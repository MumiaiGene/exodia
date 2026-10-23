import Foundation
import SwiftUI
import UIKit
import ImageIO
import CommonCrypto
import CryptoKit
import SQLite3
import zlib

struct NeuronImageVariant: Identifiable, Sendable {
    let ciid: Int64
    var id: Int64 { ciid }
}

enum NeuronError: Error { case invalidArchive, invalidResponse, invalidPayload, database, unsupportedCompression }

/// Limits the response before consuming its body (a server ignoring Range must never download the full image ZIP).
protocol NeuronTransport: Sendable {
    func data(_ url: URL, range: String?, etag: String?, limit: Int) async throws -> (Data, HTTPURLResponse)
}

extension NeuronTransport {
    func data(_ url: URL, limit: Int) async throws -> (Data, HTTPURLResponse) { try await data(url,range:nil,etag:nil,limit:limit) }
    func data(_ url: URL, range: String, limit: Int) async throws -> (Data, HTTPURLResponse) { try await data(url,range:range,etag:nil,limit:limit) }
}

struct NeuronHTTP: NeuronTransport {
    func data(_ url: URL, range: String? = nil, etag: String? = nil, limit: Int) async throws -> (Data, HTTPURLResponse) {
        guard url.scheme == "https", ["d1xxetyyss4ajs.cloudfront.net", "yocg-ap.cs.konami.net"].contains(url.host ?? "") else { throw NeuronError.invalidResponse }
        var request = URLRequest(url: url); request.timeoutInterval = 45
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if let range { request.setValue("bytes=\(range)", forHTTPHeaderField: "Range") }
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-Match") }
        let (stream, response) = try await URLSession.shared.bytes(for: request)
        defer { stream.task.cancel() }
        var expectedRangeLength: Int?
        guard let response = response as? HTTPURLResponse, response.url?.host == url.host,
              response.statusCode == (range == nil ? 200 : 206),
              response.expectedContentLength <= limit else { throw NeuronError.invalidResponse }
        if let etag, response.value(forHTTPHeaderField:"ETag") != etag { throw NeuronError.invalidResponse }
        if range != nil {
            guard let header = response.value(forHTTPHeaderField: "Content-Range"), header.hasPrefix("bytes "), !header.contains("*") else { throw NeuronError.invalidResponse }
            let parts = header.dropFirst(6).split(separator: "/")
            let bounds = parts.first?.split(separator: "-").compactMap { Int($0) } ?? []
            guard parts.count == 2, bounds.count == 2, let total = Int(parts[1]), bounds[0] >= 0, bounds[1] < total,
                  bounds[1] >= bounds[0], bounds[1]-bounds[0]+1 <= limit else { throw NeuronError.invalidResponse }
            expectedRangeLength = bounds[1]-bounds[0]+1
            if let range, range.hasPrefix("-"), let suffix = Int(range.dropFirst()) {
                guard bounds[1] == total-1, bounds[0] == max(0,total-suffix) else { throw NeuronError.invalidResponse }
            }
            if let range, !range.hasPrefix("-") {
                guard range == "\(bounds[0])-\(bounds[1])" else { throw NeuronError.invalidResponse }
            }
        }
        var bytes = Data()
        for try await byte in stream {
            guard bytes.count < limit else { throw NeuronError.invalidResponse }
            bytes.append(byte)
        }
        if let expectedRangeLength, bytes.count != expectedRangeLength { throw NeuronError.invalidResponse }
        if response.expectedContentLength >= 0, bytes.count != response.expectedContentLength { throw NeuronError.invalidResponse }
        return (bytes, response)
    }
}

struct NeuronZIPEntry: Codable, Sendable {
    let name: String
    let size: Int
    let compressed_size: Int
    let offset: Int
    let compression: Int
    let crc: UInt32
}
struct NeuronArchive: Codable, Sendable {
    let url: URL
    var etag: String?
    let entries: [NeuronZIPEntry]
}
struct NeuronIndex: Codable, Sendable {
    var version: String
    var archives: [NeuronArchive]
}

extension Data {
    fileprivate func neuronUInt(_ offset: Int, _ length: Int) throws -> Int {
        guard offset >= 0, length > 0, offset <= count-length else { throw NeuronError.invalidArchive }
        return (0..<length).reduce(0) { $0 | (Int(self[offset+$1]) << ($1*8)) }
    }
}

