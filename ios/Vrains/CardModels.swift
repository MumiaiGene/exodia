import Foundation

enum CardCatalogError: LocalizedError {
    case database, invalidData, checksum, archive, invalidRange, incompatibleSchema
    var errorDescription: String? {
        switch self {
        case .database: "无法读取本机卡库，请稍后重试。"
        case .invalidData: "下载的卡牌数据格式不完整，原卡库已保留。"
        case .checksum: "卡牌数据校验失败，原卡库已保留，请重新检查更新。"
        case .archive: "卡牌数据包无法解压，原卡库已保留。"
        case .invalidRange: "请填写有效的数值范围，最小值不能大于最大值。"
        case .incompatibleSchema: "卡库版本不兼容，请更新 App。"
        }
    }
}

struct CardOption: Identifiable, Hashable, Sendable {
    let id: Int64
    let title: String
}

enum CardVocabulary {
    static let monster: Int64 = 1
    static let spell: Int64 = 2
    static let trap: Int64 = 4
    static let xyz: Int64 = 0x800000
    static let pendulum: Int64 = 0x1000000
    static let link: Int64 = 0x4000000
    static let types = [
        CardOption(id: 0x10, title: "通常"), CardOption(id: 0x20, title: "效果"),
        CardOption(id: 0x40, title: "融合"), CardOption(id: 0x80, title: "仪式"),
        CardOption(id: 0x2000, title: "同调"), CardOption(id: xyz, title: "超量"),
        CardOption(id: pendulum, title: "灵摆"), CardOption(id: link, title: "连接"),
        CardOption(id: 0x1000, title: "调整"), CardOption(id: 0x200000, title: "反转"),
        CardOption(id: 0x10000, title: "速攻"), CardOption(id: 0x20000, title: "永续"),
        CardOption(id: 0x40000, title: "装备"), CardOption(id: 0x80000, title: "场地"),
        CardOption(id: 0x100000, title: "反击"), CardOption(id: 0x4000, title: "衍生物")
    ]
    static let monsterTypes = [
        CardOption(id: 0x10, title: "通常"), CardOption(id: 0x20, title: "效果"),
        CardOption(id: 0x80, title: "仪式"), CardOption(id: 0x40, title: "融合"),
        CardOption(id: 0x2000, title: "同步"), CardOption(id: xyz, title: "超量"),
        CardOption(id: link, title: "连接"), CardOption(id: 0x400000, title: "卡通"),
        CardOption(id: 0x200, title: "灵魂"), CardOption(id: 0x400, title: "联合"),
        CardOption(id: 0x800, title: "二重"), CardOption(id: 0x1000, title: "协调"),
        CardOption(id: 0x200000, title: "反转"), CardOption(id: pendulum, title: "灵摆"),
        CardOption(id: 0x2000000, title: "特殊召唤")
    ]
    static let spellKinds = [
        CardOption(id: 0, title: "通常"), CardOption(id: 0x80, title: "仪式"),
        CardOption(id: 0x10000, title: "速攻"), CardOption(id: 0x20000, title: "永续"),
        CardOption(id: 0x40000, title: "装备"), CardOption(id: 0x80000, title: "场地")
    ]
    static let trapKinds = [
        CardOption(id: 0, title: "通常"), CardOption(id: 0x20000, title: "永续"),
        CardOption(id: 0x100000, title: "反击")
    ]
    static let nonMonsterKindMask:Int64=65536|131072|262144|524288|128|1048576
    static let attributes = ["地", "水", "炎", "风", "光", "暗", "神"].enumerated().map { CardOption(id: 1 << $0.offset, title: $0.element) }
    static let races = ["战士", "魔法师", "天使", "恶魔", "不死", "机械", "水", "炎", "岩石", "鸟兽", "植物", "昆虫", "雷", "龙", "兽", "兽战士", "恐龙", "鱼", "海龙", "爬虫类", "念动力", "幻神兽", "创造神", "幻龙", "电子界", "幻想魔"].enumerated().map { CardOption(id: 1 << $0.offset, title: $0.element + "族") }
    static func normalize(_ text: String) -> String { text.precomposedStringWithCompatibilityMapping.lowercased() }
}

enum CardFormat: String, CaseIterable, Identifiable, Sendable {
    case ocg = "ja", tcg = "en", simplified = "cn"
    var id: String { rawValue }
    var title: String { switch self { case .ocg: "OCG（日文）"; case .tcg: "TCG（英文）"; case .simplified: "简体中文" } }
    var releaseLanguage: String { switch self { case .ocg: "jp"; case .tcg: "en"; case .simplified: "sc" } }
}

enum CardSort: String, CaseIterable, Identifiable, Sendable {
    case name = "卡名", level = "等级 / 阶级", attack = "ATK", defense = "DEF"
    case scale = "灵摆刻度", link = "连接数", releaseDate = "发售日"
    var id: String { rawValue }
}

