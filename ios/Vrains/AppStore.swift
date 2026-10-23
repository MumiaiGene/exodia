import SwiftUI
import Observation

enum ArtworkKind: String, Codable, CaseIterable {
    case blue, forest, ember, violet
    var colors: [Color] {
        switch self {
        case .blue: [Color(hex: 0x0C173F), Color(hex: 0x3157B7), Color(hex: 0xB6D5FC)]
        case .forest: [Color(hex: 0x103C3C), Color(hex: 0x438775), Color(hex: 0xC1DBAE)]
        case .ember: [Color(hex: 0x481524), Color(hex: 0xB35550), Color(hex: 0xF5CBA1)]
        case .violet: [Color(hex: 0x282045), Color(hex: 0x7769A4), Color(hex: 0xD4C8E9)]
        }
    }
    var symbol: String {
        switch self {
        case .blue: "sparkles"
        case .forest: "leaf.fill"
        case .ember: "flame.fill"
        case .violet: "moon.stars.fill"
        }
    }
    var defaultCoverCID:Int64 {
        switch self {case .blue:4007;case .forest:11213;case .ember:20029;case .violet:4041}
    }
}

struct Deck: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var subtitle: String
    var kind: ArtworkKind
    var cards: Int
    var isMine: Bool
    var updatedAt: Date? = nil
    var coverCID: Int64? = nil
    var mainCardCIDs: [Int64]? = nil
    var extraCardCIDs: [Int64]? = nil
    var sideCardCIDs: [Int64]? = nil
    var deckDescription: String? = nil
    var coverArtwork: DeckCard? = nil
    var mainCardArtworks: [DeckCard]? = nil
    var extraCardArtworks: [DeckCard]? = nil
    var sideCardArtworks: [DeckCard]? = nil
    var isFavorite: Bool? = nil
    var banlist: String? = nil
    var mainArtworks: [DeckCard] { mainCardArtworks ?? (mainCardCIDs ?? []).map { DeckCard(cid:$0) } }
    var extraArtworks: [DeckCard] { extraCardArtworks ?? (extraCardCIDs ?? []).map { DeckCard(cid:$0) } }
    var sideArtworks: [DeckCard] { sideCardArtworks ?? (sideCardCIDs ?? []).map { DeckCard(cid:$0) } }
    var coverCard: DeckCard? { coverArtwork ?? coverCID.map { DeckCard(cid:$0) } }
    var modifiedAt:Date {updatedAt ?? Date(timeIntervalSince1970:1_760_000_000)}
    var mainCards:[Int64]{mainArtworks.map(\.cid)}
    var extraCards:[Int64]{extraArtworks.map(\.cid)}
    var sideCards:[Int64]{sideArtworks.map(\.cid)}
    static func draft(name:String="新卡组",kind:ArtworkKind = .blue)->Deck {
        Deck(id:UUID().uuidString,name:name,subtitle:"",kind:kind,cards:0,isMine:true,updatedAt:.now,mainCardCIDs:[],extraCardCIDs:[],sideCardCIDs:[])
    }
    static let samples: [Deck] = [
        Deck(id: "blue", name: "青眼的回响", subtitle: "青眼白龙 · 展开与压制", kind: .blue, cards: 40, isMine: true),
        Deck(id: "forest", name: "森罗万象", subtitle: "自然系 · 控场与续航", kind: .forest, cards: 42, isMine: true),
        Deck(id: "ember", name: "赤焰之心", subtitle: "炎属性 · 进攻与爆发", kind: .ember, cards: 40, isMine: false),
        Deck(id: "violet", name: "月下魔术师", subtitle: "魔法师 · 连锁与变化", kind: .violet, cards: 40, isMine: false)
    ]
}

struct Tournament: Identifiable {
    let id: String
    let title: String
    let place: String
    let day: String
    let month: String
    let time: String
    let tag: String
    static let samples = [
        Tournament(id: "weekend", title: "周末决斗 · 上海站", place: "上海 · 星尘卡牌空间", day: "18", month: "10 月", time: "周日 14:00", tag: "公开赛"),
        Tournament(id: "open", title: "城市公开赛", place: "杭州 · 次元卡牌俱乐部", day: "24", month: "10 月", time: "周六 13:00", tag: "积分赛"),
        Tournament(id: "night", title: "Friday Night Duel", place: "线上 · 友谊对战", day: "30", month: "10 月", time: "周五 20:00", tag: "友谊赛")
    ]
}

@Observable @MainActor
final class AppStore {
    #if DEBUG
    private static var didResetForTesting = false
    #endif
    let account: AccountStore
    let jhs: JHSAccountStore
    let news: NewsStore
    let matches: MatchStore
    let catalog: CardCatalog
    var decks: [Deck]
    var savedCards: Set<String> {
        didSet { UserDefaults.standard.set(Array(savedCards), forKey: "exodia.prototype.cards") }
    }
    var followedMatches: Set<String> {
        didSet { UserDefaults.standard.set(Array(followedMatches), forKey: "exodia.prototype.matches") }
    }
    var isLoggedIn: Bool { account.isLoggedIn }
    var maskedPhone: String { account.maskedPhone }
    var myDecks: [Deck] { decks.filter(\.isMine) }

