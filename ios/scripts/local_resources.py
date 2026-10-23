#!/usr/bin/env python3
"""Pack and restore local App configuration, databases and artwork."""
import argparse
from contextlib import closing
import hashlib
import hmac
from functools import lru_cache
import json
import os
import re
from pathlib import Path, PurePosixPath
import shutil
import sqlite3
import stat
import struct
import time
import urllib.parse
import urllib.request
import zlib
import tempfile
import zipfile

PROJECT_ROOT = Path(__file__).resolve().parents[2]
RESOURCE_ROOTS = ('.private', 'ios/Vrains/CardData', 'ios/Vrains/Assets.xcassets')
EXCLUDED_RESOURCES = frozenset({'.private/signing.xcconfig'})
ARTWORKS = 'ios/Vrains/CardData/NeuronArtworks'
MANIFEST = 'manifest.json'
SCHEMA = 'vrains-local-resources-v1'

PRIVATE_CONFIG_FIELDS = (
    'officialDatabaseOrigin',
    'localizedDatabaseOrigin',
    'marketplaceOrigin',
    'translationOrigin',
    'clockOrigin',
    'businessRefererOrigin',
    'businessOrigin',
    'mapsOrigin',
    'artworkDownloadOrigin',
    'artworkManifestOrigin',
    'newsImageOrigin',
    'businessSignatureKey',
    'businessSignatureIV',
    'captchaKey',
    'captchaIV',
    'neuronAESKey',
    'neuronAESIV',
    'neuronFilenameHMACKey',
    'businessReferer',
    'businessUserAgent',
    'jhsUserAgent',
    'localizedOfficialDatabaseOrigin',
    'developmentResourcesOrigin',
    'artworkFullArchiveURL',
)


def private_config_path(root=PROJECT_ROOT):
    return Path(os.environ.get('EXODIA_PRIVATE_CONFIG', root / '.private/config.json'))


@lru_cache(maxsize=1)
def _config_values():
    try:
        values = json.loads(private_config_path().read_text())
        if not isinstance(values, dict):
            raise ValueError('Configuration must be a JSON object')
        return values
    except (OSError, ValueError) as error:
        raise RuntimeError('Missing or invalid private configuration; see ios/README.md') from error


def config_value(key):
    """Shared configuration reader for local development tools."""
    value = _config_values().get(key)
    if not isinstance(value, str) or not value or value == 'REPLACE_LOCALLY':
        raise RuntimeError('Missing private configuration field: ' + key)
    return value


def validate_private_config(path):
    """Validate build configuration without printing private values."""
    values = json.loads(Path(path).read_text())
    if not isinstance(values, dict):
        raise ValueError('Configuration must be a JSON object')
    for key in PRIVATE_CONFIG_FIELDS:
        value = values.get(key)
        if not isinstance(value, str) or not value or value == 'REPLACE_LOCALLY':
            raise ValueError('Missing private configuration field: ' + key)
        if key.endswith(('Origin', 'URL')) or key == 'businessReferer':
            url = urllib.parse.urlparse(value)
            if url.scheme != 'https' or not url.hostname:
                raise ValueError('Invalid HTTPS configuration field: ' + key)
    for key, size in {'businessSignatureKey': 24, 'businessSignatureIV': 8,
                      'captchaKey': 24, 'captchaIV': 8,
                      'neuronAESKey': 32, 'neuronAESIV': 16}.items():
        if len(values[key].encode()) != size:
            raise ValueError('Invalid key or IV length: ' + key)



def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def resource_path(name):
    path = PurePosixPath(name)
    if not name or '\\' in name or path.is_absolute() or '..' in path.parts or str(path) != name:
        raise ValueError('Invalid resource path: ' + name)
    if not any(path.is_relative_to(PurePosixPath(base)) and str(path) != base for base in RESOURCE_ROOTS):
        raise ValueError('Path outside App resource directories: ' + name)
    return path


def check_destination(root, relative):
    target = root.joinpath(*relative.parts)
    for path in [target, *target.parents]:
        if path == root:
            break
        if path.is_symlink():
            raise ValueError('Symbolic links are not supported: ' + str(relative))
    return target


