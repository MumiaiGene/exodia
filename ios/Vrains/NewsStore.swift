import Foundation
import Observation

enum NewsImageURL {
    static let base = URL(string: "\(PrivateConfiguration.value("newsImageOrigin"))/")!
    static func resolve(_ value: String?) -> URL? {
        guard let value, !value.isEmpty, let url = URL(string: value, relativeTo: base)?.absoluteURL,
              url.scheme == "https", url.host != nil else { return nil }
        return url
    }
}

struct NewsArticle: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let author: String?
    let timeDescription: String?
    let views: Int?
    let coverURL: URL?
    init(data: APIValue) throws {
        guard let id = data["id"].text, let title = data["title"].text else { throw APIError.invalidResponse }
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        author = data["author"].text
        timeDescription = data["time_desc"].text
        views = data["view"].int
        coverURL = NewsImageURL.resolve(data["cover"].text)
    }
}

struct NewsBanner: Identifiable, Sendable {
    let id: String
    let title: String
    let imageURL: URL?
    let newsID: String?
    init(data: APIValue, index: Int) {
        title = data["title"].text ?? "精选资讯"
        imageURL = NewsImageURL.resolve(data["image"].text)
        let type = data["url"]["type"].text
        let destinationID = data["url"]["id"].text
        newsID = type == "information" ? destinationID : nil
        id = "\(type ?? "banner")-\(destinationID ?? String(index))-\(index)"
    }
}

struct NewsPage: Sendable {
    let banners: [NewsBanner]
    let articles: [NewsArticle]
    let count: Int
    init(data: APIValue) throws {
        guard let articles = data["news"].values, let count = data["count"].int, count >= 0 else { throw APIError.invalidResponse }
        self.count = count
        self.articles = try articles.map(NewsArticle.init)
        banners = (data["banner"].values ?? []).enumerated().map { NewsBanner(data: $0.element, index: $0.offset) }
    }
}

struct NewsDetail: Sendable {
    let title: String
    let author: String?
    let timeDescription: String?
    let views: Int?
    let html: String
    let coverURL: URL?
    init(data: APIValue) throws {
        guard let title = data["title"].text, data.isObject else { throw APIError.invalidResponse }
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        author = data["author"].text
        timeDescription = data["time_desc"].text
        views = data["view"].int
        html = data["details"].text ?? ""
        coverURL = NewsImageURL.resolve(data["cover"].text)
    }
}

extension BusinessAPI {
    func news(page: Int, limit: Int = 10) async throws -> NewsPage {
        let data = try await request("/v1/news", method: "POST", form: ["page": String(page), "limit": String(limit), "title": ""])
        return try NewsPage(data: data)
    }
    func newsDetail(id: String) async throws -> NewsDetail {
        guard !id.isEmpty, id.allSatisfy({ $0.isASCII && $0.isNumber }) else { throw APIError.invalidResponse }
        let data = try await request("/v1/news/info/\(id)")
        return try NewsDetail(data: data["info"])
    }
}

@Observable @MainActor
final class NewsStore {
    private(set) var articles: [NewsArticle] = []
    private(set) var banners: [NewsBanner] = []
    private(set) var total = 0
    private(set) var page = 0
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var hasMore = false
    private(set) var errorMessage: String?
    let api: BusinessAPI
    init(api: BusinessAPI) { self.api = api }

    func loadInitial() async {
        guard !hasLoaded else { return }
        await refresh()
    }
    func refresh() async { await load(reset: true) }
    func loadMore() async {
        guard hasMore else { return }
        await load(reset: false)
    }
    private func load(reset: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let requestedPage = reset ? 1 : page + 1
        do {
            let response = try await api.news(page: requestedPage)
            try Task.checkCancellation()
            var ids = Set<String>()
            let combined = reset ? response.articles : articles + response.articles
            articles = combined.filter { ids.insert($0.id).inserted }
            if reset { banners = response.banners }
            total = response.count
            page = requestedPage
            hasLoaded = true
            hasMore = !response.articles.isEmpty && requestedPage * 10 < response.count
        } catch is CancellationError { }
        catch {
            if error is URLError { errorMessage = "暂时无法加载动态，请检查网络后重试。" }
            else { errorMessage = error.localizedDescription }
        }
    }
}
