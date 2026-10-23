import Foundation
import SQLite3

private let cardSQLTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
private enum CardSQLValue { case text(String), integer(Int64), null }
private final class CardSQLiteHandle: @unchecked Sendable {
    let value: OpaquePointer
    init(_ value: OpaquePointer) { self.value = value }
    deinit { sqlite3_close(value) }
}
private final class CardStatement {
    let value: OpaquePointer
    init(database: OpaquePointer, sql: String) throws {
        var pointer: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &pointer, nil) == SQLITE_OK, let pointer else {
            throw CardCatalogError.database
        }
        value = pointer
    }
    deinit { sqlite3_finalize(value) }
    func bind(_ values: [CardSQLValue]) throws {
        sqlite3_reset(value); sqlite3_clear_bindings(value)
        for (index, binding) in values.enumerated() {
            let position = Int32(index + 1)
            let result: Int32
            switch binding {
            case .text(let text): result = sqlite3_bind_text(value, position, text, -1, cardSQLTransient)
            case .integer(let number): result = sqlite3_bind_int64(value, position, number)
            case .null: result = sqlite3_bind_null(value, position)
            }
            guard result == SQLITE_OK else { throw CardCatalogError.database }
        }
    }
    func execute(_ bindings: [CardSQLValue]) throws {
        try bind(bindings)
        guard sqlite3_step(value) == SQLITE_DONE else { throw CardCatalogError.database }
    }
    func text(_ column: Int32) -> String? {
        guard sqlite3_column_type(value, column) != SQLITE_NULL, let text = sqlite3_column_text(value, column) else { return nil }
        return String(cString: text)
    }
    func integer(_ column: Int32) -> Int64? { sqlite3_column_type(value, column) == SQLITE_NULL ? nil : sqlite3_column_int64(value, column) }
    func next() throws -> Bool {
        let result = sqlite3_step(value)
        guard result == SQLITE_ROW || result == SQLITE_DONE else {
            throw CardCatalogError.database
        }
        return result == SQLITE_ROW
    }
    var card: CatalogCard {
        CatalogCard(cid: integer(0)!, passcode: integer(1), name: text(2) ?? "", description: text(3) ?? "",
                    pendulumDescription: text(4) ?? "", typeText: text(5) ?? "", typeBits: integer(6),
                    race: integer(7), attribute: integer(8), level: integer(9), levelKind: text(10),
                    attack: integer(11), defense: integer(12), leftScale: integer(13), rightScale: integer(14),
                    linkMarkers: integer(15), ot: integer(16), setcode: text(17), seriesText: text(18) ?? "")
    }
}