    init() {
        // A previous prototype phone number is not a real authenticated session.
        UserDefaults.standard.removeObject(forKey: "exodia.prototype.phone")
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        let shouldReset = args.contains("--uitesting") && args.contains("--uitesting-reset") && !Self.didResetForTesting
        if shouldReset {
            Self.didResetForTesting = true
            UserDefaults.standard.removeObject(forKey:TokenLogin.preferenceKey)
            UserDefaults.standard.removeObject(forKey:"exodia.selectedCardFormat")
            for key in ["exodia.decks.view","exodia.decks.sort","exodia.decks.ascending"] { UserDefaults.standard.removeObject(forKey:key) }
        }
        if args.contains("--uitesting") {
            let storage = KeychainSessionStorage(service: "com.localdevelopment.Exodia.uitesting")
            let jhsStorage = JHSKeychainSessionStorage(service:"com.localdevelopment.Exodia.jhs.uitesting")
            if shouldReset { try? storage.clear() }
            if shouldReset { try? jhsStorage.clear() }
            if args.contains("--uitesting-jhs-bound") {
                try? jhsStorage.save(JHSSavedSession(token:"jhs-ui-market-session",phone:"13800138000",userID:"77",username:"测试集换社账号",avatarURL:nil))
            }
            account = AccountStore(api: BusinessAPI(transport: TestAPITransport(expired: args.contains("--uitesting-expired"), offline: args.contains("--uitesting-offline"))), storage: storage)
            jhs = JHSAccountStore(api:JHSAuthAPI(transport:TestJHSAPITransport()),storage:jhsStorage)
        } else {
            account = AccountStore()
            jhs = JHSAccountStore()
        }
        if shouldReset {
            UserDefaults(suiteName:"com.localdevelopment.Exodia.preorders.uitesting")?.removeObject(forKey:JHSPreorderStore.storageKey)
            try? FileManager.default.removeItem(at:JHSMatchJobsStore.storageURL)
            for key in ["phone", "cards", "matches", "decks"] {
                UserDefaults.standard.removeObject(forKey: "exodia.prototype.\(key)")
            }
        }
        #else
        account = AccountStore()
        jhs = JHSAccountStore()
        #endif
        news = NewsStore(api: account.api)
        matches = MatchStore(api: account.api)
        #if DEBUG
        if args.contains("--uitesting") {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            // Keep schema-v2 test data separate from the retired prototype test library.
            catalog = CardCatalog(database: CardDatabase(url: directory.appendingPathComponent("Exodia/UITestCatalog-v2.sqlite")), transport: TestAPITransport(offline: true))
        } else { catalog = CardCatalog() }
        #else
        catalog = CardCatalog()
        #endif
        savedCards = Set(UserDefaults.standard.stringArray(forKey: "exodia.prototype.cards") ?? [])
        followedMatches = Set(UserDefaults.standard.stringArray(forKey: "exodia.prototype.matches") ?? [])
        if let data = UserDefaults.standard.data(forKey: "exodia.prototype.decks"),
           let saved = try? JSONDecoder().decode([Deck].self, from: data) {
            decks = saved
        } else {
            decks = Deck.samples
        }
        #if DEBUG
        if args.contains("--uitesting-deck-fixture"),let index=decks.firstIndex(where:{$0.id=="blue"}) {
            var value=decks[index]
            var main=Array((4007...4020).flatMap{cid in Array(repeating:DeckCard(cid:Int64(cid)),count:3)}.prefix(40))
            main[0].ciid=19
            value.mainCardArtworks=main;value.mainCardCIDs=main.map(\.cid)
            value.extraCardArtworks=[DeckCard(cid:13036),DeckCard(cid:9575)];value.extraCardCIDs=[13036,9575]
            value.sideCardArtworks=[DeckCard(cid:4758),DeckCard(cid:4842)];value.sideCardCIDs=[4758,4842]
            value.coverArtwork=main[0];value.coverCID=4007;value.deckDescription="日文异画构筑 · 测试卡组";value.cards=44
            decks[index]=value
        }
        #endif

    }

    @discardableResult func addDeck(name: String, kind: ArtworkKind) -> Deck {
        let deck=Deck.draft(name:name,kind:kind)
        decks.insert(deck,at:0)
        persistDecks()
        return deck
    }
    func saveDeck(_ deck: Deck) {
        var updated=deck;updated.isMine=true;updated.updatedAt = .now
        if updated.mainCardCIDs != nil || updated.mainCardArtworks != nil { updated.cards=updated.mainCards.count+updated.extraCards.count+updated.sideCards.count }
        if let index=decks.firstIndex(where:{$0.id==deck.id}) {decks[index]=updated}
        else {decks.insert(updated,at:0)}
        persistDecks()
    }
    func toggleDeckFavorite(id:String) {
        guard let index=decks.firstIndex(where:{$0.id==id}) else{return}
        decks[index].isFavorite = !(decks[index].isFavorite ?? false);persistDecks()
    }
    @discardableResult func duplicateDeck(_ source:Deck)->Deck {
        var copy=source;copy.id=UUID().uuidString;copy.name=source.name+" 副本";copy.updatedAt = .now;copy.isMine=true
        decks.insert(copy,at:0);persistDecks();return copy
    }
    func deleteDeck(id:String) {
        decks.removeAll{$0.id==id};persistDecks()
    }
    func moveMyDecks(from source:IndexSet,to destination:Int) {
        var mine=myDecks;mine.move(fromOffsets:source,toOffset:destination)
        decks=mine+decks.filter{!$0.isMine};persistDecks()
    }
    func toggleCard(_ id: String) {
        if savedCards.contains(id) { savedCards.remove(id) } else { savedCards.insert(id) }
    }
    func toggleMatch(_ id: String) {
        if followedMatches.contains(id) { followedMatches.remove(id) } else { followedMatches.insert(id) }
    }
    private func persistDecks() {
        if let data = try? JSONEncoder().encode(decks) {
            UserDefaults.standard.set(data, forKey: "exodia.prototype.decks")
        }
    }
}
