import SwiftUI
import Observation

struct ShopLevel: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    static let catalog = [ShopLevel(id: "", title: "所有"), ShopLevel(id: "1", title: "一星公认店"), ShopLevel(id: "0", title: "公认店"), ShopLevel(id: "-1", title: "零售商")]
    static func merged(_ values: [String: APIValue]) -> [ShopLevel] {
        catalog + values.compactMap { key, value in
            guard !catalog.contains(where: { $0.id == key }), let title = value.text else { return nil }
            return ShopLevel(id: key, title: title)
        }.sorted { $0.id < $1.id }
    }
}
struct ShopQuery: Hashable, Sendable {
    var keywords = ""
    var level = ""
    var city: LocatedCity?
    func form(page: Int) -> [String: String] {
        ["page": String(page), "limit": "10", "keywords": keywords, "public_level": level, "area_code": city?.code ?? ""]
    }
}
struct ShopItem: Identifiable, Sendable {
    let id: String
    let name: String
    let userID: String?
    let address: String?
    let hours: String?
    let level: String?
    init(data: APIValue) throws {
        guard let id = data["id"].text, let name = data["name"].text else { throw APIError.invalidResponse }
        self.id = id; self.name = name; userID = data["userId"].int.flatMap { $0 > 0 ? String($0) : nil }
        address = data["address"].text; hours = data["time"].text; level = data["publicLevel"].text
    }
    var levelName: String { ShopLevel.catalog.first { $0.id == level }?.title ?? "店铺" }
    var mapURL: URL? {
        guard let address else { return nil }
        var components = URLComponents(string: "\(PrivateConfiguration.value("mapsOrigin"))/")!
        components.queryItems = [URLQueryItem(name: "q", value: address)]
        return components.url
    }
}
struct ShopPage: Sendable {
    let items: [ShopItem]
    let count: Int
    let levels: [ShopLevel]
    init(data: APIValue) throws {
        guard let rows = data["shop"].values, let count = data["count"].int, count >= 0 else { throw APIError.invalidResponse }
        items = try rows.map(ShopItem.init); self.count = count
        if case .object(let values) = data["level_list"] {
            levels = ShopLevel.merged(values)
        } else { levels = ShopLevel.catalog }
    }
}
extension BusinessAPI {
    func shops(query: ShopQuery, page: Int) async throws -> ShopPage {
        try ShopPage(data: await request("/v1/shop", method: "POST", form: query.form(page: page)))
    }
}
@Observable @MainActor
final class ShopStore {
    private(set) var items: [ShopItem] = []
    private(set) var levels = ShopLevel.catalog
    private(set) var total = 0
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var hasMore = false
    private(set) var errorMessage: String?
    private var query: ShopQuery?
    private var page = 0
    private var failedPage: Int?
    private var generation = UUID()
    let api: BusinessAPI
    init(api: BusinessAPI) { self.api = api }
    func loadInitial(query: ShopQuery) async {
        if self.query == query, isLoading { return }
        if self.query != query || !hasLoaded { await refresh(query: query) }
    }
    func refresh(query: ShopQuery) async {
        generation = UUID()
        if self.query != query { items = []; total = 0; hasLoaded = false; hasMore = false }
        self.query = query
        await load(page: 1, version: generation)
    }
    func loadMore() async {
        guard hasMore, !isLoading else { return }
        await load(page: page + 1, version: generation)
    }
    func retry() async {
        await load(page: failedPage ?? 1, version: generation)
    }
    private func load(page requestedPage: Int, version: UUID) async {
        guard let query else { return }
        isLoading = true; errorMessage = nil; failedPage = nil
        defer { if generation == version { isLoading = false } }
        do {
            let result = try await api.shops(query: query, page: requestedPage)
            try Task.checkCancellation()
            guard generation == version else { return }
            var ids = Set<String>()
            items = (requestedPage == 1 ? result.items : items + result.items).filter { ids.insert($0.id).inserted }
            levels = result.levels; total = result.count; page = requestedPage; hasLoaded = true
            hasMore = !result.items.isEmpty && requestedPage * 10 < total
        } catch is CancellationError { }
        catch {
            guard generation == version else { return }
            failedPage = requestedPage
            errorMessage = error is URLError ? "暂时无法加载店铺，请检查网络后重试。" : error.localizedDescription
        }
    }
}
struct StoresScreen: View {
    @Environment(AccountStore.self) private var account
    @Environment(LocationPermissionStore.self) private var location
    @State private var store: ShopStore?
    @State private var query = ShopQuery()
    @State private var search = ""
    private var effectiveQuery: ShopQuery { var result = query; result.city = location.selectedRegion; return result }
    var body: some View {
        ActivityBrowseLayout(identity: effectiveQuery, scrollIdentifier: "shops.scroll",
            itemCount: store?.items.count ?? 0, canLoadMore: (store?.hasMore ?? false) && store?.errorMessage == nil,
            isLoading: store?.isLoading ?? false,
            refresh: { await store?.refresh(query: effectiveQuery) }, loadMore: { await store?.loadMore() }) {
                CityLocationBar()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(store?.levels ?? ShopLevel.catalog) { level in
                            Button { query.level = level.id } label: {
                                MatchCategoryPill(kind: MatchKind(id: level.id == "" ? 0 : level.id == "1" ? 21 : level.id == "0" ? 4 : 17, title: level.title), selected: query.level == level.id)
                                    .frame(minHeight: 44).contentShape(Capsule())
                            }.buttonStyle(.plain).accessibilityIdentifier("shops.level.\(level.id.isEmpty ? "all" : level.id)")
                                .accessibilityAddTraits(query.level == level.id ? .isSelected : [])
                        }
                    }.padding(.vertical, 3).padding(.horizontal, 2)
                }.accessibilityIdentifier("shops.types")
        } rows: {
            if let store {
                ForEach(store.items) { shop in
                    NavigationLink { ShopDetailScreen(shop: shop) } label: { ShopRow(shop: shop, showsDisclosure: true) }
                        .buttonStyle(.plain).accessibilityIdentifier("shops.row.\(shop.id)")
                }
                if let error = store.errorMessage {
                    NewsLoadError(message: error) { Task { await store.retry() } }
                } else if store.hasLoaded, store.items.isEmpty {
                    EmptyState(icon: "storefront", title: "暂无店铺", subtitle: "")
                }
                InfiniteScrollFooter(itemCount: store.items.count, canLoadMore: store.hasMore && store.errorMessage == nil, isLoading: store.isLoading) { await store.loadMore() }
            }
        }
        .navigationTitle("店铺").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索店铺名称或地址")
        .stableSearchToolbar()
        .onSubmit(of: .search) { query.keywords = search.trimmingCharacters(in: .whitespacesAndNewlines) }
        .onChange(of: search) { _, value in if value.isEmpty { query.keywords = "" } }
        .task {
            if store == nil { store = ShopStore(api: account.api) }
            location.locate()
            await store?.loadInitial(query: effectiveQuery)
        }
        .task(id: effectiveQuery) { await store?.loadInitial(query: effectiveQuery) }
    }
}

