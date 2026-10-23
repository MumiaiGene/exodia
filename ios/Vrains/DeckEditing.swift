import SwiftUI
import Observation
import UniformTypeIdentifiers

struct DeckCard: Codable, Hashable, Identifiable, Sendable {
    var cid: Int64
    var ciid: Int64 = 1
    var id: String { "\(cid):\(ciid)" }
}

enum DeckZone: String, CaseIterable, Identifiable, Sendable {
    case main = "主卡组", extra = "额外卡组", side = "副卡组"
    var id: String { switch self { case .main:"main"; case .extra:"extra"; case .side:"side" } }
    var capacity: Int { self == .main ? 60 : 15 }
}

enum DeckLibrarySort: String, CaseIterable {
    case updated, name, custom
    func sorted(_ decks: [Deck], ascending: Bool) -> [Deck] {
        guard self != .custom else { return decks }
        return decks.sorted { a,b in
            if self == .updated, a.modifiedAt != b.modifiedAt { return ascending ? a.modifiedAt < b.modifiedAt : a.modifiedAt > b.modifiedAt }
            let order = a.name.localizedStandardCompare(b.name)
            if order != .orderedSame { return ascending ? order == .orderedAscending : order == .orderedDescending }
            return a.id < b.id
        }
    }
}

struct DeckEditState: Equatable {
    var name: String
    var description: String
    var cover: DeckCard?
    var main: [DeckCard]
    var extra: [DeckCard]
    var side: [DeckCard]
    init(_ deck: Deck) {
        name = deck.name; description = deck.deckDescription ?? ""; cover = deck.coverArtwork ?? deck.coverCID.map { DeckCard(cid:$0) }
        main = deck.mainArtworks; extra = deck.extraArtworks; side = deck.sideArtworks
    }
    subscript(_ zone: DeckZone) -> [DeckCard] {
        get { switch zone { case .main:main; case .extra:extra; case .side:side } }
        set { switch zone { case .main:main = newValue; case .extra:extra = newValue; case .side:side = newValue } }
    }
    var all: [DeckCard] { main+extra+side }
    var covers: [DeckCard] { var seen:Set<DeckCard> = []; return all.filter { seen.insert($0).inserted } }
    func applying(to deck: Deck) -> Deck {
        var result = deck
        result.name = name.trimmingCharacters(in:.whitespacesAndNewlines); result.deckDescription = description
        let legacyUnrecorded = deck.mainCardCIDs == nil && deck.mainCardArtworks == nil && all.isEmpty
        if !legacyUnrecorded {
            result.mainCardArtworks = main; result.extraCardArtworks = extra; result.sideCardArtworks = side
            result.mainCardCIDs = main.map(\.cid); result.extraCardCIDs = extra.map(\.cid); result.sideCardCIDs = side.map(\.cid)
            let validCover = cover.flatMap { all.contains($0) ? $0 : nil }
            result.coverArtwork = validCover; result.coverCID = validCover?.cid
            result.subtitle = "主卡组 \(main.count) · 额外 \(extra.count) · 副卡组 \(side.count)"
        }
        return result
    }
}