actor CardDatabase {
    let url:URL
    private var connection:CardSQLiteHandle?
    init(url:URL?=nil) {
        self.url=url ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Exodia/Catalog-v2.sqlite")
    }
    func close(){connection=nil}
    private func execute(_ sql:String,database:OpaquePointer)throws {
        guard sqlite3_exec(database,sql,nil,nil,nil)==SQLITE_OK else{throw CardCatalogError.database}
    }
    private func open()throws->OpaquePointer {
        if let connection{return connection.value}
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        if !FileManager.default.fileExists(atPath:url.path) {
            guard let seed=Bundle.main.url(forResource:"catalog",withExtension:"sqlite",subdirectory:"CardData") else{throw CardCatalogError.database}
            let staged=url.appendingPathExtension("installing")
            try? FileManager.default.removeItem(at:staged)
            try FileManager.default.copyItem(at:seed,to:staged)
            try Self.validate(staged)
            try FileManager.default.moveItem(at:staged,to:url)
        }
        var pointer:OpaquePointer?
        guard sqlite3_open_v2(url.path,&pointer,SQLITE_OPEN_READWRITE|SQLITE_OPEN_FULLMUTEX,nil)==SQLITE_OK,let pointer else{throw CardCatalogError.database}
        let handle=CardSQLiteHandle(pointer)
        let version=try CardStatement(database:pointer,sql:"PRAGMA user_version");_ = try version.next()
        guard version.integer(0)==2 else{throw CardCatalogError.incompatibleSchema}
        _ = try version.next()
        sqlite3_busy_timeout(pointer,5000)
        try execute("PRAGMA foreign_keys=ON; PRAGMA journal_mode=WAL;",database:pointer)
        guard let runtime=Bundle.main.url(forResource:"catalog-runtime",withExtension:"sql",subdirectory:"CardData") else{throw CardCatalogError.database}
        try execute(String(contentsOf:runtime,encoding:.utf8),database:pointer)
        connection=handle
        // User decks, artwork cache and favorites live outside the retired library.
        if url.lastPathComponent=="Catalog-v2.sqlite" {
            for suffix in ["","-wal","-shm"] {
                try? FileManager.default.removeItem(at:url.deletingLastPathComponent().appendingPathComponent("CardLibrary.sqlite"+suffix))
            }
            try? FileManager.default.removeItem(at:url.deletingLastPathComponent().appendingPathComponent("Banlists"))
        }
        return pointer
    }
    static func validate(_ url:URL)throws {
        var p:OpaquePointer?
        guard sqlite3_open_v2(url.path,&p,SQLITE_OPEN_READONLY,nil)==SQLITE_OK,let p else{throw CardCatalogError.database}
        defer{sqlite3_close(p)}
        let v=try CardStatement(database:p,sql:"PRAGMA user_version");_ = try v.next()
        guard v.integer(0)==2 else{throw CardCatalogError.incompatibleSchema}
        let check=try CardStatement(database:p,sql:"PRAGMA integrity_check");_ = try check.next()
        guard check.text(0)=="ok" else{throw CardCatalogError.checksum}
        let fk=try CardStatement(database:p,sql:"PRAGMA foreign_key_check")
        guard try !fk.next() else{throw CardCatalogError.invalidData}
    }
    func updateSourceOverview()throws->[CatalogSource:String] {
        let db=try open()
        func count(_ sql:String)throws->Int64 {let q=try CardStatement(database:db,sql:sql);_ = try q.next();return q.integer(0) ?? 0}
        var result:[CatalogSource:String]=[:]
        result[.cards]="\(try count("SELECT count(*) FROM card_localizations WHERE locale='ja' AND source='official-db'").formatted()) 张日文卡片 · 官方简中优先"
        result[.packs]="\(try count("SELECT count(*) FROM packs WHERE locale='ja'").formatted()) 个日文卡包 · \(try count("SELECT count(*) FROM printings WHERE locale='ja'").formatted()) 条收录"
        result[.translations]="\(try count("SELECT count(*) FROM card_localizations WHERE source='ygocdb'").formatted()) 条本机翻译"
        result[.jhs]="\(try count("SELECT count(*) FROM jhs_versions").formatted()) 条版本记录 · 待补齐 \(try pendingJHSCardIDs().count) 张卡片"
        result[.neuron]="本机版本 \(try state("neuron_data_version")) · 仅日文及日文异画"
        for format in CardFormat.allCases {let snapshot=try banlist(format:format);result[.banlist(format)]=snapshot.map{"当期 \($0.date) · \($0.versions.count) 期版本"} ?? "尚无本机资料"}
        return result
    }
    func state(_ key:String)throws->String {
        let q=try CardStatement(database:open(),sql:"SELECT value FROM catalog_state WHERE key=?");try q.bind([.text(key)])
        return try q.next() ? q.text(0) ?? "":""
    }
    private func setState(_ key:String,_ value:String,db:OpaquePointer)throws {
        let q=try CardStatement(database:db,sql:"INSERT OR REPLACE INTO catalog_state VALUES (?,?)");try q.execute([.text(key),.text(value)])
    }
    func recordCheck()throws {
        try setState("checked_at",ISO8601DateFormatter().string(from:.now),db:open())
    }
    func metadata()throws->CardMetadata {
        let q=try CardStatement(database:open(),sql:"SELECT count(*) FROM cards WHERE EXISTS(SELECT 1 FROM card_localizations l WHERE l.cid=cards.cid AND l.locale='ja')");_ = try q.next()
        return try CardMetadata(count:Int(q.integer(0) ?? 0),hash:state("revision"),updatedAt:state("updated_at"),checkedAt:state("checked_at"),releasesHash:"",limitsHash:"",origin:"catalog-v2")
    }
    func search(keyword: String, filter: CardFilter, favorites: Set<String> = [], offset: Int = 0, limit: Int = 40) throws -> CardResults {
        try filter.validate()
        let db = try open()
        var clauses: [String] = ["EXISTS (SELECT 1 FROM card_localizations ja WHERE ja.cid=c.cid AND ja.locale='ja')"], values: [CardSQLValue] = []
        func condition(_ sql: String, _ value: CardSQLValue) { clauses.append(sql); values.append(value) }
        let submitted=keyword.trimmingCharacters(in:.whitespacesAndNewlines)
        let word = CardVocabulary.normalize(submitted)
        func pattern(_ text: String) -> String {
            "%" + text.replacingOccurrences(of: "^", with: "^^").replacingOccurrences(of: "%", with: "^%").replacingOccurrences(of: "_", with: "^_") + "%"
        }

        if !word.isEmpty {
            #if DEBUG
            let testingNumber=ProcessInfo.processInfo.arguments.contains("--uitesting") ? Int64(word):nil
            #else
            let testingNumber:Int64?=nil
            #endif
            if let number=testingNumber {
                clauses.append("(c.passcode=? OR c.cid=?)");values += [.integer(number),.integer(number)]
            } else {
                clauses.append("(EXISTS (SELECT 1 FROM card_aliases n WHERE n.cid=c.cid AND n.source IN ('sc_name','jp_name','nwbbs_n') AND n.normalized_name LIKE ? ESCAPE '^') OR c.description LIKE ? ESCAPE '^' OR c.pendulum_description LIKE ? ESCAPE '^' OR EXISTS (SELECT 1 FROM card_localizations t WHERE t.cid=c.cid AND t.locale='zh-Hans' AND t.source='official-db' AND (t.name LIKE ? ESCAPE '^' OR t.description LIKE ? ESCAPE '^' OR t.pendulum_description LIKE ? ESCAPE '^')))")
                values += [.text(pattern(word)),.text(pattern(submitted)),.text(pattern(submitted)),.text(pattern(submitted)),.text(pattern(submitted)),.text(pattern(submitted))]
            }
        }
        if filter.baseType != 0 { condition("(c.type_bits & ?) != 0", .integer(filter.baseType)) }
        if filter.subtype != 0 {
            if filter.monsterTypeMatchAll {
                clauses.append("(c.type_bits & ?) = ?")
                values += [.integer(filter.subtype),.integer(filter.subtype)]
            } else { condition("(c.type_bits & ?) != 0", .integer(filter.subtype)) }
        }
        if filter.excludedSubtype != 0 { condition("(c.type_bits & ?) = 0", .integer(filter.excludedSubtype)) }
        if filter.normalNonMonster {
            clauses.append("(c.type_bits & 6) != 0 AND (c.type_bits & ?) = 0")
            values.append(.integer(CardVocabulary.nonMonsterKindMask))
        }
        func nonMonsterKinds(base: Int64, kinds: Int64, normal: Bool) {
            guard kinds != 0 || normal else { return }
            var alternatives: [String] = []
            if normal {
                alternatives.append("((c.type_bits & \(base)) != 0 AND (c.type_bits & \(CardVocabulary.nonMonsterKindMask)) = 0)")
            }
            if kinds != 0 {
                alternatives.append("((c.type_bits & \(base)) != 0 AND (c.type_bits & ?) != 0)")
                values.append(.integer(kinds))
            }
            clauses.append("(" + alternatives.joined(separator: " OR ") + ")")
        }
        nonMonsterKinds(base: CardVocabulary.spell, kinds: filter.spellKinds, normal: filter.includesNormalSpell)
        nonMonsterKinds(base: CardVocabulary.trap, kinds: filter.trapKinds, normal: filter.includesNormalTrap)
        if filter.race != 0 { condition("(c.race & ?) != 0", .integer(filter.race)) }
        if filter.attribute != 0 { condition("(c.attribute & ?) != 0", .integer(filter.attribute)) }
        if !filter.levelKind.isEmpty { condition("c.level_kind=?", .text(filter.levelKind)) }
        for (column, low, high) in [("level", filter.minLevel, filter.maxLevel)] {
            if let low = Int64(low) { condition("c.\(column)>=?", .integer(low)) }
            if let high = Int64(high) { condition("c.\(column)<=?", .integer(high)) }
        }
        func selectedValues(_ mask: Int64, _ values: ClosedRange<Int>) -> [Int64] {
            values.compactMap { mask & (Int64(1) << Int64($0)) != 0 ? Int64($0) : nil }
        }
        func selection(_ sql: String, values selected: [Int64]) {
            guard !selected.isEmpty else { return }
            clauses.append(sql.replacingOccurrences(of: "{values}", with: Array(repeating:"?",count:selected.count).joined(separator:",")))
            values += selected.map(CardSQLValue.integer)
        }
        selection("c.level IN ({values})", values: selectedValues(filter.selectedLevels, 0...13))
        let scales = selectedValues(filter.selectedScales, 0...13)
        if !scales.isEmpty {
            let placeholders=Array(repeating:"?",count:scales.count).joined(separator:",")
            clauses.append("(c.left_scale IN (\(placeholders)) OR c.right_scale IN (\(placeholders)))")
            values += (scales+scales).map(CardSQLValue.integer)
        }
        let links=selectedValues(filter.selectedLinkRatings, 1...6)
        if !links.isEmpty { selection("(c.level_kind='link' AND c.level IN ({values}))",values:links) }
        if filter.linkMarkers != 0 {
            if filter.linkMarkerMatchAll {
                clauses.append("(c.level_kind='link' AND (c.link_markers & ?) = ?)")
                values += [.integer(filter.linkMarkers),.integer(filter.linkMarkers)]
            } else {
                clauses.append("(c.level_kind='link' AND (c.link_markers & ?) != 0)")
                values.append(.integer(filter.linkMarkers))
            }
        }
        func stat(_ column:String, low:String, high:String, includeUnknown:Bool) {
            var numeric=["c.\(column)>=0"]
            if let low=Int64(low) { numeric.append("c.\(column)>=?");values.append(.integer(low)) }
            if let high=Int64(high) { numeric.append("c.\(column)<=?");values.append(.integer(high)) }
            let hasRange = !low.isEmpty || !high.isEmpty
            if hasRange && includeUnknown { clauses.append("(("+numeric.joined(separator:" AND ")+") OR c.\(column)<0)") }
            else if hasRange { clauses.append(numeric.joined(separator:" AND ")) }
            else if includeUnknown { clauses.append("c.\(column)<0") }
        }
        stat("atk",low:filter.minAttack,high:filter.maxAttack,includeUnknown:filter.unknownAttack)
        stat("defense",low:filter.minDefense,high:filter.maxDefense,includeUnknown:filter.unknownDefense)
        if let scale = Int64(filter.leftScale) { condition("c.left_scale=?", .integer(scale)) }
        if let scale = Int64(filter.rightScale) { condition("c.right_scale=?", .integer(scale)) }
        if let code = Int64(filter.seriesCode) { condition("EXISTS (SELECT 1 FROM card_series s WHERE s.cid=c.cid AND s.series_code=?)", .integer(code)) }
        if !filter.seriesName.isEmpty { condition("c.series_text LIKE ? ESCAPE '^'", .text(pattern(filter.seriesName))) }
        if !filter.pack.isEmpty { condition("EXISTS (SELECT 1 FROM app_releases r WHERE r.cid=c.cid AND r.pack LIKE ? ESCAPE '^')", .text(pattern(filter.pack))) }
        if !filter.releaseLanguage.isEmpty { condition("EXISTS (SELECT 1 FROM app_releases r WHERE r.cid=c.cid AND r.language=?)", .text(filter.releaseLanguage)) }
        if !filter.rarity.isEmpty || !filter.rarities.isEmpty {
            var selected=filter.rarities.sorted()
            if !filter.rarity.isEmpty {selected.append(filter.rarity)}
            clauses.append("EXISTS (SELECT 1 FROM printings p JOIN rarities rr USING(rarity_id) WHERE p.cid=c.cid AND rr.source_rid IN ("+Array(repeating:"?",count:selected.count).joined(separator:",")+"))")
            values += selected.map(CardSQLValue.text)
        }
        if !filter.printingPack.isEmpty {
            condition("EXISTS (SELECT 1 FROM printings p WHERE p.cid=c.cid AND p.card_number LIKE ? ESCAPE '^')",.text(pattern(filter.printingPack)))
        }
        if !filter.releaseDateFrom.isEmpty || !filter.releaseDateTo.isEmpty {
            var release=["r.cid=c.cid","r.language='jp'","r.date IS NOT NULL"]
            if !filter.releaseDateFrom.isEmpty { release.append("r.date>=?");values.append(.text(filter.releaseDateFrom)) }
            if !filter.releaseDateTo.isEmpty { release.append("r.date<=?");values.append(.text(filter.releaseDateTo)) }
            clauses.append("EXISTS (SELECT 1 FROM app_releases r WHERE "+release.joined(separator:" AND ")+")")
        }
        if filter.limitCopies >= 0 {
            clauses.append("EXISTS (SELECT 1 FROM app_releases r WHERE r.cid=c.cid AND r.language=?) AND COALESCE((SELECT copies FROM app_limits l WHERE l.cid=c.cid AND l.format=?),3)=?")
            values += [.text(filter.format.releaseLanguage), .text(filter.format.rawValue), .integer(Int64(filter.limitCopies))]
        }
        let limitStatuses=selectedValues(filter.limitStatuses,0...3)
        if !limitStatuses.isEmpty {
            clauses.append("EXISTS (SELECT 1 FROM app_releases r WHERE r.cid=c.cid AND r.language=?) AND COALESCE((SELECT copies FROM app_limits l WHERE l.cid=c.cid AND l.format=?),3) IN ("+Array(repeating:"?",count:limitStatuses.count).joined(separator:",")+")")
            values += [.text(filter.format.releaseLanguage),.text(filter.format.rawValue)] + limitStatuses.map(CardSQLValue.integer)
        }
        if filter.favoritesOnly {
            let cids = favorites.compactMap { $0.hasPrefix("cid:") ? Int64($0.dropFirst(4)) : nil }
            let ids = favorites.compactMap { $0.hasPrefix("cid:") ? nil : Int64($0) }
            var groups: [String] = []
            if !cids.isEmpty { groups.append("c.cid IN (\(Array(repeating: "?", count: cids.count).joined(separator: ",")))"); values += cids.map(CardSQLValue.integer) }
            if !ids.isEmpty { groups.append("c.passcode IN (\(Array(repeating: "?", count: ids.count).joined(separator: ",")))"); values += ids.map(CardSQLValue.integer) }
            clauses.append(groups.isEmpty ? "0" : "(" + groups.joined(separator: " OR ") + ")")
        }
        let whereSQL = clauses.isEmpty ? "" : " WHERE " + clauses.joined(separator: " AND ")
        let counter = try CardStatement(database: db, sql: "SELECT count(*) FROM app_cards c" + whereSQL)
        try counter.bind(values); _ = try counter.next()
        let count = Int(counter.integer(0) ?? 0)
        let direction=filter.sortAscending ? "ASC":"DESC"
        var order:String
        switch filter.sort {
        case .name: order="c.name COLLATE NOCASE \(direction),c.cid \(direction)"
        case .level: order="(CASE WHEN c.level_kind IN ('level','rank') THEN c.level END) IS NULL,(CASE WHEN c.level_kind IN ('level','rank') THEN c.level END) \(direction),c.name COLLATE NOCASE"
        case .attack: order="(c.atk IS NULL OR c.atk<0),c.atk \(direction),c.name COLLATE NOCASE"
        case .defense: order="(c.defense IS NULL OR c.defense<0),c.defense \(direction),c.name COLLATE NOCASE"
        case .scale: order="COALESCE(c.left_scale,c.right_scale) IS NULL,COALESCE(c.left_scale,c.right_scale) \(direction),c.name COLLATE NOCASE"
        case .link: order="(CASE WHEN c.level_kind='link' THEN c.level END) IS NULL,(CASE WHEN c.level_kind='link' THEN c.level END) \(direction),c.name COLLATE NOCASE"
        case .releaseDate: order="(SELECT r.date FROM app_releases r WHERE r.cid=c.cid AND r.language='jp') IS NULL,(SELECT r.date FROM app_releases r WHERE r.cid=c.cid AND r.language='jp') \(direction),c.name COLLATE NOCASE"
        }
        let statement = try CardStatement(database: db, sql: "SELECT c.* FROM app_cards c" + whereSQL + " ORDER BY " + order + " LIMIT ? OFFSET ?")
        try statement.bind(values + [.integer(Int64(max(1, min(limit, 200)))), .integer(Int64(max(0, offset)))])
        var cards: [CatalogCard] = []
        while try statement.next() { cards.append(statement.card) }
        return CardResults(cards: cards, count: count)
    }

    func availableRarities()throws->[String] {
        let q=try CardStatement(database:open(),sql:"SELECT source_rid FROM rarities WHERE display_order IS NOT NULL ORDER BY display_order DESC,source_rid")
        var result:[String]=[];while try q.next(){result.append(q.text(0)!)};return result
    }
    func banlistCards(cids:[Int64])throws->[Int64:CatalogCard] {
        guard !cids.isEmpty else{return [:]}
        let q=try CardStatement(database:open(),sql:"SELECT * FROM app_cards WHERE cid IN ("+cids.map{_ in "?"}.joined(separator:",")+")")
        try q.bind(cids.map(CardSQLValue.integer));var result:[Int64:CatalogCard]=[:]
        while try q.next(){let card=q.card;result[card.cid]=card};return result
    }
    func details(cid:Int64)throws->CardDetails {
        let db=try open(),q=try CardStatement(database:open(),sql:"SELECT * FROM app_cards WHERE cid=?");try q.bind([.integer(cid)])
        guard try q.next() else{throw CardCatalogError.invalidData};let card=q.card
        let names=try CardStatement(database:db,sql:"SELECT source,name FROM card_aliases WHERE cid=? ORDER BY source")
        try names.bind([.integer(cid)]);var aliases:[CardName]=[];while try names.next(){aliases.append(.init(source:names.text(0)!,name:names.text(1)!))}
        let releases=try CardStatement(database:db,sql:"SELECT language,date,pack FROM app_releases WHERE cid=?");try releases.bind([.integer(cid)])
        var dates:[CardRelease]=[];while try releases.next(){dates.append(.init(language:releases.text(0)!,date:releases.text(1),pack:releases.text(2)))}
        let limits=try CardStatement(database:db,sql:"SELECT format,copies FROM app_limits WHERE cid=?");try limits.bind([.integer(cid)])
        var copies:[String:Int]=[:];while try limits.next(){copies[limits.text(0)!]=Int(limits.integer(1)!)}
        let versions=try CardStatement(database:db,sql:"SELECT format,max(effective_date) FROM banlists WHERE completeness='complete' AND effective_date<=date('now','localtime') GROUP BY format")
        var limitDates:[String:String]=[:];while try versions.next(){limitDates[versions.text(0)!]=versions.text(1)!}
        let sets=try CardStatement(database:db,sql:"SELECT series_code FROM card_series WHERE cid=?");try sets.bind([.integer(cid)])
        var codes:[Int64]=[];while try sets.next(){if let code=sets.integer(0){codes.append(code)}}
        let note=try CardStatement(database:db,sql:"SELECT notes FROM card_localizations WHERE cid=? AND locale='ja' LIMIT 1");try note.bind([.integer(cid)])
        let notes=try note.next() ? note.text(0) ?? "":""
        return .init(card:card,names:aliases,releases:dates,limits:copies,limitDates:limitDates,setCodes:codes,officialNotes:notes)
    }
    func artworkLimit(cid:Int64,format:CardFormat)throws->Int? {try details(cid:cid).limitCopies(in:format)}
    func migrateFavorites(_ favorites:Set<String>)throws->Set<String> {
        let q=try CardStatement(database:open(),sql:"SELECT cid FROM cards WHERE CAST(passcode AS INTEGER)=?");var result=Set<String>()
        for key in favorites {
            guard !key.hasPrefix("cid:"),let passcode=Int64(key) else{result.insert(key);continue}
            try q.bind([.integer(passcode)]);var found=false
            while try q.next(){result.insert("cid:\(q.integer(0)!)");found=true};if !found{result.insert(key)}
        };return result
    }
    func pendingJHSCardIDs()throws->[Int64] {
        let q=try CardStatement(database:open(),sql:"SELECT CAST(resource_key AS INTEGER) FROM sync_resources WHERE source='jhs' AND resource_type='card_versions' AND status!='complete' ORDER BY CAST(resource_key AS INTEGER)")
        var ids:[Int64]=[];while try q.next(){if let cid=q.integer(0),cid>0 {ids.append(cid)}};return ids
    }
    func verifiedJHSIDs(cid:Int64)throws->Set<Int64> {
        let q=try CardStatement(database:open(),sql:"SELECT jhs_card_id FROM jhs_card_mappings WHERE cid=? AND match_status='verified'");try q.bind([.integer(cid)])
        var ids=Set<Int64>();while try q.next(){if let id=q.integer(0){ids.insert(id)}};return ids
    }
    func printings(cid:Int64)throws->[CardPrinting] {
        let q=try CardStatement(database:open(),sql:"SELECT DISTINCT v.jhs_version_id,v.jhs_card_id,v.name,v.origin_name,v.card_number,v.rarity_code,v.pack_code,v.fetched_at FROM jhs_versions v JOIN jhs_card_mappings m ON m.jhs_card_id=v.jhs_card_id WHERE m.cid=? AND m.match_status='verified' ORDER BY v.pack_code,v.card_number,v.rarity_code")
        try q.bind([.integer(cid)]);var result:[CardPrinting]=[]
        while try q.next(){result.append(.init(versionID:q.integer(0)!,sourceCardID:q.integer(1),name:q.text(2)!,originName:q.text(3),number:q.text(4)!,rarity:q.text(5)!,packCode:q.text(6),fetchedAt:q.text(7)!))};return result
    }
    func displayPrintings(cid:Int64)throws->[CardPrintingDisplay] {
        // Detail/market rows are JHS versions. Official printings enrich pack labels only;
        // an unmatched official printing must never create a market row with version ID 0.
        let versions=try printings(cid:cid),official=try officialPrintings(cid:cid),db=try open()
        let linked=try CardStatement(database:db,sql:"SELECT j.jhs_version_id,k.name,k.release_date FROM printing_jhs_links j JOIN printings p USING(printing_id) JOIN packs k ON k.locale=p.locale AND k.pid=p.pid WHERE p.cid=? AND j.match_status='verified' ORDER BY k.release_date DESC,k.pid")
        try linked.bind([.integer(cid)]);var labels:[Int64:(String,String?)]=[:]
        while try linked.next(){let id=linked.integer(0)!;if labels[id]==nil {labels[id]=(linked.text(1)!,linked.text(2))}}
        let ranks=try CardStatement(database:db,sql:"SELECT m.source_code,max(r.display_order) FROM rarity_source_mappings m JOIN rarities r USING(rarity_id) WHERE m.source='jhs' AND m.match_status='verified' GROUP BY m.source_code")
        var orders:[String:Int64]=[:];while try ranks.next(){orders[ranks.text(0)!]=ranks.integer(1) ?? -1}
        func canonicalNumber(_ number:String)->String {
            var result=number
            for suffix in ["[Asia]","[Japan]","(-)"] {if result.hasSuffix(suffix){result=String(result.dropLast(suffix.count))}}
            return result
        }
        let byNumber=Dictionary(grouping:official,by:{$0.number})
        return versions.map {version in
            let candidates=byNumber[canonicalNumber(version.number)] ?? []
            let uniquePack=Set(candidates.map(\.pid)).count==1 ? candidates.first:nil
            let label=labels[version.versionID]
            return CardPrintingDisplay(id:"jhs:\(version.versionID)",versionID:version.versionID,sourceCardID:version.sourceCardID,number:version.number,rarity:version.rarity,packName:label?.0 ?? uniquePack?.packName ?? version.packCode ?? "其他发行物",date:label?.1 ?? uniquePack?.date)
        }.sorted {
            if $0.date != $1.date {return ($0.date ?? "") > ($1.date ?? "")}
            if $0.number != $1.number {return $0.number < $1.number}
            let a=orders[$0.rarity] ?? -1,b=orders[$1.rarity] ?? -1
            if a != b {return a>b}
            return $0.versionID < $1.versionID
        }
    }
    func officialPrintings(cid:Int64)throws->[OfficialPrinting] {
        let q=try CardStatement(database:open(),sql:"SELECT p.pid,p.card_number,r.code,l.name,k.release_date,k.name FROM printings p JOIN rarities r USING(rarity_id) JOIN packs k ON k.locale=p.locale AND k.pid=p.pid LEFT JOIN rarity_localizations l ON l.rarity_id=r.rarity_id AND l.locale='ja' AND l.source=(SELECT z.source FROM rarity_localizations z WHERE z.rarity_id=r.rarity_id AND z.locale='ja' ORDER BY CASE z.source WHEN 'official-db' THEN 0 ELSE 1 END LIMIT 1) WHERE p.cid=? AND p.locale='ja' ORDER BY k.release_date DESC,p.card_number,r.display_order DESC")
        try q.bind([.integer(cid)]);var result:[OfficialPrinting]=[]
        while try q.next(){result.append(.init(cid:cid,pid:q.text(0)!,number:q.text(1)!,rarity:q.text(2)!,rarityName:q.text(3) ?? "",date:q.text(4),packName:q.text(5)!))};return result
    }
    func collectionPacks(locale:String)throws->[CollectionPack] {
        let q=try CardStatement(database:open(),sql:"SELECT pid,name,release_date,category_code,source_subcategory FROM packs WHERE locale=? ORDER BY release_date DESC,pid")
        try q.bind([.text(locale)]);var result:[CollectionPack]=[]
        while try q.next(){result.append(.init(id:q.text(0)!,locale:locale,name:q.text(1)!,date:q.text(2) ?? "",category:Int(q.text(3) ?? "") ?? 0,group:q.text(4) ?? ""))};return result
    }
    func collectionCards(_ pack:CollectionPack)throws->[CollectionCard] {
        let q=try CardStatement(database:open(),sql:"SELECT p.cid,c.name,r.source_rid,r.code,COALESCE(l.name,r.code),r.color_hex FROM printings p JOIN app_cards c ON c.cid=p.cid JOIN rarities r USING(rarity_id) LEFT JOIN rarity_localizations l ON l.rarity_id=r.rarity_id AND l.locale='ja' AND l.source=(SELECT z.source FROM rarity_localizations z WHERE z.rarity_id=r.rarity_id AND z.locale='ja' ORDER BY CASE z.source WHEN 'official-db' THEN 0 ELSE 1 END LIMIT 1) WHERE p.locale=? AND p.pid=? ORDER BY p.position,p.card_number,r.display_order DESC")
        try q.bind([.text(pack.locale),.text(pack.id)]);var result:[CollectionCard]=[],index:[Int64:Int]=[:]
        while try q.next(){let cid=q.integer(0)!,rarity=CollectionRarity(code:q.text(3)!,name:q.text(4)!,colorHex:q.text(5),rid:q.text(2))
            if let i=index[cid]{if !result[i].rarities.contains(rarity){result[i].rarities.append(rarity)}}
            else{index[cid]=result.count;result.append(.init(id:cid,name:q.text(1)!,rarities:[rarity]))}
        };return result
    }
    func collectionCardsComplete(_ pack:CollectionPack)throws->Bool {try !collectionCards(pack).isEmpty}
    func banlist(format:CardFormat,date:String?=nil)throws->BanlistSnapshot? {
        let db=try open(),versions=try CardStatement(database:open(),sql:"SELECT effective_date FROM banlists WHERE format=? AND completeness='complete' ORDER BY effective_date DESC")
        try versions.bind([.text(format.rawValue)]);var dates:[String]=[];while try versions.next(){dates.append(versions.text(0)!)}
        guard let date=date ?? dates.first else{return nil}
        let q=try CardStatement(database:db,sql:"SELECT e.cid,c.name,e.copies,e.source_change,e.previous_copies,e.is_changed FROM banlist_entries e JOIN app_cards c ON c.cid=e.cid WHERE e.format=? AND e.effective_date=? ORDER BY e.is_changed DESC,e.cid")
        try q.bind([.text(format.rawValue),.text(date)]);var entries:[BanlistEntry]=[]
        while try q.next(){let status=Int(q.integer(2)!),previous=Int(q.integer(4) ?? 3),changed=q.integer(5)==1
            let words=["禁止","限制","准限制","解除限制"]
            entries.append(.init(cid:q.integer(0)!,name:q.text(1)!,status:status,change:changed && previous != status ? words[previous]+"-"+words[status]:q.text(3) ?? ""))
        };return entries.isEmpty ? nil:.init(format:format.rawValue,date:date,versions:format == .simplified ? []:dates,entries:entries)
    }
    func changedNeuronCards(_ rows:[NeuronCardText])throws->[Int64] {
        let q=try CardStatement(database:open(),sql:"SELECT name,description,pendulum_description FROM card_localizations WHERE cid=? AND locale='ja' AND source='official-db'")
        func normalized(_ text:String)->String{text.components(separatedBy:.whitespacesAndNewlines).joined()}
        var changed:[Int64]=[]
        for row in rows {try q.bind([.integer(row.cid)])
            if try !q.next(){changed.append(row.cid);continue}
            // The bundled Neuron mapping intentionally omits names/effects. An empty
            // omitted field is unknown, not a request to erase an official text.
            let name=normalized(row.name),text=normalized(row.text),pendulum=normalized(row.pendulum)
            let nameChanged = !name.isEmpty && normalized(q.text(0) ?? "") != name
            let textChanged = !text.isEmpty && normalized(q.text(1) ?? "") != text
            let hasCompleteText = !name.isEmpty && !text.isEmpty
            let pendulumChanged = (hasCompleteText || !pendulum.isEmpty) && normalized(q.text(2) ?? "") != pendulum
            if nameChanged || textChanged || pendulumChanged {changed.append(row.cid)}
        };return changed
    }
    func applyUpdate(cards:[Data],packs:[CollectionPack],members:[String:[CollectionCard]],banlists:[BanlistSnapshot],neuronVersion:String,jhs:[CatalogJHSRefresh]=[])throws {
        let db=try open(),stamp=ISO8601DateFormatter().string(from:.now)
        try execute("BEGIN IMMEDIATE",database:db)
        do {
            for bytes in cards {try saveCard(bytes,stamp:stamp,db:db)}
            for pack in packs {
                let category=String(pack.category)
                let categoryRow=try CardStatement(database:db,sql:"INSERT OR IGNORE INTO pack_categories VALUES (?,?,?,?,?)")
                try categoryRow.execute([.text(pack.locale),.text(category),.text(pack.group),.text(pack.group),.integer(Int64(pack.category))])
                let q=try CardStatement(database:db,sql:"INSERT INTO packs VALUES (?,?,?,?,?,?,?,?) ON CONFLICT(locale,pid) DO UPDATE SET name=excluded.name,release_date=excluded.release_date,category_code=excluded.category_code,updated_at=excluded.updated_at")
                try q.execute([.text(pack.locale),.text(pack.id),.text(pack.name),.text(pack.date),.text(category),.text(pack.group),.text(CollectionService.catalogURL(pack.locale).absoluteString),.text(stamp)])
                // Full card detail rows carry the official card number and rid; no placeholder printings.
                if let expected=members[pack.id] {
                    let check=try CardStatement(database:db,sql:"SELECT COUNT(DISTINCT cid) FROM printings WHERE locale=? AND pid=?")
                    try check.bind([.text(pack.locale),.text(pack.id)]);_ = try check.next()
                    guard check.integer(0)==Int64(expected.count) else{throw CardCatalogError.invalidData}
                }
            }
            for snapshot in banlists.sorted(by:{$0.date<$1.date}) {
                let row=try CardStatement(database:db,sql:"INSERT OR REPLACE INTO banlists VALUES (?,?,?,?,?,'complete')")
                let hash=CardDigest.sha256(try JSONEncoder().encode(snapshot))
                try row.execute([.text(snapshot.format),.text(snapshot.date),.text(BanlistRepository.url(format:CardFormat(rawValue:snapshot.format)!).absoluteString),.text(stamp),.text(hash)])
                let remove=try CardStatement(database:db,sql:"DELETE FROM banlist_entries WHERE format=? AND effective_date=?");try remove.execute([.text(snapshot.format),.text(snapshot.date)])
                let previous=try CardStatement(database:db,sql:"SELECT copies FROM banlist_entries WHERE cid=? AND format=? AND effective_date=(SELECT max(effective_date) FROM banlists WHERE format=? AND effective_date<? AND completeness='complete')")
                let entry=try CardStatement(database:db,sql:"INSERT INTO banlist_entries VALUES (?,?,?,?,?,?,?)")
                for card in snapshot.entries {
                    try previous.bind([.integer(card.cid),.text(snapshot.format),.text(snapshot.format),.text(snapshot.date)])
                    let old=try previous.next() ? previous.integer(0) ?? 3:3
                    try entry.execute([.text(snapshot.format),.text(snapshot.date),.integer(card.cid),.integer(Int64(card.status)),.integer(old),.text(card.change),.integer(old != card.status ? 1:0)])
                }
            }
            for update in jhs {try saveJHS(update,stamp:stamp,db:db)}
            let fk=try CardStatement(database:db,sql:"PRAGMA foreign_key_check");guard try !fk.next() else{throw CardCatalogError.invalidData}
            try setState("updated_at",stamp,db:db);try setState("checked_at",stamp,db:db)
            try setState("revision",UUID().uuidString,db:db)
            if !neuronVersion.isEmpty {try setState("neuron_data_version",neuronVersion,db:db)}
            try execute("COMMIT",database:db)
        } catch {try? execute("ROLLBACK",database:db);throw error}
    }
    private func saveJHS(_ update:CatalogJHSRefresh,stamp:String,db:OpaquePointer)throws {
        var complete=update.complete,detail=update.detail
        let ids=Set(update.records.compactMap(\.sourceCardID))
        guard Set(update.records.map(\.versionID)).count==update.records.count else {throw CardCatalogError.invalidData}
        for id in ids {
            let conflict=try CardStatement(database:db,sql:"SELECT cid FROM jhs_card_mappings WHERE jhs_card_id=? AND cid!=? AND match_status='verified' LIMIT 1")
            try conflict.bind([.integer(id),.integer(update.cid)])
            if try conflict.next() {complete=false;detail="映射与其他卡片冲突，保留原资料等待核对"}
        }
        for record in update.records {
            let conflict=try CardStatement(database:db,sql:"SELECT jhs_card_id FROM jhs_versions WHERE jhs_version_id=? AND jhs_card_id!=? LIMIT 1")
            try conflict.bind([.integer(record.versionID),.integer(record.sourceCardID ?? 0)])
            if try conflict.next() {complete=false;detail="版本归属与本机记录冲突，保留原资料等待核对"}
        }
        if complete {
            guard !ids.isEmpty,update.records.allSatisfy({$0.sourceCardID != nil && $0.versionID>0 && !$0.number.isEmpty && !$0.rarity.isEmpty}) else {throw CardCatalogError.invalidData}
            for id in ids {
                let mapping=try CardStatement(database:db,sql:"INSERT INTO jhs_card_mappings VALUES (?,?,?,'verified',?,?) ON CONFLICT(cid,jhs_card_id) DO UPDATE SET match_method=excluded.match_method,match_status='verified',evidence_json=excluded.evidence_json,checked_at=excluded.checked_at")
                let evidence=String(decoding:try JSONSerialization.data(withJSONObject:["method":update.method,"version_count":update.records.count]),as:UTF8.self)
                try mapping.execute([.integer(update.cid),.integer(id),.text(update.method),.text(evidence),.text(stamp)])
            }
            for row in update.records {
                let q=try CardStatement(database:db,sql:"INSERT INTO jhs_versions VALUES (?,?,?,?,?,?,?,?) ON CONFLICT(jhs_version_id) DO UPDATE SET jhs_card_id=excluded.jhs_card_id,name=excluded.name,origin_name=excluded.origin_name,card_number=excluded.card_number,rarity_code=excluded.rarity_code,pack_code=excluded.pack_code,fetched_at=excluded.fetched_at")
                try q.execute([.integer(row.versionID),.integer(row.sourceCardID!),.text(row.name),row.originName.map(CardSQLValue.text) ?? .null,.text(row.number),.text(row.rarity),row.packCode.map(CardSQLValue.text) ?? .null,.text(stamp)])
            }
        }
        let state=try CardStatement(database:db,sql:"INSERT INTO sync_resources(source,resource_type,resource_key,status,last_attempt_at,last_success_at,attempts,last_error) VALUES ('jhs','card_versions',?,?,?,?,1,?) ON CONFLICT(source,resource_type,resource_key) DO UPDATE SET status=excluded.status,last_attempt_at=excluded.last_attempt_at,last_success_at=COALESCE(excluded.last_success_at,sync_resources.last_success_at),attempts=sync_resources.attempts+1,last_error=excluded.last_error")
        try state.execute([.text(String(update.cid)),.text(complete ? "complete":"partial"),.text(stamp),complete ? .text(stamp):.null,complete ? .null:.text(detail)])
    }
    private func saveCard(_ bytes:Data,stamp:String,db:OpaquePointer)throws {
        let card=try JSONDecoder().decode(YGOSourceCard.self,from:bytes)
        guard let fields=card.data,let raw=try JSONSerialization.jsonObject(with:bytes) as? [String:Any],let official=raw["official_ja"] as? [String:Any],let ja=raw["jp_name"] as? String,let text=official["text"] as? String,!text.isEmpty else{throw CardCatalogError.invalidData}
        let bits=fields.type,monster=bits&1 != 0,link=bits&CardVocabulary.link != 0,pendulum=bits&CardVocabulary.pendulum != 0
        let q=try CardStatement(database:db,sql:"INSERT INTO cards VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(cid) DO UPDATE SET type_bits=excluded.type_bits,race_code=excluded.race_code,attribute_code=excluded.attribute_code,level_kind=excluded.level_kind,level_value=excluded.level_value,atk=excluded.atk,defense=excluded.defense,scale_left=excluded.scale_left,scale_right=excluded.scale_right,link_markers=excluded.link_markers,playability=excluded.playability,updated_at=excluded.updated_at,passcode=COALESCE(excluded.passcode,cards.passcode)")
        let notes=official["notes"] as? String ?? ""
        try q.execute([.integer(card.cid),card.id>0 ? .text(String(format:"%08lld",card.id)):.null,.text(monster ? "monster":bits&4 != 0 ? "trap":"spell"),.integer(bits),monster ? .text(String(fields.race)):.null,monster ? .text(String(fields.attribute)):.null,monster ? .text(link ? "link":bits&CardVocabulary.xyz != 0 ? "rank":"level"):.null,monster ? .integer(fields.level&0xffff):.null,monster ? .integer(fields.atk):.null,monster && !link ? .integer(fields.def):.null,pendulum ? .integer((fields.level>>24)&255):.null,pendulum ? .integer((fields.level>>16)&255):.null,link ? .integer(fields.def):.null,.text(notes.contains("公式のデュエルでは使用できません") ? "not_for_official_duel":bits&0x4000 != 0 ? "token":"normal"),.integer(fields.ot),.text(stamp)])
        let localization=try CardStatement(database:db,sql:"INSERT OR REPLACE INTO card_localizations VALUES (?,?,?,?,?,?,?,?,?,?,?,?)")
        try localization.execute([.integer(card.cid),.text("ja"),.text("official-db"),.text(ja),.text(raw["jp_ruby"] as? String ?? ja),.text(card.text.types ?? ""),.text(""),.text(text),.text(official["pdesc"] as? String ?? ""),.text(notes),.null,.text(stamp)])
        if let cn=raw["official_cn"] as? [String:String],let name=cn["name"],let desc=cn["text"] {
            try localization.execute([.integer(card.cid),.text("zh-Hans"),.text("official-db"),.text(name),.null,.text(""),.text(""),.text(desc),.text(cn["pdesc"] ?? ""),.text(""),.null,.text(stamp)])
        }
        if let nw=raw["nwbbs_n"] as? String,!nw.isEmpty,let body=raw["nw_text"] as? [String:Any],let desc=body["desc"] as? String,!desc.isEmpty {
            try localization.execute([.integer(card.cid),.text("zh-Hans"),.text("ygocdb"),.text(nw),.null,.text(body["types"] as? String ?? ""),.text(""),.text(desc),.text(body["pdesc"] as? String ?? ""),.text(""),.null,.text(stamp)])
        }
        let alias=try CardStatement(database:db,sql:"INSERT OR IGNORE INTO card_aliases(cid,locale,source,name,normalized_name,kind) VALUES (?,?,?,?,?,'translation')")
        for key in ["jp_name","jp_ruby","sc_name","nwbbs_n","cn_name","en_name","cnocg_n"] {
            if let name=raw[key] as? String,!name.isEmpty {try alias.execute([.integer(card.cid),.text(key.hasPrefix("jp") ? "ja":key=="en_name" ? "en":"zh-Hans"),.text(key),.text(name),.text(CardVocabulary.normalize(name))])}
        }
        for (position,row) in (official["printings"] as? [[String:Any]] ?? []).enumerated() {
            guard let pid=row["pid"] as? String,let name=row["pack"] as? String,let number=row["number"] as? String,let code=row["rarity"] as? String,let rid=row["rid"] as? String else{throw CardCatalogError.invalidData}
            let key="konami:ocg:rid:"+rid
            let rarity=try CardStatement(database:db,sql:"INSERT OR IGNORE INTO rarities VALUES (?,'official-db',?,?,NULL,NULL,1)");try rarity.execute([.text(key),.text(rid),.text(code)])
            let local=try CardStatement(database:db,sql:"INSERT OR REPLACE INTO rarity_localizations VALUES (?,'ja','official-db',?,?)");try local.execute([.text(key),.text(code),.text(row["rarity_name"] as? String ?? code)])
            let pack=try CardStatement(database:db,sql:"INSERT OR IGNORE INTO packs VALUES ('ja',?,?,?,'unknown',NULL,?,?)")
            try pack.execute([.text(pid),.text(name),.text(row["date"] as? String ?? ""),.text(CollectionService.catalogURL("ja").absoluteString),.text(stamp)])
            let printing=try CardStatement(database:db,sql:"INSERT OR IGNORE INTO printings(locale,pid,cid,card_number,number_status,rarity_id,position,source_url,fetched_at) VALUES ('ja',?,?,?,?,?,?,?,?)")
            try printing.execute([.text(pid),.integer(card.cid),.text(number),.text(number.isEmpty ? "source-empty":"known"),.text(key),.integer(Int64(position)),.text("\(PrivateConfiguration.value("officialDatabaseOrigin"))/yugiohdb/card_search.action?ope=2&cid=\(card.cid)&request_locale=ja"),.text(stamp)])
        }
    }
}

extension OfficialRarityCatalog {
    static func loadDefinitions()->[Definition] {
        guard let url=Bundle.main.url(forResource:"catalog",withExtension:"sqlite",subdirectory:"CardData") else{return []}
        var p:OpaquePointer?
        guard sqlite3_open_v2(url.path,&p,SQLITE_OPEN_READONLY,nil)==SQLITE_OK,let p else{return []}
        defer{sqlite3_close(p)}
        do {
            let q=try CardStatement(database:p,sql:"SELECT r.source_rid,r.code,l.name,r.color_hex,r.display_order FROM rarities r JOIN rarity_localizations l USING(rarity_id) WHERE l.locale='ja' AND l.source=(SELECT z.source FROM rarity_localizations z WHERE z.rarity_id=r.rarity_id AND z.locale='ja' ORDER BY CASE z.source WHEN 'official-db' THEN 0 ELSE 1 END LIMIT 1) AND r.display_order IS NOT NULL ORDER BY r.display_order DESC")
            var rows:[Definition]=[];while try q.next(){rows.append(.init(rid:q.text(0)!,code:q.text(1)!,name:q.text(2)!,colorHex:q.text(3),order:Int(q.integer(4)!)))};return rows
        } catch{return []}
    }
}