struct CardFilter: Hashable, Sendable {
    var baseType: Int64 = 0
    var subtype: Int64 = 0
    var excludedSubtype: Int64 = 0
    var monsterTypeMatchAll = false
    var normalNonMonster = false
    var spellKinds: Int64 = 0
    var includesNormalSpell = false
    var trapKinds: Int64 = 0
    var includesNormalTrap = false
    var attribute: Int64 = 0
    var race: Int64 = 0
    var levelKind = ""
    var minLevel = "", maxLevel = ""
    var selectedLevels: Int64 = 0
    var minAttack = "", maxAttack = "", minDefense = "", maxDefense = ""
    var leftScale = "", rightScale = ""
    var selectedScales: Int64 = 0
    var selectedLinkRatings: Int64 = 0
    var linkMarkers: Int64 = 0
    var linkMarkerMatchAll = false
    var unknownAttack = false
    var unknownDefense = false
    var seriesCode = "", seriesName = "", pack = ""
    var releaseLanguage = ""
    var rarity = "", printingPack = ""
    var rarities: Set<String> = []
    var releaseDateFrom = "", releaseDateTo = ""
    var format: CardFormat = .ocg
    var limitCopies = -1
    var limitStatuses: Int64 = 0
    var favoritesOnly = false
    var sort: CardSort = .releaseDate
    var sortAscending = false
    var activeCount: Int {
        [subtype != 0 || excludedSubtype != 0, spellKinds != 0 || includesNormalSpell,
         trapKinds != 0 || includesNormalTrap || normalNonMonster, attribute != 0, race != 0, !levelKind.isEmpty,
         selectedLevels != 0 || !minLevel.isEmpty || !maxLevel.isEmpty,
         !minAttack.isEmpty || !maxAttack.isEmpty || !minDefense.isEmpty || !maxDefense.isEmpty || unknownAttack || unknownDefense,
         selectedScales != 0 || !leftScale.isEmpty || !rightScale.isEmpty,
         selectedLinkRatings != 0 || linkMarkers != 0,
         !seriesCode.isEmpty || !seriesName.isEmpty, !pack.isEmpty, !releaseLanguage.isEmpty,
         limitCopies >= 0 || limitStatuses != 0, !rarity.isEmpty || !rarities.isEmpty || !printingPack.isEmpty,
         !releaseDateFrom.isEmpty || !releaseDateTo.isEmpty].filter { $0 }.count
    }
    func validate() throws {
        for (minimum, maximum) in [(minLevel, maxLevel), (minAttack, maxAttack), (minDefense, maxDefense)] {
            if !minimum.isEmpty, Int(minimum) == nil || (Int(minimum) ?? -1) < 0 { throw CardCatalogError.invalidRange }
            if !maximum.isEmpty, Int(maximum) == nil || (Int(maximum) ?? -1) < 0 { throw CardCatalogError.invalidRange }
            if let low = Int(minimum), let high = Int(maximum), low > high { throw CardCatalogError.invalidRange }
        }
        for value in [leftScale, rightScale, seriesCode] where !value.isEmpty {
            guard let number = Int64(value), number >= 0 else { throw CardCatalogError.invalidRange }
        }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd"
        for value in [releaseDateFrom, releaseDateTo] where !value.isEmpty {
            guard parser.date(from: value) != nil else { throw CardCatalogError.invalidRange }
        }
        if !releaseDateFrom.isEmpty, !releaseDateTo.isEmpty, releaseDateFrom > releaseDateTo {
            throw CardCatalogError.invalidRange
        }
    }
}