enum NeuronFormat {
    static func filename(cid: Int64, image: Int64) -> String {
        let key = SymmetricKey(data: Data(PrivateConfiguration.value("neuronFilenameHMACKey").utf8))
        return HMAC<SHA256>.authenticationCode(for: Data("\(cid)_\(image).png".utf8), using: key).map { String(format: "%02X", $0) }.joined()
    }
    static func decode(_ encrypted: Data) throws -> Data {
        guard !encrypted.isEmpty, encrypted.count % 16 == 0, encrypted.count <= 200*1024*1024 else { throw NeuronError.invalidPayload }
        let key = Array(PrivateConfiguration.value("neuronAESKey").utf8), iv = Array(PrivateConfiguration.value("neuronAESIV").utf8)
        var output = Data(count: encrypted.count+16), written = 0
        let capacity = output.count
        let status = output.withUnsafeMutableBytes { target in encrypted.withUnsafeBytes { source in
            CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), 0, key, key.count, iv, source.baseAddress, encrypted.count, target.baseAddress, capacity, &written)
        } }
        guard status == kCCSuccess else { throw NeuronError.invalidPayload }
        output.count = written
        guard output.count >= 28, Array(output.prefix(17)) == [0,1,0,0,0,255,255,255,255,1,0,0,0,0,0,0,0], output[17] == 15, output[26] == 2 else { throw NeuronError.invalidPayload }
        let length = try output.neuronUInt(22,4)
        guard length <= output.count-28, output[27+length] == 11, output.dropFirst(28+length).allSatisfy({$0 == 0}) else { throw NeuronError.invalidPayload }
        return output.subdata(in: 27..<27+length)
    }
    static func directory(_ data: Data, count: Int) throws -> [NeuronZIPEntry] {
        guard count <= 100_000 else { throw NeuronError.invalidArchive }
        var cursor = 0, entries: [NeuronZIPEntry] = []
        for _ in 0..<count {
            guard try data.neuronUInt(cursor,4) == 0x02014b50, try data.neuronUInt(cursor+8,2) & 1 == 0 else { throw NeuronError.invalidArchive }
            let n = try data.neuronUInt(cursor+28,2), extra = try data.neuronUInt(cursor+30,2), comment = try data.neuronUInt(cursor+32,2)
            guard cursor+46+n+extra+comment <= data.count, let name = String(data: data.subdata(in: cursor+46..<cursor+46+n), encoding: .utf8) else { throw NeuronError.invalidArchive }
            entries.append(try NeuronZIPEntry(name:name,size:data.neuronUInt(cursor+24,4),compressed_size:data.neuronUInt(cursor+20,4),offset:data.neuronUInt(cursor+42,4),compression:data.neuronUInt(cursor+10,2),crc:UInt32(data.neuronUInt(cursor+16,4))))
            cursor += 46+n+extra+comment
        }
        guard cursor == data.count, Set(entries.map(\.name)).count == entries.count else { throw NeuronError.invalidArchive }
        return entries
    }
    static func unpack(_ compressed: Data, entry: NeuronZIPEntry) throws -> Data {
        guard entry.size > 0, entry.size <= 200*1024*1024, compressed.count == entry.compressed_size else { throw NeuronError.invalidArchive }
        let bytes: Data
        if entry.compression == 0 { bytes = compressed }
        else if entry.compression == 8 {
            var output = Data(count: entry.size), stream = z_stream()
            guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw NeuronError.invalidArchive }
            defer { inflateEnd(&stream) }
            let status = output.withUnsafeMutableBytes { dst in compressed.withUnsafeBytes { src in
                stream.next_in = UnsafeMutablePointer(mutating: src.bindMemory(to: Bytef.self).baseAddress); stream.avail_in = uInt(compressed.count)
                stream.next_out = dst.bindMemory(to: Bytef.self).baseAddress; stream.avail_out = uInt(entry.size)
                return inflate(&stream, Z_FINISH)
            } }
            guard status == Z_STREAM_END, stream.total_out == entry.size, stream.total_in == compressed.count else { throw NeuronError.invalidArchive }
            bytes = output
        } else { throw NeuronError.unsupportedCompression }
        let checksum = bytes.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(bytes.count)) }
        guard bytes.count == entry.size, UInt32(checksum) == entry.crc else { throw NeuronError.invalidArchive }
        return bytes
    }
}

