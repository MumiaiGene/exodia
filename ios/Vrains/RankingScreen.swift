import SwiftUI
import Observation

enum RankingCategory: Int, CaseIterable, Identifiable, Sendable {
    case ocg = 2, simplifiedChinese = 1
    var id: Int { rawValue }
    var title: String { self == .simplifiedChinese ? "简体中文" : "OCG" }
}

struct RankingSeason: Identifiable, Sendable {
    let id: String
    let name: String
}

struct RankingPlayer: Identifiable, Sendable {
    // Public rankings have no user ID, and ranks can tie. Use the list position for view identity only.
    let id: Int
    let rank: Int
    let nickname: String
    let avatar: URL?
    let points: String
    init(data: APIValue, position: Int) throws {
        guard let rank = data["rank"].int, rank > 0, let points = data["points"].text else { throw APIError.invalidResponse }
        id = position; self.rank = rank; self.points = points
        nickname = data["nickName"].text ?? "未命名决斗者"
        avatar = data["avatar"].text.flatMap(URL.init(string:))
    }
}

struct RankingPage: Sendable {
    let players: [RankingPlayer]
    let count: Int
    let personal: RankingPlayer?
    let seasons: [RankingSeason]
    let seasonID: String?
    init(data: APIValue, page: Int) throws {
        guard let rows = data["res"].values, let count = data["count"].int, count >= 0 else { throw APIError.invalidResponse }
        players = try rows.enumerated().map { try RankingPlayer(data: $0.element, position: (page - 1) * 10 + $0.offset) }
        self.count = count
        personal = data["personal"]["rank"].int.flatMap { $0 > 0 ? try? RankingPlayer(data: data["personal"], position: -1) : nil }
        seasonID = data["season_id"].text
        seasons = (data["allSeason"].values ?? []).compactMap {
            guard let id = $0["id"].text, let name = $0["name"].text else { return nil }
            return RankingSeason(id: id, name: name)
        }
    }
}

extension BusinessAPI {
    func ranking(category: RankingCategory, season: String, page: Int, token: String? = nil) async throws -> RankingPage {
        try RankingPage(data: await request("/v1/points/ranking", method: "POST", form: [
            "type": String(category.rawValue), "season_id": season, "page": String(page), "limit": "10"
        ], token: token), page: page)
    }
}

@Observable @MainActor
final class RankingStore {
    private(set) var players: [RankingPlayer] = []
    private(set) var personal: RankingPlayer?
    private(set) var hasLoaded = false
    private(set) var seasons: [RankingSeason] = []
    private(set) var currentSeasonID: String?
    private(set) var total = 0
    private(set) var isLoading = false
    private(set) var hasMore = false
    private(set) var errorMessage: String?
    private var page = 0
    private var category: RankingCategory = .ocg
    private var season = ""
    private var token: String?
    private var generation = UUID()
    let api: BusinessAPI
    init(api: BusinessAPI = BusinessAPI()) { self.api = api }
    func refresh(category: RankingCategory, season: String, token: String? = nil) async {
        generation = UUID()
        self.category = category; self.season = season; self.token = token
        personal = nil; hasLoaded = false
        players = []; total = 0; page = 0; hasMore = false
        await load(page: 1, generation: generation)
    }
    func loadMore() async {
        guard !isLoading, hasMore else { return }
        await load(page: page + 1, generation: generation)
    }
    private func load(page requestedPage: Int, generation version: UUID) async {
        isLoading = true; errorMessage = nil
        defer { if version == generation { isLoading = false } }
        do {
            let result = try await api.ranking(category: category, season: season, page: requestedPage, token: token)
            try Task.checkCancellation()
            guard version == generation else { return }
            players = requestedPage == 1 ? result.players : players + result.players
            seasons = result.seasons; currentSeasonID = result.seasonID
            if requestedPage == 1 { personal = result.personal }
            hasLoaded = true
            // Pin following pages to the season selected by the server for the first page.
            if season.isEmpty { season = result.seasonID ?? "" }
            total = result.count; page = requestedPage
            hasMore = !result.players.isEmpty && requestedPage * 10 < total
        } catch is CancellationError { }
        catch {
            guard version == generation else { return }
            errorMessage = error is URLError ? "暂时无法加载排名，请检查网络后重试。" : error.localizedDescription
        }
    }
}

