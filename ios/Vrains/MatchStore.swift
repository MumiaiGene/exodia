import Foundation
import Observation

enum MatchStatus: Int, CaseIterable, Identifiable {
    case registration = 2, ongoing = 3, ended = 8
    var id: Int { rawValue }
    var title: String {
        switch self { case .registration: "可报名"; case .ongoing: "比赛中"; case .ended: "已结束" }
    }
}

struct MatchKind: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    static let all = MatchKind(id: 0, title: "所有")
}

enum MatchEnvironment: Int, CaseIterable, Identifiable, Sendable {
    case ocg = 2, simplifiedChinese = 1
    var id: Int { rawValue }
    var title: String { self == .ocg ? "OCG" : "简体中文" }
}

struct MatchQuery: Hashable, Sendable {
    var status: MatchStatus = .registration
    var typeID: Int = 0
    var city: LocatedCity?
    var environment: MatchEnvironment = .ocg
    var keywords = ""
    var shopOwnerID: String?
    func inRegion(_ city: LocatedCity?) -> MatchQuery {
        var result = self; result.city = city; return result
    }
    func form(page: Int) -> [String: String] {
        ["page": String(page), "limit": "20", "keywords": keywords,
         "type": typeID == 0 ? "" : "[\"\(typeID)\"]", "status": String(status.rawValue),
         "area_code": city?.code ?? "", "city": city?.name ?? "", "condition": shopOwnerID == nil ? "[\"\(environment.rawValue)\"]" : "", "user_id": shopOwnerID ?? "", "player_number_type": "", "match_start_type": "",
         "zone_id": "", "city_id": "", "county_id": ""]
    }
}

struct MatchItem: Identifiable, Sendable {
    let id: String
    let name: String
    let address: String?
    let startsAt: Date?
    let startText: String?
    let typeID: Int?
    let status: String?
    let statusID: Int?
    let isBackup: Bool
    let registered: Int?
    let capacity: Int?
    let isSignedUp: Bool
    init(data: APIValue) throws {
        guard let id = data["id"].text, let name = data["name"].text else { throw APIError.invalidResponse }
        self.id = id; self.name = name
        address = data["address"].text
        startText = data["startAt"].text
        if let timestamp = data["startAtTimestamp"].int {
            startsAt = Date(timeIntervalSince1970: Double(timestamp))
        } else if let text = startText {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            startsAt = formatter.date(from: text)
        } else { startsAt = nil }
        typeID = data["type"].int
        statusID = data["statusId"].int
        isBackup = data["isBackup"].flag ?? false
        status = data["bottom"]["title"]["text"].text ?? data["statusId"].int.flatMap { MatchStatus(rawValue: $0)?.title }
        registered = data["bottom"]["title"]["alreadySignedUp"].int
        capacity = data["bottom"]["title"]["signUpTotal"].int
        isSignedUp = data["isSignup"].flag == true || data["role"].text == "player" || status == "已报名"
    }

    var timeText: String? {
        if let startsAt { let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.timeZone = TimeZone(identifier: "Asia/Shanghai"); formatter.dateFormat = "HH:mm"; return formatter.string(from: startsAt) }
        return startText?.split(separator: " ").last.map(String.init)
    }
}

struct MatchPage: Sendable {
    let items: [MatchItem]
    let count: Int
    let kinds: [MatchKind]
    init(data: APIValue) throws {
        guard let count = data["count"].int, count >= 0 else { throw APIError.invalidResponse }
        let values: [APIValue]
        if let rows = data["matchs"].values { values = rows }
        else if count == 0, data["matchs"] == .null { values = [] }
        else { throw APIError.invalidResponse }
        items = try values.map(MatchItem.init)
        self.count = count
        if case .object(let types) = data["matchTypeView"] {
            let supplied: [MatchKind] = types.compactMap { key, value in
                guard let id = Int(key), id != 0, let title = value.text else { return nil }
                return MatchKind(id: id, title: title)
            }
            kinds = MatchKind.merged(supplied)
        } else { kinds = MatchKind.catalog }
    }
}