@Observable @MainActor
final class DeckEditingSession {
    private(set) var state: DeckEditState
    private var past: [DeckEditState] = []
    private var future: [DeckEditState] = []
    let format:CardFormat
    private let legacyUnrecorded:Bool
    private var ruleDetails:[Int64:CardDetails]=[:]
    private var checkedRules:Set<Int64> = []
    private var ruleRevision:Int?
    var zone = DeckZone.main
    var error: String?
    init(deck: Deck,format:CardFormat = .ocg) { state = DeckEditState(deck);self.format=deck.banlist.flatMap(CardFormat.init(rawValue:)) ?? format;legacyUnrecorded=deck.mainCardCIDs == nil && deck.mainCardArtworks == nil && deck.cards>0 }
    var legalityIssues:[DeckLegalityIssue] {
        DeckLegality.issues(state:state,format:format,details:ruleDetails,checked:checkedRules,legacyUnrecorded:legacyUnrecorded)
    }
    func refreshLegality(database:CardDatabase,revision:Int) async {
        let ids=Set(state.all.map(\.cid))
        var snapshot = ruleRevision == revision ? ruleDetails : [:]
        var checked = ruleRevision == revision ? checkedRules : []
        for cid in ids.sorted() where snapshot[cid] == nil {
            if Task.isCancelled {return}
            snapshot[cid]=try? await database.details(cid:cid);checked.insert(cid)
        }
        guard !Task.isCancelled else{return}
        ruleDetails=snapshot;checkedRules=checked;ruleRevision=revision
    }
    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }
    func change(_ operation: (inout DeckEditState)->Void) {
        var next = state; operation(&next)
        if let cover=next.cover, !next.all.contains(cover) { next.cover=nil }
        guard next != state else { return }
        past.append(state); if past.count > 100 { past.removeFirst() }; state = next; future.removeAll()
    }
    func undo() { guard let previous = past.popLast() else { return }; future.append(state); state = previous }
    func redo() { guard let next = future.popLast() else { return }; past.append(state); state = next }
    func count(cid: Int64, side: Bool) -> Int { (side ? state.side : state.main+state.extra).filter{$0.cid == cid}.count }
    func total(cid: Int64) -> Int { state.all.filter{$0.cid == cid}.count }
    nonisolated static func isExtra(_ card: CatalogCard) -> Bool { (card.typeBits ?? 0) & (0x40|0x2000|CardVocabulary.xyz|CardVocabulary.link) != 0 }
    func destination(for card: CatalogCard, side: Bool) -> DeckZone { side ? .side : Self.isExtra(card) ? .extra : .main }
    @discardableResult func add(_ card: CatalogCard, ciid: Int64, side: Bool, before targetArtwork:DeckCard? = nil)->Bool {
        let target = destination(for:card,side:side)
        guard total(cid:card.cid) < 3 else { error = "同一张卡的所有异画在主卡组、额外卡组和副卡组合计最多投入 3 张。"; return false }
        guard state[target].count < target.capacity else { error = "\(target.rawValue)最多 \(target.capacity) 张。"; return false }
        let artwork=DeckCard(cid:card.cid,ciid:ciid)
        change {
            if let targetArtwork,let index=$0[target].firstIndex(of:targetArtwork) { $0[target].insert(artwork,at:index) }
            else if let last=$0[target].lastIndex(of:artwork) { $0[target].insert(artwork,at:last+1) }
            else { $0[target].append(artwork) }
        }
        return true
    }
    func searchDropZone(for card:CatalogCard)->DeckZone {
        if Self.isExtra(card) {return .extra}
        return zone == .side ? .side:.main
    }
    @discardableResult func insertFromSearch(_ card:CatalogCard,ciid:Int64,before target:DeckCard? = nil)->Bool {
        let destination=searchDropZone(for:card)
        guard add(card,ciid:ciid,side:destination == .side,before:target) else{return false}
        zone=destination;return true
    }
    @discardableResult func removeArtwork(_ artwork:DeckCard,in zone:DeckZone)->Bool {
        guard let index=state[zone].lastIndex(of:artwork) else{return false}
        change{$0[zone].remove(at:index)};return true
    }
    func remove(_ card: CatalogCard, ciid: Int64, side: Bool) {
        let target = destination(for:card,side:side), chosen = DeckCard(cid:card.cid,ciid:ciid)
        let cards = state[target]
        // Remove the displayed artwork first, then another artwork of the same card if necessary.
        guard let index = cards.lastIndex(of:chosen) ?? cards.lastIndex(where:{$0.cid == card.cid}) else { return }
        change { $0[target].remove(at:index) }
    }
    func groups(in zone: DeckZone) -> [DeckCard] { var seen:Set<DeckCard> = []; return state[zone].filter{seen.insert($0).inserted} }
    func moveToEnd(_ card:DeckCard,in zone:DeckZone) {
        guard state[zone].contains(card) else{return}
        change { draft in let copies=draft[zone].filter{$0==card};draft[zone].removeAll{$0==card};draft[zone].append(contentsOf:copies) }
    }
    func move(_ card: DeckCard, before target: DeckCard, in zone: DeckZone) {
        guard card != target, state[zone].contains(card), state[zone].contains(target) else { return }
        change { draft in
            let count = draft[zone].filter{$0 == card}.count
            var cards = draft[zone].filter{$0 != card}
            guard let index = cards.firstIndex(of:target) else { return }
            cards.insert(contentsOf:Array(repeating:card,count:count),at:index); draft[zone] = cards
        }
    }
}

struct DeckDrawState {
    private(set) var result: [DeckCard] = []
    private(set) var remaining: [DeckCard] = []
    mutating func start<R: RandomNumberGenerator>(cards:[DeckCard],using generator:inout R) {
        let shuffled = cards.shuffled(using:&generator)
        result = Array(shuffled.prefix(5)); remaining = Array(shuffled.dropFirst(min(5,shuffled.count)))
    }
    mutating func start(cards:[DeckCard]) { var rng = SystemRandomNumberGenerator(); start(cards:cards,using:&rng) }
    mutating func drawOne() { guard !remaining.isEmpty else { return }; result.append(remaining.removeFirst()) }
}