struct RankingScreen: View {
    @Environment(AccountStore.self) private var account
    @State private var store = RankingStore(api: BusinessAPI(transport:
        ProcessInfo.processInfo.arguments.contains("--uitesting") ? TestAPITransport() : NetworkTransport()))
    @State private var category: RankingCategory = .ocg
    @State private var season = ""
    var body: some View {
        List {
            Section {
                Picker("榜单分类", selection: $category) {
                    ForEach(RankingCategory.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("ranking.category")
                if !store.seasons.isEmpty {
                    Picker("赛季", selection: Binding(get: {
                        season.isEmpty ? (store.currentSeasonID ?? "") : season
                    }, set: { season = $0 })) {
                        ForEach(store.seasons) { Text($0.name).tag($0.id) }
                    }.accessibilityIdentifier("ranking.season")
                }
            }
            Section("我的排名") {
                HStack {
                    if !account.isLoggedIn {
                        Text("登录后查看个人排名").foregroundStyle(.secondary)
                    } else if let personal = store.personal {
                        RankingPlayerRow(player: personal, nickname: account.profile?.nickname, avatar: account.profile?.avatarURL)
                            .accessibilityIdentifier("ranking.personal.row")
                    } else if store.isLoading && !store.hasLoaded {
                        ProgressView()
                    } else {
                        Text(store.hasLoaded ? "未上榜" : "暂未获取个人排名")
                            .foregroundStyle(.secondary).accessibilityIdentifier("ranking.personal.unranked")
                    }
                }

            }
            Section {
                ForEach(store.players) { player in
                    RankingPlayerRow(player: player)
                        .onAppear { if player.id == store.players.last?.id, store.errorMessage == nil { Task { await store.loadMore() } } }
                }
                if store.isLoading { HStack { Spacer(); ProgressView(); Spacer() } }
                if let error = store.errorMessage {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(error).foregroundStyle(.secondary)
                        Button("重试") { Task { if store.players.isEmpty { await refresh() } else { await store.loadMore() } } }
                    }
                } else if !store.isLoading, store.players.isEmpty {
                    ContentUnavailableView("暂无排名", systemImage: "chart.bar", description: Text("此分类或赛季暂无榜单。"))
                } else if !store.isLoading, !store.hasMore {
                    Text("已展示全部排名").font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                HStack { Text("排名 · 决斗者"); Spacer(); Text("分数") }
            } footer: { Text("共 \(store.total) 位决斗者；并列名次按榜单原顺序展示。") }
        }
        .navigationTitle("排名").navigationBarTitleDisplayMode(.large)
        .task(id: "\(category.rawValue)-\(season)-\(account.sessionVersion)") { await refresh() }
        .refreshable { await refresh() }
    }
    private func refresh() async { await store.refresh(category: category, season: season, token: account.session?.token) }
}

private struct RankingPlayerRow: View {
    let player: RankingPlayer
    var nickname: String? = nil
    var avatar: URL? = nil
    var body: some View {
        HStack(spacing: 12) {
            Text(String(player.rank)).font(.headline.monospacedDigit())
                .foregroundStyle(player.rank <= 3 ? Color.orange : Color.secondary).frame(minWidth: 30)
            AsyncImage(url: player.avatar ?? avatar) { image in image.resizable().scaledToFill() } placeholder: {
                Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
            }.frame(width: 44, height: 44).clipShape(Circle()).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(player.nickname == "未命名决斗者" ? (nickname ?? player.nickname) : player.nickname).font(.headline)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(player.points).font(.headline.monospacedDigit()).fixedSize(horizontal: true, vertical: false)
        }.padding(.vertical, 6).accessibilityElement(children: .combine)
    }
}