private struct ShopRow: View {
    let shop: ShopItem
    var showsDisclosure = false
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 8) {
                Image(systemName: "storefront.fill").font(.title2).foregroundStyle(Design.accent)
                    .frame(width: 62, height: 62).background(Design.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                CardTypeLabel(kind: MatchKind(id: shop.level == "1" ? 21 : shop.level == "0" ? 4 : 17, title: shop.levelName))
            }.frame(width: 88)
            VStack(alignment: .leading, spacing: 8) {
                Text(shop.name).font(.headline).foregroundStyle(Design.ink)
                if let address = shop.address {
                    Label(address, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(Design.secondary)
                }
                if let hours = shop.hours { Label(hours, systemImage: "clock").font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if showsDisclosure { Image(systemName: "chevron.right").font(.caption).foregroundStyle(Design.secondary) }
        }.padding(17).background(Design.surface, in: RoundedRectangle(cornerRadius: 25))
    }
}
struct ShopDetailScreen: View {
    let shop: ShopItem
    @Environment(AccountStore.self) private var account
    @State private var matches: MatchStore?
    @State private var status: MatchStatus = .registration
    private var matchQuery: MatchQuery { MatchQuery(status: status, shopOwnerID: shop.userID) }
    var body: some View {
        List {
            Section("店铺信息") {
                LabeledContent("类型", value: shop.levelName)
                if let address = shop.address, let url = shop.mapURL {
                    Link(destination: url) { Label(address, systemImage: "map") }.accessibilityIdentifier("shops.detail.map")
                }
                if let hours = shop.hours { Label(hours, systemImage: "clock").textSelection(.enabled) }
            }
            Section("店铺比赛") {
                MatchStatusMenu(status: $status, count: matches?.total ?? 0, identifier: "shops.matches.status")
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
                if shop.userID == nil { Text("店铺暂未提供赛事信息").foregroundStyle(.secondary) }
                else if let matches {
                    ForEach(matches.items) { match in
                        let kind = matches.kinds.first { $0.id == match.typeID }?.title ?? "比赛"
                        NavigationLink { MatchSummaryScreen(match: match, kind: kind) } label: { LiveMatchRow(match: match, kind: kind, showsDisclosure: false) }
                            .buttonStyle(.plain).listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                            .listRowBackground(Color.clear).listRowSeparator(.hidden)
                            .onAppear { if match.id == matches.items.last?.id { Task { await matches.loadMore() } } }
                            .accessibilityIdentifier("shops.match.\(match.id)")
                    }
                    if matches.isLoading { ProgressView() }
                    if let error = matches.errorMessage {
                        Text(error).foregroundStyle(.secondary)
                        Button("重试") { Task { await matches.refresh(query: matchQuery) } }
                    } else if matches.hasLoaded, matches.items.isEmpty { Text("暂无比赛").foregroundStyle(.secondary) }
                } else { ProgressView() }
            }
        }.navigationTitle(shop.name).navigationBarTitleDisplayMode(.inline)
            .task(id: status) {
                guard shop.userID != nil else { return }
                if matches == nil { matches = MatchStore(api: account.api) }
                await matches?.loadInitial(query: matchQuery)
            }
            .refreshable { if shop.userID != nil { await matches?.refresh(query: matchQuery) } }
    }
}