def pack(root, output):
    root = root.resolve()
    output = output.resolve()
    if output.exists():
        raise ValueError('Archive already exists; choose a new --output path')
    files = []
    for base in RESOURCE_ROOTS:
        folder = root / base
        if not folder.is_dir() or folder.is_symlink():
            raise ValueError('Missing resource directory: ' + base)
        for path in sorted(folder.rglob('*')):
            if path.relative_to(root).as_posix() in EXCLUDED_RESOURCES:
                continue
            if path.is_symlink():
                raise ValueError('Symbolic links are not supported: ' + str(path.relative_to(root)))
            if path.is_relative_to(root / ARTWORKS):
                continue
            if path.is_file() and path.name != '.DS_Store' and not path.name.endswith(('-wal', '-shm', '-journal')):
                files.append(path)
    for name in ('.private/config.json', '.private/jhs-profile.json'):
        if not (root / name).is_file():
            raise ValueError('Missing local configuration: ' + name)
    for base in RESOURCE_ROOTS:
        if output.is_relative_to(root / base):
            raise ValueError('Archive must be outside resource directories')
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='vrains-pack-', dir=output.parent) as temporary:
        temporary = Path(temporary)
        archive = temporary / 'resources.zip'
        manifest = {'schema': SCHEMA, 'files': [], 'downloads': []}
        if (root / 'ios/Vrains/CardData/neuron-ja.sqlite').is_file():
            config = json.loads((root / '.private/config.json').read_text())
            if not config.get('artworkFullArchiveURL'):
                raise ValueError('Missing artworkFullArchiveURL in local configuration')
            manifest['downloads'].append('neuron-full-artworks')
        with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=1, allowZip64=True) as bundle:
            for path in files:
                name = path.relative_to(root).as_posix()
                source = path
                # Backup includes committed WAL data and gives each database a consistent snapshot.
                if path.suffix.lower() in ('.sqlite', '.db'):
                    source = temporary / 'database-snapshot'
                    source.unlink(missing_ok=True)
                    with closing(sqlite3.connect(path.as_uri() + '?mode=ro', uri=True)) as database:
                        with closing(sqlite3.connect(source)) as snapshot:
                            database.backup(snapshot)
                before = source.stat()
                checksum = hashlib.sha256()
                with source.open('rb') as stream, bundle.open(name, 'w', force_zip64=True) as target:
                    for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                        checksum.update(chunk)
                        target.write(chunk)
                after = source.stat()
                if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
                    raise ValueError('Resource changed during packaging: ' + name)
                manifest['files'].append({'path': name, 'size': before.st_size, 'sha256': checksum.hexdigest()})
            bundle.writestr(MANIFEST, json.dumps(manifest, indent=2))
        os.chmod(archive, 0o600)
        # Do not overwrite an existing archive, including one created during packaging.
        os.link(archive, output)
    print('Packed {} resources: {}'.format(len(files), output))