private final class NeuronDB: @unchecked Sendable {
    let pointer: OpaquePointer
    init(_ url: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else { if let db { sqlite3_close(db) }; throw NeuronError.database }
        pointer = db
    }
    deinit { sqlite3_close(pointer) }
    func execute(_ sql: String) throws {
        guard sqlite3_exec(pointer, sql, nil, nil, nil) == SQLITE_OK else { throw NeuronError.database }
    }
    func rows(_ sql: String) throws -> [[String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(pointer, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw NeuronError.database }
        defer { sqlite3_finalize(statement) }
        var result: [[String]] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW else { throw NeuronError.database }
            result.append((0..<sqlite3_column_count(statement)).map { column in sqlite3_column_text(statement,column).map { String(cString:$0) } ?? "" })
        }
    }
    func patch(_ statements: [String], version: String) throws {
        guard version.allSatisfy({ $0.isNumber || $0 == "." }) else { throw NeuronError.database }
        try execute("BEGIN IMMEDIATE")
        do {
            // Remote data may only read/write the two isolated mapping tables, never the App card library.
            sqlite3_set_authorizer(pointer, { _, action, first, _, _, _ in
                let table = first.map { String(cString: $0) } ?? ""
                switch action {
                case SQLITE_INSERT, SQLITE_UPDATE, SQLITE_DELETE, SQLITE_READ: return ["CardSet","MstCardInfo"].contains(table) ? SQLITE_OK : SQLITE_DENY
                case SQLITE_SELECT: return SQLITE_OK
                default: return SQLITE_DENY
                }
            }, nil)
            do { for sql in statements { try execute(sql) } }
            catch { sqlite3_set_authorizer(pointer,nil,nil); throw error }
            sqlite3_set_authorizer(pointer,nil,nil)
            try execute("DELETE FROM CardSet WHERE language!='ja'; DELETE FROM MstCardInfo WHERE language!='ja'; INSERT OR REPLACE INTO NeuronState VALUES ('version','\(version)'); COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
}

actor NeuronArtworkStore {
    static let shared = NeuronArtworkStore()
    private let directory: URL
    private let bundledArtworks:URL?
    private var mappingURL:URL?
    private var artworkProgress:(@Sendable(String)async->Void)?
    private let http: any NeuronTransport
    private var db: NeuronDB?
    private var index: NeuronIndex?
    private var lookup: [String:(NeuronArchive,NeuronZIPEntry)] = [:]
    private var downloads: [String:(UUID,Task<Data,Error>)] = [:]
    private var activeImages = 0
    private var imageWaiters: [CheckedContinuation<Void,Never>] = []
    private var updateTask: Task<Bool,Error>?
    private var lastCheck = Date.distantPast
    private var generation = 0
    init(directory: URL? = nil, transport: any NeuronTransport = NeuronHTTP(), bundledArtworks:URL?=Bundle.main.url(forResource:"NeuronArtworks",withExtension:nil,subdirectory:"CardData")) {
        self.bundledArtworks=bundledArtworks
        self.http = transport
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory,in: .userDomainMask)[0].appendingPathComponent("Exodia/Neuron")
    }
    private func open() throws -> NeuronDB {
        if let db { return db }
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let legacy=directory.appendingPathComponent("images"),permanent=directory.appendingPathComponent("artworks")
        if FileManager.default.fileExists(atPath:legacy.path),!FileManager.default.fileExists(atPath:permanent.path) {try FileManager.default.moveItem(at:legacy,to:permanent)}
        var base=directory
        let pointer=directory.appendingPathComponent("active.json")
        if let bytes=try? Data(contentsOf:pointer),let revision=try? JSONDecoder().decode(String.self,from:bytes),UUID(uuidString:revision) != nil {
            base=directory.appendingPathComponent("revisions/"+revision,isDirectory:true)
        }
        let target = base.appendingPathComponent("mapping.sqlite")
        if !FileManager.default.fileExists(atPath:target.path) {
            guard let seed = Bundle.main.url(forResource:"neuron-ja",withExtension:"sqlite",subdirectory:"CardData") else { throw NeuronError.database }
            try FileManager.default.copyItem(at:seed,to:target)
        }
        var connection = try NeuronDB(target)
        mappingURL=target
        let saved = base.appendingPathComponent("index.json")
        guard let seed = Bundle.main.url(forResource:"neuron-index",withExtension:"json",subdirectory:"CardData") else { throw NeuronError.database }
        var loaded = try JSONDecoder().decode(NeuronIndex.self,from:(try? Data(contentsOf:saved)) ?? Data(contentsOf:seed))
        let bundledIndex=try JSONDecoder().decode(NeuronIndex.self,from:Data(contentsOf:seed))
        // An App upgrade brings a complete new offline baseline; do not keep an older disk index.
        if bundledArtworks != nil,Self.newer(bundledIndex.version,than:loaded.version) {
            guard let seedDB=Bundle.main.url(forResource:"neuron-ja",withExtension:"sqlite",subdirectory:"CardData") else {throw NeuronError.database}
            let revision=UUID().uuidString,base=directory.appendingPathComponent("revisions/"+revision,isDirectory:true)
            try FileManager.default.createDirectory(at:base,withIntermediateDirectories:true)
            let mapping=base.appendingPathComponent("mapping.sqlite")
            try FileManager.default.copyItem(at:seedDB,to:mapping)
            let newConnection=try NeuronDB(mapping)
            try JSONEncoder().encode(bundledIndex).write(to:base.appendingPathComponent("index.json"),options:.atomic)
            try JSONEncoder().encode(revision).write(to:directory.appendingPathComponent("active.json"),options:.atomic)
            connection=newConnection;mappingURL=mapping;loaded=bundledIndex
        }
        publish(loaded); db = connection
        // Delete the retired SAMPLE cache once; it is never read by this pipeline.
        let old = FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent("ExodiaCardImages")
        try? FileManager.default.removeItem(at:old)
        return connection
    }
    private func publish(_ value: NeuronIndex) {
        index = value; lookup.removeAll(keepingCapacity:true)
        for archive in value.archives { for entry in archive.entries { lookup[entry.name] = (archive,entry) } }
    }
    func variants(cid: Int64) throws -> [NeuronImageVariant] {
        let db = try open()
        let values = try db.rows("SELECT image_id FROM (SELECT card_image_id AS image_id FROM CardSet WHERE language='ja' AND card_id=\(cid) UNION SELECT min_card_image_id FROM MstCardInfo WHERE language='ja' AND card_id=\(cid)) ORDER BY CASE WHEN image_id=(SELECT min_card_image_id FROM MstCardInfo WHERE language='ja' AND card_id=\(cid)) THEN 0 ELSE 1 END,image_id")
        return values.compactMap { row in row.first.flatMap(Int64.init).flatMap { $0 > 0 ? NeuronImageVariant(ciid:$0) : nil } }
    }
    func data(cid: Int64, ciid: Int64? = nil) async throws -> Data {
        let variants = try variants(cid:cid)
        let selected = ciid ?? variants.first?.ciid
        guard let selected, variants.contains(where:{$0.ciid == selected}), let (archive,entry) = lookup[NeuronFormat.filename(cid:cid,image:selected)] else { throw NeuronError.invalidPayload }
        let key = "\(cid)-\(selected)-\(entry.crc)-\(entry.size)"
        if let bundled=bundledArtworks?.appendingPathComponent(key+".png"),let bytes=try? Data(contentsOf:bundled),Self.validPNG(bytes) {return bytes}
        let cache = directory.appendingPathComponent("artworks",isDirectory:true), file = cache.appendingPathComponent(key+".png")
        if let bytes = try? Data(contentsOf:file), Self.validPNG(bytes) { return bytes }
        if let task = downloads[key] { return try await task.1.value }
        let currentGeneration = generation
        let id = UUID()
        let task = Task { try await self.loadImage(entry,archive:archive) }
        downloads[key] = (id,task)
        defer { if downloads[key]?.0 == id { downloads.removeValue(forKey:key) } }
        let bytes = try await task.value
        guard Self.validPNG(bytes) else { throw NeuronError.invalidPayload }
        if generation == currentGeneration {
            try FileManager.default.createDirectory(at:cache,withIntermediateDirectories:true)
            try bytes.write(to:file,options:.atomic)
        }
        return bytes
    }
    private func loadImage(_ entry: NeuronZIPEntry, archive: NeuronArchive) async throws -> Data {
        if activeImages >= 3 { await withCheckedContinuation { imageWaiters.append($0) } }
        else { activeImages += 1 }
        defer { if imageWaiters.isEmpty { activeImages -= 1 } else { imageWaiters.removeFirst().resume() } }
        try Task.checkCancellation()
        guard entry.size <= 16*1024*1024 else { throw NeuronError.invalidPayload }
        return try NeuronFormat.decode(await member(entry,archive:archive))
    }
    private static func validPNG(_ bytes: Data) -> Bool {
        guard bytes.starts(with:[137,80,78,71,13,10,26,10]), bytes.count <= 16*1024*1024,
              let source = CGImageSourceCreateWithData(bytes as CFData,nil), CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int else { return false }
        return width > 0 && width <= 4096 && height > 0 && height <= 4096
    }
    private func hasArtwork(_ key:String)->Bool {
        if let bundled=bundledArtworks,FileManager.default.fileExists(atPath:bundled.appendingPathComponent(key+".png").path) {return true}
        return FileManager.default.fileExists(atPath:directory.appendingPathComponent("artworks/"+key+".png").path)
    }
    private func artworkJobs(_ value:NeuronIndex,db:NeuronDB)throws->[(String,NeuronZIPEntry,NeuronArchive)] {
        let entries=Dictionary(value.archives.flatMap {archive in archive.entries.map {($0.name,($0,archive))}},uniquingKeysWith:{_,new in new})
        return try db.rows("SELECT card_id,card_image_id FROM CardSet WHERE language='ja' UNION SELECT card_id,min_card_image_id FROM MstCardInfo WHERE language='ja'").compactMap {row in
            guard row.count==2,let cid=Int64(row[0]),let ciid=Int64(row[1]),ciid>0,let (entry,archive)=entries[NeuronFormat.filename(cid:cid,image:ciid)] else {return nil}
            let key="\(cid)-\(ciid)-\(entry.crc)-\(entry.size)"
            return hasArtwork(key) ? nil:(key,entry,archive)
        }
    }
    private func persist(_ key:String,entry:NeuronZIPEntry,archive:NeuronArchive)async throws {
        let bytes=try await loadImage(entry,archive:archive)
        guard Self.validPNG(bytes) else {throw NeuronError.invalidPayload}
        let folder=directory.appendingPathComponent("artworks",isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        try bytes.write(to:folder.appendingPathComponent(key+".png"),options:.atomic)
    }
    private func persistAll(_ value:NeuronIndex,db:NeuronDB)async throws->Bool {
        let jobs=try artworkJobs(value,db:db)
        guard !jobs.isEmpty else{return false}
        try await withThrowingTaskGroup(of:Void.self) {group in
            var next=0,completed=0
            func enqueue(_ index:Int) {let job=jobs[index];group.addTask {try await self.persist(job.0,entry:job.1,archive:job.2)}}
            while next<min(3,jobs.count) {enqueue(next);next+=1}
            while try await group.next() != nil {
                completed+=1;await artworkProgress?("下载并保存 Neuron 卡图 \(completed)/\(jobs.count)")
                if next<jobs.count {enqueue(next);next+=1}
            }
        }
        return true
    }
    func synchronize(progress:@escaping @Sendable(String)async->Void)async throws->Bool {
        artworkProgress=progress;defer {artworkProgress=nil}
        return try await check(force:true)
    }
    private func archive(_ url: URL) async throws -> NeuronArchive {
        let (tail,response) = try await http.data(url,range:"-65536",limit:65536)
        guard tail.count >= 22 else { throw NeuronError.invalidArchive }
        var end: Int?
        for position in stride(from:tail.count-22,through:0,by:-1) {
            if try tail.neuronUInt(position,4) == 0x06054b50, try position+22+tail.neuronUInt(position+20,2) == tail.count { end = position; break }
        }
        guard let end, try tail.neuronUInt(end+4,2) == 0, try tail.neuronUInt(end+6,2) == 0,
              try tail.neuronUInt(end+8,2) == tail.neuronUInt(end+10,2) else { throw NeuronError.invalidArchive }
        let count = try tail.neuronUInt(end+10,2), size = try tail.neuronUInt(end+12,4), start = try tail.neuronUInt(end+16,4)
        guard count < 65535, size > 0, size < 16*1024*1024, start < 0xffffffff else { throw NeuronError.invalidArchive }
        let etag = response.value(forHTTPHeaderField:"ETag")
        let (central,_) = try await http.data(url,range:"\(start)-\(start+size-1)",etag:etag,limit:16*1024*1024)
        return try NeuronArchive(url:url,etag:etag,entries:NeuronFormat.directory(central,count:count))
    }
    private func member(_ entry: NeuronZIPEntry, archive: NeuronArchive) async throws -> Data {
        guard entry.size > 0, entry.size <= 200*1024*1024, entry.compressed_size > 0, entry.compressed_size <= 200*1024*1024 else { throw NeuronError.invalidArchive }
        let (header,_) = try await http.data(archive.url,range:"\(entry.offset)-\(entry.offset+29)",etag:archive.etag,limit:30)
        guard try header.neuronUInt(0,4) == 0x04034b50, try header.neuronUInt(6,2) & 1 == 0,
              try header.neuronUInt(8,2) == entry.compression else { throw NeuronError.invalidArchive }
        let nameLength = try header.neuronUInt(26,2), extraLength = try header.neuronUInt(28,2)
        let start = entry.offset+30+nameLength+extraLength
        let (bytes,_) = try await http.data(archive.url,range:"\(entry.offset+30)-\(start+entry.compressed_size-1)",etag:archive.etag,limit:entry.compressed_size+131070)
        guard String(data:bytes.prefix(nameLength),encoding:.utf8) == entry.name else { throw NeuronError.invalidArchive }
        return try NeuronFormat.unpack(Data(bytes.suffix(entry.compressed_size)),entry:entry)
    }
    private func installDatabase(_ entry: NeuronZIPEntry, archive: NeuronArchive, version: String, db: NeuronDB) async throws {
        let plain = try NeuronFormat.decode(await member(entry,archive:archive))
        let temporary = directory.appendingPathComponent("replacement.sqlite")
        try plain.write(to:temporary,options:.atomic)
        defer { try? FileManager.default.removeItem(at:temporary) }
        let source = try NeuronDB(temporary)
        _ = try source.rows("SELECT card_id,min_card_image_id FROM MstCardInfo LIMIT 1")
        try db.execute("ATTACH DATABASE '\(temporary.path.replacingOccurrences(of:"'",with:"''"))' AS replacement")
        do {
            try db.execute("BEGIN IMMEDIATE; DELETE FROM CardSet; DELETE FROM MstCardInfo; INSERT INTO CardSet SELECT * FROM replacement.CardSet WHERE language='ja'; INSERT INTO MstCardInfo SELECT * FROM replacement.MstCardInfo WHERE language='ja'; INSERT OR REPLACE INTO NeuronState VALUES ('version','\(version)'); COMMIT")
        } catch { try? db.execute("ROLLBACK"); try? db.execute("DETACH DATABASE replacement"); throw error }
        try db.execute("DETACH DATABASE replacement")
    }
    static func newer(_ left: String, than right: String) -> Bool {
        left.compare(right,options:.numeric) == .orderedDescending
    }
    func check(force: Bool = false) async throws -> Bool {
        if let updateTask { return try await updateTask.value }
        if !force, Date.now.timeIntervalSince(lastCheck) < 86400 { return false }
        let task = Task { try await self.refresh() }; updateTask = task
        defer { updateTask = nil }
        let changed = try await task.value; lastCheck = .now; return changed
    }
    private func refresh() async throws -> Bool {
        _ = try open()
        guard let mappingURL else {throw NeuronError.database}
        let revision=UUID().uuidString,stage=directory.appendingPathComponent("revisions/"+revision,isDirectory:true)
        try FileManager.default.createDirectory(at:stage,withIntermediateDirectories:true)
        var committed=false
        defer {if !committed {try? FileManager.default.removeItem(at:stage)}}
        let stagedMapping=stage.appendingPathComponent("mapping.sqlite")
        try FileManager.default.copyItem(at:mappingURL,to:stagedMapping)
        let db=try NeuronDB(stagedMapping)
        let (bytes,_) = try await http.data(URL(string:"\(PrivateConfiguration.value("artworkManifestOrigin"))/neuron_rest/downloadList/ocg")!,limit:2*1024*1024)
        guard let manifest = try JSONSerialization.jsonObject(with:bytes) as? [String:Any],
              let full = manifest["newFullDataDictionary"] as? [String:Any], let latest = full["lasted_version"] as? String,
              let path = full["path"] as? String, path == "full_\(latest)", latest.allSatisfy({$0.isNumber || $0 == "."}),
              let common = manifest["newCommonDataList"] as? [[String:Any]], let images = manifest["newHighImageDataList"] as? [[String:Any]], let old = index else { throw NeuronError.invalidResponse }
        var staged = old, changed = false
        // Stage mapping and index; publish them only after every Japanese PNG is durable.
        let baseline = old.archives.first?.url.deletingLastPathComponent().lastPathComponent.replacingOccurrences(of:"full_",with:"") ?? old.version
        if Self.newer(latest,than:baseline) {
            staged = NeuronIndex(version:latest,archives:[try await archive(URL(string:"\(PrivateConfiguration.value("artworkDownloadOrigin"))/ocg/\(path)/ocg_high.zip")!)])
            changed = true
        }
        for item in images.sorted(by:{Self.newer($1["version"] as? String ?? "",than:$0["version"] as? String ?? "")}) {
            guard let version = item["version"] as? String, Self.newer(version,than:staged.version), version.allSatisfy({$0.isNumber || $0 == "."}) else { continue }
            staged.archives.append(try await archive(URL(string:"\(PrivateConfiguration.value("artworkDownloadOrigin"))/ocg/\(version)/ocg_high.zip")!)); staged.version = version; changed = true
        }
        var mappingVersion = try db.rows("SELECT value FROM NeuronState WHERE key='version'").first?.first ?? "0"
        // If the server retired the deltas needed by this installation, recover from its full common snapshot.
        let oldestCommon = common.compactMap { $0["version"] as? String }.sorted { Self.newer($1,than:$0) }.first
        if Self.newer(latest,than:mappingVersion), oldestCommon.map({Self.newer($0,than:mappingVersion)}) ?? true {
            let snapshot = try await archive(URL(string:"\(PrivateConfiguration.value("artworkDownloadOrigin"))/ocg/\(path)/android.zip")!)
            guard let entry = snapshot.entries.first(where:{$0.name == "05E47DF6E20B232F8665AED3D69564FBB0F291FCA9995A064507C32B5642AFAC"}) else { throw NeuronError.invalidArchive }
            try await installDatabase(entry,archive:snapshot,version:latest,db:db)
            mappingVersion = latest; changed = true
        }
        for item in common.sorted(by:{Self.newer($1["version"] as? String ?? "",than:$0["version"] as? String ?? "")}) {
            guard let version = item["version"] as? String, Self.newer(version,than:mappingVersion), version.allSatisfy({$0.isNumber || $0 == "."}) else { continue }
            let patch = try await archive(URL(string:"\(PrivateConfiguration.value("artworkDownloadOrigin"))/ocg/\(version)/android.zip")!)
            // Common archives may replace Card.sqlite instead of sending SQL deltas.
            if let replacement = patch.entries.first(where:{$0.name == "05E47DF6E20B232F8665AED3D69564FBB0F291FCA9995A064507C32B5642AFAC"}) {
                try await installDatabase(replacement,archive:patch,version:version,db:db)
            } else {
                var sql: [String] = []
                for entry in patch.entries where ["DataCardSet","DataMstCardInfo"].contains(entry.name) {
                    let plain = try NeuronFormat.decode(await member(entry,archive:patch))
                    guard let statement = String(data:plain,encoding:.utf8), !statement.contains("\0") else { throw NeuronError.invalidPayload }; sql.append(statement)
                }
                try db.patch(sql,version:version)
            }
            changed = true
        }
        if try await persistAll(staged,db:db) {changed=true}
        try Task.checkCancellation()
        if changed {
            try JSONEncoder().encode(staged).write(to:stage.appendingPathComponent("index.json"),options:.atomic)
            try JSONEncoder().encode(revision).write(to:directory.appendingPathComponent("active.json"),options:.atomic)
            self.db=db;self.mappingURL=stagedMapping
            publish(staged); generation += 1;committed=true
        }
        return changed
    }
    func close() { db = nil }
    // Artwork is installed data. Only transient decoded images may be discarded.
    func clear() async {await CardArtworkMemory.clear()}

}

struct CardArtwork: View {
    @Environment(CardCatalog.self) private var catalog
    let cid: Int64
    var ciid: Int64? = nil
    var load = true
    @State private var image: UIImage?
    @State private var loadedKey:String?
    private var imageKey:String {CardArtworkMemory.key(cid:cid,ciid:ciid,revision:catalog.artworkRevision)}
    private var displayedImage:UIImage? {loadedKey == imageKey ? image : CardArtworkMemory.cached(imageKey)}
    private static let backPrint: UIImage? = Bundle.main.url(forResource:"BackPrint",withExtension:"png",subdirectory:"CardData").flatMap { UIImage(contentsOfFile:$0.path) }
    var body: some View {
        Group {
            if let displayed = displayedImage ?? Self.backPrint { Image(uiImage:displayed).resizable().scaledToFit() }
            else { Color.clear }
        }
        .accessibilityLabel(displayedImage == nil ? "卡图占位 BackPrint" : "Neuron 日文卡图")
        .accessibilityIdentifier(ciid == nil || ciid == 1 ? "cards.artwork.\(cid)" : "cards.artwork.\(cid).\(ciid!)")
        .task(id:"\(cid)-\(ciid ?? 0)-\(load)-\(catalog.artworkRevision)") {
            guard load else { return }
            let args = ProcessInfo.processInfo.arguments
            guard !args.contains("--uitesting") || args.contains("--uitesting-card-images") else { return }
            let key=imageKey
            let loaded=await CardArtworkMemory.load(cid:cid,ciid:ciid,revision:catalog.artworkRevision)
            if !Task.isCancelled {image=loaded;loadedKey=key}
        }
    }
}

/// Small, immutable UI sprites are decoded once, rather than reopened for every cell render.
@MainActor enum CardUIImages {
    private static var images:[String:UIImage]=[:]
    static func image(_ name:String,in folder:String)->UIImage? {
        let key=folder+"/"+name
        if let cached=images[key] {return cached}
        guard let url=Bundle.main.url(forResource:name,withExtension:"png",subdirectory:"CardData/"+folder),let image=UIImage(contentsOfFile:url.path) else{return nil}
        let decoded=image.preparingForDisplay() ?? image
        images[key]=decoded;return decoded
    }
}

@MainActor enum CardArtworkMemory {
    private static let images:NSCache<NSString,UIImage> = {
        let cache=NSCache<NSString,UIImage>();cache.totalCostLimit=48*1024*1024;cache.countLimit=160;return cache
    }()
    private static var tasks:[String:Task<UIImage?,Never>]=[:]
    static func key(cid:Int64,ciid:Int64?,revision:Int)->String {"\(cid)-\(ciid ?? 0)-\(revision)"}
    static func clear(){images.removeAllObjects()}
    static func cached(_ key:String)->UIImage? {images.object(forKey:key as NSString)}
    static func load(cid:Int64,ciid:Int64?,revision:Int) async ->UIImage? {
        let key=key(cid:cid,ciid:ciid,revision:revision)
        if let image=cached(key){return image}
        if let task=tasks[key]{return await task.value}
        let task=Task<UIImage?,Never> {
            guard let bytes=try? await NeuronArtworkStore.shared.data(cid:cid,ciid:ciid),let image=UIImage(data:bytes) else{return nil}
            return await image.byPreparingForDisplay() ?? image
        }
        tasks[key]=task
        let image=await task.value;tasks.removeValue(forKey:key)
        if let image {images.setObject(image,forKey:key as NSString,cost:Int(image.size.width*image.scale*image.size.height*image.scale*4))}
        return image
    }
}

struct NeuronCardText:Sendable {let cid:Int64;let name:String;let text:String;let pendulum:String}
struct NeuronUpdateProbe:Sendable {let version:String;let estimatedBytes:Int64;let hasChanges:Bool}
extension NeuronArtworkStore {
    // A read-only check: no index, mapping version or accepted revision is advanced here.
    func probe()async throws->NeuronUpdateProbe {
        let db=try open()
        let (bytes,_)=try await http.data(URL(string:"\(PrivateConfiguration.value("artworkManifestOrigin"))/neuron_rest/downloadList/ocg")!,limit:2*1024*1024)
        guard let root=try JSONSerialization.jsonObject(with:bytes) as? [String:Any],let full=root["newFullDataDictionary"] as? [String:Any],let baseline=full["lasted_version"] as? String,baseline.allSatisfy({$0.isNumber || $0 == "."}),
              let common=root["newCommonDataList"] as? [[String:Any]],let images=root["newHighImageDataList"] as? [[String:Any]] else{throw NeuronError.invalidResponse}
        let current=try db.rows("SELECT value FROM NeuronState WHERE key='version'").first?.first ?? "0"
        let latest=([baseline]+common.compactMap{$0["version"] as? String}).max{Self.newer($1,than:$0)} ?? baseline
        let imageLatest=([baseline]+images.compactMap{$0["version"] as? String}).max{Self.newer($1,than:$0)} ?? baseline
        let pending=try artworkJobs(index!,db:db)
        let changed=Self.newer(latest,than:current) || Self.newer(imageLatest,than:index?.version ?? "0") || !pending.isEmpty
        var estimate:Int64=Int64(pending.reduce(0){$0+$1.1.compressed_size+256})
        var commonURLs:[URL]=[]
        let oldest=common.compactMap{$0["version"] as? String}.sorted{Self.newer($1,than:$0)}.first
        var mapping=current
        if Self.newer(baseline,than:current),oldest.map({Self.newer($0,than:current)}) ?? true {
            commonURLs.append(URL(string:"\(PrivateConfiguration.value("artworkDownloadOrigin"))/ocg/full_\(baseline)/android.zip")!);mapping=baseline
        }
        for item in common {
            if let version=item["version"] as? String,Self.newer(version,than:mapping),version.allSatisfy({$0.isNumber || $0 == "."}) {
                commonURLs.append(URL(string:"\(PrivateConfiguration.value("artworkDownloadOrigin"))/ocg/\(version)/android.zip")!)
            }
        }
        for url in commonURLs {
            let archive=try await archive(url)
            estimate+=Int64(archive.entries.filter{["05E47DF6E20B232F8665AED3D69564FBB0F291FCA9995A064507C32B5642AFAC","DataCardSet","DataMstCardInfo"].contains($0.name)}.reduce(0){$0+$1.compressed_size+128})
        }
        if Self.newer(imageLatest,than:index?.version ?? "0") {
            // Include PNG payloads, not just ZIP directories. Delta entries are an upper bound.
            estimate+=2*1024*1024
            if Self.newer(baseline,than:index?.version ?? "0") {
                let next=try await archive(URL(string:"\(PrivateConfiguration.value("artworkDownloadOrigin"))/ocg/full_\(baseline)/ocg_high.zip")!)
                let previous=Dictionary(index!.archives.flatMap{ $0.entries.map{($0.name,$0.crc)}},uniquingKeysWith:{_,new in new})
                estimate+=Int64(next.entries.filter{previous[$0.name] != $0.crc}.reduce(0){$0+$1.compressed_size+256})
            }
            for item in images {
                if let version=item["version"] as? String,Self.newer(version,than:index?.version ?? "0"),version.allSatisfy({$0.isNumber || $0 == "."}) {
                    let delta=try await archive(URL(string:"\(PrivateConfiguration.value("artworkDownloadOrigin"))/ocg/\(version)/ocg_high.zip")!)
                    estimate+=Int64(delta.entries.reduce(0){$0+$1.compressed_size+256})
                }
            }
        }
        return .init(version:latest,estimatedBytes:estimate,hasChanges:changed)
    }
    func cardTexts()throws->[NeuronCardText] {
        try open().rows("SELECT card_id,card_name,card_text,card_pen_effect FROM MstCardInfo WHERE language='ja'").compactMap {r in
            guard r.count==4,let cid=Int64(r[0]) else{return nil};return .init(cid:cid,name:r[1],text:r[2],pendulum:r[3])
        }
    }
}
