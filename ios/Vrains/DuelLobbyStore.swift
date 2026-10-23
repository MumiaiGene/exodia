import Foundation
import Observation

struct DuelAppearance: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let subtitle: String
    let symbol: String
    let color: UInt32

    static let mates: [Self] = [
        .init(id:"kuriboh",name:"栗子球",subtitle:"小小伙伴，一起迎接每个回合",symbol:"pawprint.fill",color:0xAC765B),
        .init(id:"dragon",name:"青眼白龙",subtitle:"与传说中的白龙并肩",symbol:"sparkles",color:0x557CB5),
        .init(id:"magician",name:"黑魔导",subtitle:"来自魔法世界的守护",symbol:"wand.and.stars",color:0x8C68B6)
    ]
    static let fields: [Self] = [
        .init(id:"temple",name:"星辉圣殿",subtitle:"星光照亮决斗的舞台",symbol:"sparkle",color:0x465BA2),
        .init(id:"forest",name:"森之秘境",subtitle:"在绿意与微光中交锋",symbol:"leaf.fill",color:0x387E6D),
        .init(id:"volcano",name:"赤焰领域",subtitle:"让下一回合燃起热情",symbol:"flame.fill",color:0xB7595E)
    ]
}

struct DuelServerOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let rules: String
    let mode: String
    // These are local demo queues, not addresses of public duel servers.
    static let options: [Self] = [
        .init(id:"demo-single",name:"演示服务器 · 单局",rules:"OCG · 大师规则 5",mode:"Single"),
        .init(id:"demo-match",name:"演示服务器 · 三局两胜",rules:"OCG · 大师规则 5",mode:"Match")
    ]
}

struct DuelLobbyPreferences: Codable, Equatable {
    var deckID: String?
    var mateID = DuelAppearance.mates[0].id
    var fieldID = DuelAppearance.fields[0].id
    var serverID = DuelServerOption.options[0].id
}

struct DuelMatchConfiguration: Sendable, Equatable {
    let deckID: String
    let deckName: String
    let cardCount: Int
    let mate: DuelAppearance
    let field: DuelAppearance
    let server: DuelServerOption
}

struct DuelMatchSession: Identifiable, Sendable {
    let id: UUID
    let configuration: DuelMatchConfiguration
    let opponentName: String
    let isDemo: Bool
}

protocol DuelMatchmaking: Sendable {
    func findOpponent(configuration: DuelMatchConfiguration) async throws -> DuelMatchSession
}

struct DemoDuelMatchmaker: DuelMatchmaking {
    var delay: Duration = .seconds(4)
    func findOpponent(configuration: DuelMatchConfiguration) async throws -> DuelMatchSession {
        try await Task.sleep(for:delay)
        try Task.checkCancellation()
        return DuelMatchSession(id:UUID(),configuration:configuration,opponentName:"星尘 · 演示对手",isDemo:true)
    }
}

@Observable @MainActor
final class DuelLobbyStore {
    static let preferencesKey = "exodia.duel.lobby.preferences.v1"
    var preferences: DuelLobbyPreferences {
        didSet {
            if let data=try? JSONEncoder().encode(preferences) { defaults.set(data,forKey:Self.preferencesKey) }
        }
    }
    private(set) var isSearching=false
    private(set) var pendingSession:DuelMatchSession?
    var previewSession:DuelMatchSession?
    var errorMessage:String?
    var mate:DuelAppearance { DuelAppearance.mates.first{$0.id==preferences.mateID} ?? DuelAppearance.mates[0] }
    var field:DuelAppearance { DuelAppearance.fields.first{$0.id==preferences.fieldID} ?? DuelAppearance.fields[0] }
    var server:DuelServerOption { DuelServerOption.options.first{$0.id==preferences.serverID} ?? DuelServerOption.options[0] }
    @ObservationIgnored private let defaults:UserDefaults
    @ObservationIgnored private let matchmaker:any DuelMatchmaking
    @ObservationIgnored private var operation:Task<Void,Never>?
    @ObservationIgnored private var searchID:UUID?

    init(defaults:UserDefaults = .standard,matchmaker:(any DuelMatchmaking)? = nil) {
        self.defaults=defaults
        #if DEBUG
        let args=ProcessInfo.processInfo.arguments
        if args.contains("--uitesting-reset") { defaults.removeObject(forKey:Self.preferencesKey) }
        self.matchmaker=matchmaker ?? DemoDuelMatchmaker(delay:args.contains("--uitesting-duel-hold") ? .seconds(60):.seconds(4))
        #else
        self.matchmaker=matchmaker ?? DemoDuelMatchmaker()
        #endif
        if let data=defaults.data(forKey:Self.preferencesKey),let saved=try? JSONDecoder().decode(DuelLobbyPreferences.self,from:data) {
            preferences=saved
        } else { preferences=DuelLobbyPreferences() }
    }

    func reconcileDecks(_ decks:[Deck]) {
        guard !isSearching,pendingSession==nil,previewSession==nil else { return }
        if !decks.contains(where:{$0.id==preferences.deckID}) { preferences.deckID=decks.first?.id }
    }

    func configuration(for decks:[Deck]) -> DuelMatchConfiguration? {
        guard let deck=decks.first(where:{$0.id==preferences.deckID}),deck.cards>0 else { return nil }
        return .init(deckID:deck.id,deckName:deck.name,cardCount:deck.cards,mate:mate,field:field,server:server)
    }

    func startSearch(decks:[Deck]) {
        guard !isSearching,pendingSession==nil,previewSession==nil,let configuration=configuration(for:decks) else { return }
        errorMessage=nil
        let id=UUID()
        searchID=id
        isSearching=true
        operation=Task { [weak self,matchmaker] in
            do {
                let session=try await matchmaker.findOpponent(configuration:configuration)
                guard let self,self.searchID==id,!Task.isCancelled else { return }
                self.pendingSession=session
                self.isSearching=false
                self.operation=nil
                self.searchID=nil
            } catch {
                guard let self,self.searchID==id else { return }
                self.isSearching=false
                self.operation=nil
                self.searchID=nil
                if !(error is CancellationError) { self.errorMessage="匹配未完成，请稍后重试。" }
            }
        }
    }

    func cancelSearch() {
        searchID=nil
        operation?.cancel()
        operation=nil
        pendingSession=nil
        isSearching=false
    }

    /// Called after the matching sheet has finished dismissing, so the game
    /// destination never competes with that presentation transition.
    func openPendingMatch() {
        guard let session=pendingSession else { return }
        pendingSession=nil
        previewSession=session
    }
}