def unpack(root, archive, force=False):
    root = root.resolve()
    if not root.is_dir():
        raise ValueError('Project directory does not exist')
    with tempfile.TemporaryDirectory(prefix='vrains-unpack-', dir=root) as temporary:
        temporary = Path(temporary)
        with zipfile.ZipFile(archive) as bundle:
            names = bundle.namelist()
            if len(names) != len(set(names)) or names.count(MANIFEST) != 1:
                raise ValueError('Duplicate entries or missing resource manifest')
            if bundle.getinfo(MANIFEST).file_size > 32 * 1024 * 1024:
                raise ValueError('Resource manifest is too large')
            manifest = json.loads(bundle.read(MANIFEST))
            if manifest.get('schema') != SCHEMA or not isinstance(manifest.get('files'), list):
                raise ValueError('Unsupported resource archive')
            downloads = manifest.get('downloads', [])
            if downloads not in ([], ['neuron-full-artworks']):
                raise ValueError('Unsupported resource download task')
            records = manifest['files']
            expected = [entry['path'] for entry in records]
            if len(expected) != len(set(expected)) or set(names) != set(expected) | {MANIFEST}:
                raise ValueError('Archive entries do not match manifest')
            pending = []
            skipped = 0
            for entry in records:
                relative = resource_path(entry['path'])
                info = bundle.getinfo(entry['path'])
                if stat.S_ISLNK(info.external_attr >> 16) or info.is_dir() or info.file_size != entry['size']:
                    raise ValueError('Invalid resource entry: ' + entry['path'])
                # Older archives may contain a signing identity; never restore it.
                if entry['path'] in EXCLUDED_RESOURCES:
                    checksum = hashlib.sha256()
                    with bundle.open(info) as source:
                        for chunk in iter(lambda: source.read(1024 * 1024), b''):
                            checksum.update(chunk)
                    if checksum.hexdigest() != entry['sha256']:
                        raise ValueError('Resource checksum mismatch: ' + entry['path'])
                    skipped += 1
                    continue
                destination = check_destination(root, relative)
                if destination.exists() and not destination.is_file():
                    raise ValueError('Destination is not a file: ' + entry['path'])
                staged = temporary.joinpath(*relative.parts)
                staged.parent.mkdir(parents=True, exist_ok=True)
                with bundle.open(info) as source, staged.open('wb') as target:
                    shutil.copyfileobj(source, target, 1024 * 1024)
                if digest(staged) != entry['sha256']:
                    raise ValueError('Resource checksum mismatch: ' + entry['path'])
                if destination.exists() and digest(destination) == entry['sha256']:
                    continue
                if destination.exists() and not force:
                    raise ValueError('Existing resource differs; use --force to replace: ' + entry['path'])
                pending.append((relative, staged))
        # Verify the entire archive before replacing any project files.
        for relative, staged in pending:
            destination = check_destination(root, relative)
            destination.parent.mkdir(parents=True, exist_ok=True)
            if relative.parts[0] == '.private':
                os.chmod(root / '.private', 0o700)
            os.chmod(staged, 0o600 if relative.parts[0] == '.private' else 0o644)
            os.replace(staged, destination)
    print('Restored {} resources; {} already identical; {} machine-specific files skipped'.format(
        len(pending), len(records) - len(pending) - skipped, skipped))
    if downloads:
        restore_artworks(root, force)


def download_archive(url, cache):
    """Download the complete versioned ZIP, resuming an interrupted transfer."""
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != 'https' or not parsed.hostname:
        raise ValueError('Full artwork archive must use HTTPS')
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / ('neuron-full-' + hashlib.sha256(url.encode()).hexdigest()[:16] + '.zip')
    if archive.is_file():
        try:
            with zipfile.ZipFile(archive) as existing:
                if existing.testzip() is None:
                    return archive
        except (OSError, zipfile.BadZipFile, RuntimeError):
            pass
        archive.unlink()
    partial = archive.with_suffix('.zip.part')
    offset = partial.stat().st_size if partial.exists() else 0
    headers = {'Accept-Encoding': 'identity'}
    if offset:
        headers['Range'] = 'bytes={}-'.format(offset)
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=90) as response:
        final = urllib.parse.urlparse(response.geturl())
        if final.scheme != 'https' or final.hostname != parsed.hostname:
            raise ValueError('Unexpected artwork download redirect')
        if offset and response.status == 200:
            offset = 0  # Server ignored resume: safely restart the full transfer.
        if response.status != (206 if offset else 200):
            raise ValueError('Unexpected artwork download status')
        if offset:
            content_range = response.headers.get('Content-Range', '')
            match = re.fullmatch(r'bytes (\d+)-(\d+)/(\d+)', content_range)
            if not match or int(match[1]) != offset or int(match[2]) != int(match[3]) - 1:
                raise ValueError('Invalid resumed artwork download range')
        length = response.headers.get('Content-Length')
        total = offset + int(length) if length else None
        received, last_report = offset, time.monotonic()
        with partial.open('ab' if offset else 'wb') as target:
            os.chmod(partial, 0o600)
            for chunk in iter(lambda: response.read(1024 * 1024), b''):
                target.write(chunk)
                received += len(chunk)
                if time.monotonic() - last_report >= 5:
                    print('Downloading full artwork ZIP: {:.0f} MiB{}'.format(received / 1048576, ' / {:.0f} MiB'.format(total / 1048576) if total else ''), flush=True)
                    last_report = time.monotonic()
        if total is not None and received != total:
            raise ValueError('Incomplete full artwork download; rerun unpack to resume')
    try:
        with zipfile.ZipFile(partial) as downloaded:
            if downloaded.testzip() is not None:
                raise ValueError('Downloaded artwork ZIP checksum mismatch')
    except (zipfile.BadZipFile, ValueError):
        partial.unlink()
        raise ValueError('Downloaded artwork archive failed ZIP verification')
    os.replace(partial, archive)
    return archive


