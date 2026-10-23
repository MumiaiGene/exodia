import Foundation
import Observation

@Observable @MainActor
final class AccountStore {
    private(set) var session: SavedSession?
    private(set) var profile: UserProfile?
    private(set) var statistics: PersonalStatistics?
    private(set) var matches: [PersonalMatch] = []
    private(set) var unreadCount: Int?
    private(set) var isLoading = false
    private(set) var resendAt = Date.distantPast
    private(set) var sentPhone: String?
    private(set) var sessionVersion = UUID()
    private(set) var sectionErrors: [String: String] = [:]
    var sessionMessage: String?
    let api: BusinessAPI
    private let storage: any SessionStorage
    private var lastRefresh = Date.distantPast
    private var isSending = false
    var isLoggedIn: Bool { session != nil }
    var displayName: String { profile?.nickname ?? (isLoggedIn ? "决斗者" : "你的热爱，值得收藏。") }
    var maskedPhone: String {
        guard let phone = profile?.phone ?? session?.phone, phone.count == 11 else { return "手机号已绑定" }
        return "\(phone.prefix(3)) ···· \(phone.suffix(4))"
    }
    init(api: BusinessAPI = BusinessAPI(), storage: any SessionStorage = KeychainSessionStorage()) {
        self.api = api
        self.storage = storage
        do { session = try storage.load() }
        catch { sessionMessage = error.localizedDescription }
    }
    static func validPhone(_ phone: String) -> Bool {
        phone.range(of: "^1[3-9][0-9]{9}$", options: .regularExpression) != nil
    }
    func sendCode(phone: String) async throws {
        guard Self.validPhone(phone) else { throw APIError.invalidPhone }
        guard !isSending, Date.now >= resendAt else { throw APIError.waitToResend }
        isSending = true
        // Reserve the interval before dispatch; an ambiguous network failure must not cause an automatic second SMS.
        resendAt = .now.addingTimeInterval(60)
        defer { isSending = false }
        _ = try await api.request("/v1/msg/send", method: "POST", form: ["phone": phone])
        sentPhone = phone
    }
    func signIn(phone: String, code: String) async throws {
        guard Self.validPhone(phone) else { throw APIError.invalidPhone }
        guard code.range(of: "^[0-9]+$", options: .regularExpression) != nil else { throw APIError.invalidCode }
        let version = sessionVersion
        let newSession = try await api.login(phone: phone, code: code)
        try Task.checkCancellation()
        guard version == sessionVersion else { throw CancellationError() }
        // Persist successfully before exposing authenticated UI. Never write token to UserDefaults or logs.
        try storage.save(newSession)
        clearProfile()
        session = newSession
        sessionMessage = nil
        sessionVersion = UUID()
    }
    func importToken(_ input: String) async throws {
        let token = try TokenLogin.normalized(input)
        let version = sessionVersion
        let data = try await api.request("/v1/user/info", token: token)
        guard data["user"].isObject else { throw APIError.invalidResponse }
        let user = UserProfile(data: data["user"])
        // JWT payload is used only for identity metadata after server validation.
        guard let id = data["user"]["id"].text ?? data["id"].text ?? TokenLogin.userID(in: token) else { throw APIError.invalidResponse }
        try Task.checkCancellation()
        guard version == sessionVersion else { throw CancellationError() }
        let imported = SavedSession(token: token, userID: id, phone: user.phone ?? "")
        try storage.save(imported)
        clearProfile(); session = imported; profile = user; sessionMessage = nil
        sessionVersion = UUID()
    }
    func signOut() throws {
        try storage.clear()
        session = nil
        sessionVersion = UUID()
        clearProfile()
        sessionMessage = nil
    }
    func refresh(force: Bool = true) async {
        guard let session, !isLoading, force || Date.now.timeIntervalSince(lastRefresh) > 60 else { return }
        let version = sessionVersion
        isLoading = true
        defer { if version == sessionVersion { isLoading = false } }
        async let user = attempt { try await self.api.user(token: session.token) }
        async let center = attempt { try await self.api.center(token: session.token) }
        async let events = attempt { try await self.api.matches(token: session.token) }
        async let unread = attempt { try await self.api.unread(token: session.token) }
        let results = await (user, center, events, unread)
        guard version == sessionVersion, !Task.isCancelled else { return }
        let errors = [results.0.failure, results.1.failure, results.2.failure, results.3.failure].compactMap { $0 }
        if errors.contains(where: { ($0 as? APIError)?.requiresLogin == true }) {
            do { try signOut(); sessionMessage = APIError.sessionExpired.localizedDescription }
            catch { sessionMessage = error.localizedDescription }
            return
        }
        sectionErrors = [:]
        apply(results.0, section: "个人资料") { profile = $0 }
        apply(results.1, section: "赛事统计") { statistics = $0 }
        apply(results.2, section: "我的赛事") { matches = $0 }
        apply(results.3, section: "消息") { unreadCount = $0 }
        lastRefresh = .now
    }
    func fetchAuthenticated(_ path: String, form: [String: String] = [:], method: String = "GET", includeEnvelope: Bool = false) async throws -> APIValue {
        guard let session else { throw APIError.sessionExpired }
        let version = sessionVersion
        do {
            let data = try await api.request(path, method: method, form: form, token: session.token, includeEnvelope: includeEnvelope)
            guard version == sessionVersion else { throw CancellationError() }
            return data
        } catch {
            if version == sessionVersion, let apiError = error as? APIError, apiError.requiresLogin {
                try signOut()
                sessionMessage = apiError.localizedDescription
            }
            throw error
        }
    }
    private func clearProfile() {
        profile = nil; statistics = nil; matches = []; unreadCount = nil
        sectionErrors = [:]; isLoading = false; lastRefresh = .distantPast
    }
    private func apply<Value>(_ result: Result<Value, Error>, section: String, success: (Value) -> Void) {
        switch result {
        case .success(let value): success(value)
        case .failure(let error): sectionErrors[section] = Self.message(for: error)
        }
    }
    static func message(for error: Error) -> String {
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost: return "网络连接不可用，登录状态已保留。"
            case .timedOut: return "请求超时，请稍后重试。"
            default: return "暂时无法连接服务，请稍后重试。"
            }
        }
        return error.localizedDescription
    }
}

private func attempt<Value: Sendable>(_ operation: @Sendable () async throws -> Value) async -> Result<Value, Error> {
    do { return .success(try await operation()) } catch { return .failure(error) }
}
private extension Result {
    var failure: Failure? { if case .failure(let error) = self { error } else { nil } }
}
