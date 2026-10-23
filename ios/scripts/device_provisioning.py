#!/usr/bin/env python3
"""Renew near-expiry development profiles, and verify the profile actually embedded in the app."""
import argparse
import datetime as dt
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

UTC = dt.timezone.utc
MIN_VALIDITY = dt.timedelta(days=2)


def decode(path):
    result = subprocess.run(['security', 'cms', '-D', '-i', str(path)], capture_output=True)
    if result.returncode:
        raise RuntimeError(f'无法读取描述文件：{path.name}')
    return plistlib.loads(result.stdout)


def expiry(profile):
    value = profile.get('ExpirationDate')
    if not isinstance(value, dt.datetime):
        raise RuntimeError('描述文件缺少有效的到期时间。')
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)


def matches(profile, bundle_id, team_id):
    return (profile.get('Entitlements', {}).get('application-identifier') == team_id + '.' + bundle_id
            and team_id in profile.get('TeamIdentifier', []))


def describe(profile, now):
    end = expiry(profile)
    hours = (end - now).total_seconds() / 3600
    local = end.astimezone(dt.timezone(dt.timedelta(hours=8))).strftime('%Y-%m-%d %H:%M')
    print(f'描述文件到期：{local}（北京时间），剩余 {hours:.1f} 小时。')


def prepare(args, now):
    roots = [Path.home() / 'Library/Developer/Xcode/UserData/Provisioning Profiles',
             Path.home() / 'Library/MobileDevice/Provisioning Profiles']
    backup = Path(args.backup_dir)
    count = 0
    for root in roots:
        for path in root.glob('*.mobileprovision'):
            profile = decode(path)
            if not matches(profile, args.bundle_id, args.team_id):
                continue
            describe(profile, now)
            if expiry(profile) - now >= MIN_VALIDITY:
                continue
            # Only move this app/team's near-expiry local cache; keep a recoverable private copy.
            backup.mkdir(parents=True, exist_ok=True, mode=0o700)
            os.chmod(backup, 0o700)
            destination = backup / (now.strftime('%Y%m%dT%H%M%S') + '-' + path.name)
            if destination.exists():
                raise RuntimeError('描述文件备份已存在，本次未修改缓存。')
            shutil.copy2(path, destination)
            os.chmod(destination, 0o600)
            path.unlink()
            count += 1
    print(f'已备份并移除 {count} 个不足两天的本机描述文件缓存；接下来由 Xcode 自动申请。')


def verify(args, now):
    profile = decode(Path(args.profile))
    if not matches(profile, args.bundle_id, args.team_id):
        raise RuntimeError('安装包内描述文件与当前 App / 开发团队不匹配，停止安装。')
    if args.device not in profile.get('ProvisionedDevices', []):
        raise RuntimeError('描述文件不包含目标 iPhone，停止安装。')
    describe(profile, now)
    if expiry(profile) - now < MIN_VALIDITY:
        raise RuntimeError('Apple 返回的描述文件有效期仍不足两天，停止安装。请在 Xcode 账号设置检查开发账号和自动签名后重试。')
    print('签名有效期检查通过，可以覆盖安装并保留本机数据。')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['prepare', 'verify'])
    parser.add_argument('--bundle-id', required=True)
    parser.add_argument('--team-id', required=True)
    parser.add_argument('--backup-dir')
    parser.add_argument('--profile')
    parser.add_argument('--device')
    args = parser.parse_args()
    if args.mode == 'prepare' and not args.backup_dir:
        parser.error('prepare requires --backup-dir')
    if args.mode == 'verify' and (not args.profile or not args.device):
        parser.error('verify requires --profile and --device')
    try:
        (prepare if args.mode == 'prepare' else verify)(args, dt.datetime.now(UTC))
    except (RuntimeError, OSError, ValueError, plistlib.InvalidFileException) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