def decode_artwork(payload, key, iv):
    if payload.startswith(b'\x89PNG\r\n\x1a\n'):
        png = payload
    else:
        from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
        if not payload or len(payload) % 16 or len(payload) > 16 * 1024 * 1024:
            raise ValueError('Invalid encrypted artwork size')
        decryptor = Cipher(algorithms.AES(key), modes.CBC(iv)).decryptor()
        plain = decryptor.update(payload) + decryptor.finalize()
        if len(plain) < 28 or plain[:17] != bytes.fromhex('0001000000ffffffff0100000000000000') or plain[17] != 15 or plain[26] != 2:
            raise ValueError('Invalid artwork serialization')
        size = struct.unpack_from('<I', plain, 22)[0]
        if size > min(16 * 1024 * 1024, len(plain) - 28) or plain[27 + size] != 11 or any(plain[28 + size:]):
            raise ValueError('Invalid artwork payload')
        png = plain[27:27 + size]
    if not png.startswith(b'\x89PNG\r\n\x1a\n'):
        raise ValueError('Decoded artwork is not PNG')
    position, first, ended = 8, True, False
    while position + 12 <= len(png):
        size = struct.unpack_from('>I', png, position)[0]
        end = position + 12 + size
        if end > len(png):
            raise ValueError('Truncated artwork PNG')
        kind = png[position + 4:position + 8]
        if first:
            if kind != b'IHDR' or size != 13:
                raise ValueError('Invalid artwork PNG header')
            width, height = struct.unpack_from('>II', png, position + 8)
            if not (0 < width <= 4096 and 0 < height <= 4096):
                raise ValueError('Invalid artwork dimensions')
            first = False
        if zlib.crc32(png[position + 4:end - 4]) & 0xffffffff != struct.unpack_from('>I', png, end - 4)[0]:
            raise ValueError('Artwork PNG checksum mismatch')
        position = end
        if kind == b'IEND':
            ended = size == 0 and end == len(png)
            break
    if not ended:
        raise ValueError('Missing artwork PNG end record')
    return png


def restore_artworks(root, force=False):
    """Fetch one full ZIP, then reconstruct the App's original offline PNG layout."""
    try:
        import cryptography.hazmat.primitives.ciphers  # Optional only for pack/embed-config.
    except ImportError as error:
        raise ValueError('Artwork restoration requires: python3 -m pip install cryptography') from error
    config = json.loads((root / '.private/config.json').read_text())
    url = config['artworkFullArchiveURL']
    key, iv = config['neuronAESKey'].encode(), config['neuronAESIV'].encode()
    hash_key = config['neuronFilenameHMACKey'].encode()
    if len(key) != 32 or len(iv) != 16:
        raise ValueError('Invalid local artwork decryption configuration')
    database = root / 'ios/Vrains/CardData/neuron-ja.sqlite'
    with closing(sqlite3.connect(database.resolve().as_uri() + '?mode=ro', uri=True)) as db:
        pairs = db.execute("SELECT card_id,card_image_id FROM CardSet WHERE language='ja' UNION SELECT card_id,min_card_image_id FROM MstCardInfo WHERE language='ja'").fetchall()
    desired = {hmac.new(hash_key, '{}_{}.png'.format(cid, image).encode(), hashlib.sha256).hexdigest().upper(): (cid, image) for cid, image in pairs if image > 0}
    archive = download_archive(url, root / '.local-resources/downloads')
    output = check_destination(root, PurePosixPath(ARTWORKS))
    output.mkdir(parents=True, exist_ok=True)
    result = {'source': url, 'count': 0, 'bytes': 0, 'unavailable': []}
    with zipfile.ZipFile(archive) as bundle:
        if len(bundle.namelist()) != len(set(bundle.namelist())):
            raise ValueError('Duplicate artwork ZIP entries')
        entries = {info.filename: info for info in bundle.infolist()}
        for name, (cid, image) in desired.items():
            info = entries.get(name)
            if info is None:
                result['unavailable'].append([cid, image])
                continue
            if info.file_size > 16 * 1024 * 1024 or info.is_dir():
                raise ValueError('Invalid artwork ZIP entry')
            png = decode_artwork(bundle.read(info), key, iv)
            target = check_destination(root, PurePosixPath(ARTWORKS) / '{}-{}-{}-{}.png'.format(cid, image, info.CRC, info.file_size))
            if target.exists() and target.read_bytes() != png and not force:
                raise ValueError('Existing artwork differs; use --force to replace: ' + target.name)
            if not target.exists() or target.read_bytes() != png:
                with tempfile.NamedTemporaryFile(dir=output, prefix='.artwork-', delete=False) as temporary:
                    temporary.write(png)
                    staged = Path(temporary.name)
                try:
                    os.replace(staged, target)
                finally:
                    staged.unlink(missing_ok=True)
            result['count'] += 1
            result['bytes'] += len(png)
            if result['count'] % 1000 == 0:
                print('Restored {} offline artworks'.format(result['count']), flush=True)
    manifest = check_destination(root, PurePosixPath(ARTWORKS) / 'manifest.json')
    manifest.write_text(json.dumps(result, indent=2) + '\n')
    if result['unavailable']:
        raise ValueError('{} artworks absent from the full ZIP; restored {} available images'.format(len(result['unavailable']), result['count']))
    print('Offline artwork restoration complete: {} images'.format(result['count']))