struct CatalogCard: Identifiable, Hashable, Sendable {
    let cid: Int64
    let passcode: Int64?
    let name: String
    let description: String
    let pendulumDescription: String
    let typeText: String
    let typeBits: Int64?
    let race: Int64?
    let attribute: Int64?
    let level: Int64?
    let levelKind: String?
    let attack: Int64?
    let defense: Int64?
    let leftScale: Int64?
    let rightScale: Int64?
    let linkMarkers: Int64?
    let ot: Int64?
    let setcode: String?
    let seriesText: String
    var id: Int64 { cid }
    var favoriteKey: String { "cid:\(cid)" }
    var passwordLabel: String { passcode.map { String(format: "%08lld", $0) } ?? "尚未公开" }
    var artwork: ArtworkKind { attribute == 4 ? .ember : attribute == 32 ? .violet : attribute == 16 ? .blue : .forest }
    var isMonster: Bool { (typeBits ?? 0) & 1 != 0 }
    var isPendulum: Bool { (typeBits ?? 0) & CardVocabulary.pendulum != 0 }
    var isTrap: Bool { (typeBits ?? 0) & 4 != 0 || typeText.hasPrefix("[陷阱") }
    var attributeIcon: String {
        guard isMonster else { return isTrap ? "attribute-trap" : "attribute-spell" }
        return "attribute-" + ([Int64(1):"earth",2:"water",4:"fire",8:"wind",16:"light",32:"dark",64:"divine"][attribute ?? 0] ?? "dark")
    }
    var attributeTitle: String {
        guard isMonster else { return isTrap ? "陷阱" : "魔法" }
        return (CardVocabulary.attributes.first { $0.id == attribute }?.title ?? "—") + "属性"
    }
    var spellTrapKind: String {
        let bits=typeBits ?? 0
        for (flag,name) in [(Int64(65536),"速攻"),(1048576,"反击"),(128,"仪式"),(524288,"场地"),(262144,"装备"),(131072,"永续")] where bits & flag != 0 { return name }
        return "通常"
    }
    var spellTrapIcon: String {
        let codes=["速攻":"quickplay","反击":"counter","仪式":"ritual","场地":"field","装备":"equip","永续":"continuous"]
        return codes[spellTrapKind].map { "effect-"+$0 } ?? attributeIcon
    }
    var spellTrapTitle: String { spellTrapKind + (isTrap ? "陷阱" : "魔法") }
    var compactTypeLine: String {
        guard isMonster else { return "【\(spellTrapKind)】" }
        let raceName=CardVocabulary.races.first { $0.id == race }?.title ?? ""
        let labels:[(Int64,String)]=[(64,"融合"),(128,"仪式"),(8192,"同步"),(8388608,"超量"),(16777216,"灵摆"),(67108864,"连接"),(512,"灵魂"),(1024,"同盟"),(2048,"二重"),(4096,"调整"),(2097152,"反转"),(4194304,"卡通"),(33554432,"特殊召唤"),(16,"通常"),(32,"效果")]
        let types=labels.filter { (typeBits ?? 0) & $0.0 != 0 }.map(\.1)
        return "【"+([raceName]+types).filter { !$0.isEmpty }.joined(separator:"/")+"】"
    }
    var levelLabel: String {
        switch levelKind { case "link": "LINK"; case "rank": "阶级"; default: "等级" }
    }
    var statsText: String {
        guard isMonster else { return typeText }
        let atk = attack.map { $0 < 0 ? "?" : String($0) } ?? "—"
        if levelKind == "link" { return "LINK-\(level ?? 0) · ATK \(atk)" }
        let def = defense.map { $0 < 0 ? "?" : String($0) } ?? "—"
        return "\(levelLabel) \(level ?? 0) · \(atk) / \(def)"
    }
    var arrows: String {
        guard let markers = linkMarkers else { return "" }
        return [(1, "↙"), (2, "↓"), (4, "↘"), (8, "←"), (32, "→"), (64, "↖"), (128, "↑"), (256, "↗")].filter { markers & Int64($0.0) != 0 }.map(\.1).joined(separator: " ")
    }
}

struct CardName: Sendable {
    let source: String
    let name: String
    var label: String {
        ["sc_name": "官方简中", "cn_name": "百鸽译名", "md_name": "Master Duel", "jp_name": "日文", "jp_ruby": "日文读音", "en_name": "英文", "nwbbs_n": "NWBBS", "cnocg_n": "CNOCG", "wiki_en": "Yugipedia"][source] ?? source
    }
}
struct CardRelease: Sendable { let language: String; let date: String?; let pack: String? }
struct OfficialPrinting: Identifiable, Sendable {
    let cid: Int64
    let pid: String
    let number: String
    let rarity: String
    let rarityName: String
    let date: String?
    let packName: String
    var id: String { "\(cid):\(pid):\(number):\(rarity)" }
}
struct OfficialDetailMetadata: Sendable {
    let cid: Int64
    let printings: [OfficialPrinting]
}
struct CardDetails: Sendable {
    let card: CatalogCard
    let names: [CardName]
    let releases: [CardRelease]
    let limits: [String: Int]
    let limitDates: [String: String]
    let setCodes: [Int64]
    var officialNotes = ""
    func limitCopies(in format: CardFormat) -> Int? {
        if officialNotes.contains("公式のデュエルでは使用できません") { return 0 }
        guard releases.contains(where: { $0.language == format.releaseLanguage }) else { return nil }
        return limits[format.rawValue] ?? 3
    }
}
struct CardResults: Sendable { let cards: [CatalogCard]; let count: Int }
struct CardMetadata: Sendable {
    let count: Int
    let hash: String
    let updatedAt: String
    let checkedAt: String
    let releasesHash: String
    let limitsHash: String
    var origin = "ygocdb"
    var sourceLabel: String { ["official-ja","catalog-v2"].contains(origin) ? "官方数据库 · 中文由官方及百鸽补充" : "百鸽" }
}

struct YGOSourceCard: Decodable {
    let cid: Int64
    let id: Int64
    let text: TextData
    let data: DataFields?
    let set_ext: String?
    struct TextData: Decodable { let types: String?; let desc: String?; let pdesc: String? }
    struct DataFields: Decodable {
        let ot: Int64; let setcode: UInt64; let type: Int64; let atk: Int64; let def: Int64
        let level: Int64; let race: Int64; let attribute: Int64
    }
}