extension BusinessAPI {
    func matchPage(query: MatchQuery, page: Int) async throws -> MatchPage {
        // The mini-program lists matches publicly; no account token is required.
        try MatchPage(data: await request("/v1/match", method: "POST", form: query.form(page: page)))
    }
}

@Observable @MainActor
final class MatchStore {
    private(set) var items: [MatchItem] = []
    private(set) var kinds: [MatchKind] = MatchKind.catalog
    private(set) var total = 0
    private(set) var page = 0
    private(set) var isLoading = false
    private(set) var hasMore = false
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    private(set) var loadedQuery: MatchQuery?
    let api: BusinessAPI
    private var generation = UUID()
    init(api: BusinessAPI) { self.api = api }

    func loadInitial(query: MatchQuery) async {
        if loadedQuery != query || !hasLoaded { await refresh(query: query) }
    }
    func refresh(query: MatchQuery) async {
        let version = UUID()
        generation = version
        if loadedQuery != query { items = []; total = 0; hasMore = false; hasLoaded = false }
        loadedQuery = query
        await load(query: query, page: 1, version: version)
    }
    func loadMore() async {
        guard !isLoading, hasMore, let query = loadedQuery else { return }
        await load(query: query, page: page + 1, version: generation)
    }
    private func load(query: MatchQuery, page requestedPage: Int, version: UUID) async {
        isLoading = true; errorMessage = nil
        defer { if generation == version { isLoading = false } }
        do {
            let response = try await api.matchPage(query: query, page: requestedPage)
            try Task.checkCancellation()
            guard generation == version else { return }
            var ids = Set<String>()
            items = (requestedPage == 1 ? response.items : items + response.items).filter { ids.insert($0.id).inserted }
            kinds = response.kinds
            total = response.count; page = requestedPage; hasLoaded = true
            hasMore = !response.items.isEmpty && requestedPage * 20 < response.count
        } catch is CancellationError { }
        catch {
            guard generation == version else { return }
            errorMessage = error is URLError ? "暂时无法加载比赛，请检查网络后重试。" : error.localizedDescription
        }
    }
}

struct ScrollSearchState {
    private var lastOffset: CGFloat? = 0
    private var distance: CGFloat = 0
    private(set) var isVisible = false
    mutating func setVisible(_ visible: Bool) { isVisible = visible; lastOffset = 0; distance = 0 }
    mutating func endGesture() { lastOffset = 0; distance = 0 }
    mutating func update(offset: CGFloat) -> Bool {
        guard let lastOffset else { self.lastOffset = offset; return isVisible }
        let change = offset - lastOffset
        self.lastOffset = offset
        if change * distance < 0 { distance = 0 }
        distance += change
        // Content offset increases when the finger swipes upwards.
        if distance > 14 { isVisible = false; distance = 0 }
        if distance < -14 { isVisible = true; distance = 0 }
        return isVisible
    }
}


@Observable @MainActor
final class MatchBrowserStore {
    let ocg: MatchStore
    let simplifiedChinese: MatchStore
    private var context: MatchQuery?
    private var loadingContext: MatchQuery?
    private var refreshVersion = UUID()
    init(api: BusinessAPI) {
        ocg = MatchStore(api: api); simplifiedChinese = MatchStore(api: api)
    }
    func store(for environment: MatchEnvironment) -> MatchStore {
        environment == .ocg ? ocg : simplifiedChinese
    }
    static func fullQuery(_ query: MatchQuery) -> MatchQuery {
        var result = query; result.typeID = 0; result.environment = .ocg; return result
    }
    func loadInitial(query: MatchQuery) async {
        let full = Self.fullQuery(query)
        if context == full, loadingContext == full || (ocg.hasLoaded && simplifiedChinese.hasLoaded) { return }
        await refresh(query: full)
    }
    func refresh(query: MatchQuery) async {
        let full = Self.fullQuery(query)
        let version = UUID(); refreshVersion = version
        context = full; loadingContext = full
        defer { if refreshVersion == version { loadingContext = nil } }
        var chinese = full; chinese.environment = .simplifiedChinese
        async let first: Void = ocg.refresh(query: full)
        async let second: Void = simplifiedChinese.refresh(query: chinese)
        _ = await (first, second)
    }
}