def embed_config(root):
    """Internal Xcode build phase; runtime resources are copied by Xcode itself."""
    config = private_config_path(root)
    profile = Path(os.environ.get('JHS_PROFILE_SOURCE', root / '.private/jhs-profile.json'))
    validate_private_config(config)
    data = json.loads(profile.read_text())
    if data.get('schema') != 'jhs-jm-random-v1' or data.get('version') != 1:
        raise ValueError('Invalid JHS profile schema')
    if len(bytes.fromhex(data['prefixXorHex'])) != 17 or len(bytes.fromhex(data['blockXorHex'])) != 18 or '0' not in data['selectors']:
        raise ValueError('Invalid JHS profile parameters')
    for selector in data['selectors'].values():
        if len(bytes.fromhex(selector['masterKeyHex'])) != 16 or len(bytes.fromhex(selector['ivPrefixHex'])) != 15:
            raise ValueError('Invalid JHS profile key lengths')
    destination = Path(os.environ['TARGET_BUILD_DIR']) / os.environ['UNLOCALIZED_RESOURCES_FOLDER_PATH']
    destination.mkdir(parents=True, exist_ok=True)
    for source, name in [(profile, 'JHSProtocolProfile.json'), (config, 'PrivateConfiguration.json')]:
        shutil.copyfile(source, destination / name)
        os.chmod(destination / name, 0o600)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project-root', type=Path, default=PROJECT_ROOT, help='Project directory (default: this checkout)')
    commands = parser.add_subparsers(dest='command', required=True)
    packaging = commands.add_parser('pack', help='Package local configuration, databases and artwork')
    packaging.add_argument('--output', type=Path, help='Destination ZIP (default: .local-resources/vrains-resources.zip)')
    restore = commands.add_parser('unpack', help='Restore local resources, download the full artwork ZIP and reconstruct offline images')
    restore.add_argument('archive', type=Path)
    restore.add_argument('--force', action='store_true', help='Replace existing resources that differ')
    commands.add_parser('embed-config', help='Internal Xcode configuration-copy step')
    args = parser.parse_args()
    try:
        if args.command == 'pack':
            pack(args.project_root, args.output or args.project_root / '.local-resources/vrains-resources.zip')
        elif args.command == 'unpack':
            unpack(args.project_root, args.archive, args.force)
        else:
            embed_config(args.project_root)
    except (OSError, ValueError, KeyError, TypeError, sqlite3.Error, zipfile.BadZipFile) as error:
        # Avoid exposing invalid configuration values through exception messages.
        if args.command == 'embed-config':
            parser.exit(1, 'error: Invalid or missing local configuration; see ios/README.md\n')
        parser.exit(1, 'error: {}\n'.format(error))


if __name__ == '__main__':
    main()