struct DeckExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(deck: Deck) { data = (try? JSONEncoder().encode(deck)) ?? Data() }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents:data) }
}

struct DeckLegalityIssue:Identifiable,Equatable {
    let id:String
    let message:String
    var summary:String {
        if id.hasPrefix("main.") {return "卡组数量"}
        if id.hasPrefix("extra.") {return "额外卡组数量"}
        if id.hasPrefix("side.") {return "副卡组数量"}
        if id.hasPrefix("copies:") {
            if message.hasPrefix("禁止卡") {return "禁止卡数量"}
            if message.hasPrefix("限制卡") {return "限制卡数量"}
            if message.hasPrefix("准限制卡") {return "准限制卡数量"}
            return "同名卡数量"
        }
        if id.hasPrefix("placement.") {return "卡片区域"}
        if id.hasPrefix("release:") {return "未发售卡片"}
        if id.hasPrefix("token:") {return "衍生物卡片"}
        return "卡片资料"
    }
}

enum DeckLegality {
    static func issues(state:DeckEditState,format:CardFormat,details:[Int64:CardDetails],checked:Set<Int64> = [],legacyUnrecorded:Bool = false)->[DeckLegalityIssue] {
        if legacyUnrecorded && state.all.isEmpty {
            return [DeckLegalityIssue(id:"legacy",message:"旧版卡组尚未录入逐张清单，暂时无法确认合法性。")]
        }
        var result:[DeckLegalityIssue]=[]
        if state.main.count<40 {result.append(.init(id:"main.minimum",message:"主卡组至少需要 40 张，当前 \(state.main.count) 张，还差 \(40-state.main.count) 张。"))}
        if state.main.count>60 {result.append(.init(id:"main.maximum",message:"主卡组最多 60 张，当前 \(state.main.count) 张。"))}
        for zone in [DeckZone.extra,.side] where state[zone].count>15 {
            result.append(.init(id:"\(zone.id).maximum",message:"\(zone.rawValue)最多 15 张，当前 \(state[zone].count) 张。"))
        }
        let counts=Dictionary(grouping:state.all,by:\.cid).mapValues(\.count)
        for cid in counts.keys.sorted() {
            let copies=counts[cid]!
            guard let info=details[cid] else {
                if copies>3 {result.append(.init(id:"copies:\(cid)",message:"卡片 \(cid) 的各异画合计 \(copies) 张，最多投入 3 张。"))}
                if checked.contains(cid) {result.append(.init(id:"unknown:\(cid)",message:"卡片 \(cid) 的资料暂不可用，无法确认是否合法。"))}
                continue
            }
            let name=info.card.name
            if (info.card.typeBits ?? 0) & 0x4000 != 0 {
                result.append(.init(id:"token:\(cid)",message:"「\(name)」是衍生物，不能投入卡组。"));continue
            }
            if let allowed=info.limitCopies(in:format) {
                let maximum=max(0,min(3,allowed))
                if copies>maximum {
                    let description = maximum == 0 ? "禁止卡「\(name)」不能投入，当前合计 \(copies) 张。" : maximum == 1 ? "限制卡「\(name)」最多 1 张，当前各异画合计 \(copies) 张。" : maximum == 2 ? "准限制卡「\(name)」最多 2 张，当前各异画合计 \(copies) 张。" : "「\(name)」最多 3 张，当前各异画合计 \(copies) 张。"
                    result.append(.init(id:"copies:\(cid)",message:description))
                }
            } else {
                result.append(.init(id:"release:\(cid)",message:"「\(name)」尚未在\(format.title)环境发售，不能用于该卡组。"))
                if copies>3 {result.append(.init(id:"copies:\(cid)",message:"「\(name)」的各异画合计 \(copies) 张，最多投入 3 张。"))}
            }
            let isExtra=DeckEditingSession.isExtra(info.card)
            if isExtra && state.main.contains(where:{$0.cid==cid}) {
                result.append(.init(id:"placement.main:\(cid)",message:"「\(name)」是额外卡组怪兽，不能放在主卡组。"))
            }
            if !isExtra && state.extra.contains(where:{$0.cid==cid}) {
                result.append(.init(id:"placement.extra:\(cid)",message:"「\(name)」不能放在额外卡组。"))
            }
        }
        return result
    }
}
