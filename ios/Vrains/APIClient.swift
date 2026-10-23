import Foundation
import CommonCrypto

enum APIError: LocalizedError {
    case business(Int, String), http(Int), invalidResponse, sessionExpired, invalidPhone, invalidCode, waitToResend
    var errorDescription: String? {
        switch self {
        case .business(_, let message): message.isEmpty ? "服务暂时不可用，请稍后重试。" : message
        case .http(let status): "服务请求失败（\(status)），请稍后重试。"
        case .invalidResponse: "服务器返回了无法识别的数据，请稍后重试。"
        case .sessionExpired: "登录已失效，请重新登录。"
        case .invalidPhone: "请输入正确的 11 位手机号。"
        case .invalidCode: "请输入短信中的数字验证码。"
        case .waitToResend: "请等待倒计时结束后再获取验证码。"
        }
    }
    var requiresLogin: Bool {
        switch self {
        case .sessionExpired: true
        case .business(let code, _): code == 10313 || code == 10314
        case .http(let status): status == 401
        default: false
        }
    }
}

enum APIValue: Codable, Sendable, Equatable {
    case object([String: APIValue]), array([APIValue]), string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(Double.self) { self = .number(value) }
        else if let value = try? c.decode(String.self) { self = .string(value) }
        else if let value = try? c.decode([String: APIValue].self) { self = .object(value) }
        else { self = .array(try c.decode([APIValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let value): try c.encode(value)
        case .array(let value): try c.encode(value)
        case .string(let value): try c.encode(value)
        case .number(let value): try c.encode(value)
        case .bool(let value): try c.encode(value)
        case .null: try c.encodeNil()
        }
    }
    subscript(_ key: String) -> APIValue {
        if case .object(let object) = self { object[key] ?? .null } else { .null }
    }
    var text: String? {
        switch self {
        case .string(let value): value.isEmpty ? nil : value
        case .number(let value): value.isFinite ? String(format: "%.0f", value) : nil
        default: nil
        }
    }
    var int: Int? {
        switch self {
        case .number(let value): Int(exactly: value)
        case .string(let value): Int(value)
        default: nil
        }
    }
    var flag: Bool? {
        switch self {
        case .bool(let value): value
        case .number(let value): value == 1
        case .string(let value): ["1", "true"].contains(value.lowercased())
        default: nil
        }
    }
    var values: [APIValue]? { if case .array(let values) = self { values } else { nil } }
    var isObject: Bool { if case .object = self { true } else { false } }
}

protocol APITransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

final class NetworkTransport: APITransport, @unchecked Sendable {
    private let session: URLSession
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration)
    }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        return (data, response)
    }
}

enum RequestSignature {
    static func make(timestamp: Int64) throws -> String {
        let message = Array("CNMD_\(timestamp)".utf8)
        let key = Array(PrivateConfiguration.value("businessSignatureKey").utf8)
        let iv = Array(PrivateConfiguration.value("businessSignatureIV").utf8)
        var output = [UInt8](repeating: 0, count: message.count + kCCBlockSize3DES)
        var written = 0
        let capacity = output.count
        let status = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                message.withUnsafeBytes { inputBytes in
                    output.withUnsafeMutableBytes { outputBytes in
                        CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithm3DES), CCOptions(kCCOptionPKCS7Padding),
                                keyBytes.baseAddress, kCCKeySize3DES, ivBytes.baseAddress,
                                inputBytes.baseAddress, message.count, outputBytes.baseAddress, capacity, &written)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw APIError.invalidResponse }
        return Data(output.prefix(written)).base64EncodedString()
    }
}

actor SignatureClock {
    private let transport: any APITransport
    private var offset: TimeInterval = 0
    private var checkedAt = Date.distantPast
    init(transport: any APITransport) { self.transport = transport }
    func timestamp() async -> Int64 {
        if Date.now.timeIntervalSince(checkedAt) > 300 {
            checkedAt = .now
            var request = URLRequest(url: URL(string: "\(PrivateConfiguration.value("clockOrigin"))/api/ct.do")!)
            request.timeoutInterval = 3
            let started = Date.now
            if let (data, response) = try? await transport.data(for: request), response.statusCode == 200,
               let value = try? JSONDecoder().decode(APIValue.self, from: data),
               let milliseconds = value["currentTime"].int {
                let midpoint = started.timeIntervalSince1970 + Date.now.timeIntervalSince(started) / 2
                offset = Double(milliseconds) / 1000 - midpoint
            }
        }
        return Int64(floor(Date.now.timeIntervalSince1970 + offset))
    }
}

struct BusinessAPI: Sendable {
    static let baseURL = URL(string: "\(PrivateConfiguration.value("businessOrigin"))")!
    let transport: any APITransport
    private let clock: SignatureClock
    init(transport: any APITransport = NetworkTransport()) {
        self.transport = transport
        clock = SignatureClock(transport: transport)
    }
    func request(_ path: String, method: String = "GET", form: [String: String] = [:], token: String? = nil, includeEnvelope: Bool = false) async throws -> APIValue {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if method == "GET" || method == "DELETE", !form.isEmpty {
            components.queryItems = form.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(PrivateConfiguration.value("businessUserAgent"), forHTTPHeaderField: "User-Agent")
        request.setValue(PrivateConfiguration.value("businessReferer"), forHTTPHeaderField: "Referer")
        request.setValue(try RequestSignature.make(timestamp: await clock.timestamp()), forHTTPHeaderField: "signature")
        if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if method != "GET" && method != "DELETE" { request.httpBody = Self.encodeForm(form) }
        // SMS and login are intentionally sent once. There is no retry loop.
        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else { throw APIError.http(response.statusCode) }
        guard let envelope = try? JSONDecoder().decode(APIValue.self, from: data), let code = envelope["code"].int else { throw APIError.invalidResponse }
        guard code == 200 else { throw APIError.business(code, envelope["msg"].text ?? "") }
        return includeEnvelope ? envelope : envelope["data"]
    }
    static func encodeForm(_ form: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return Data(form.sorted(by: { $0.key < $1.key }).map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&").utf8)
    }
    func login(phone: String, code: String) async throws -> SavedSession {
        let data = try await request("/v1/user/login", method: "POST", form: ["type": "tel", "phone": phone, "code": code])
        guard let token = data["token"].text, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let id = data["id"].text else { throw APIError.invalidResponse }
        return SavedSession(token: token, userID: id, phone: phone)
    }
    func user(token: String) async throws -> UserProfile {
        let data = try await request("/v1/user/info", token: token)
        guard data["user"].isObject else { throw APIError.invalidResponse }
        return UserProfile(data: data["user"])
    }
    func center(token: String) async throws -> PersonalStatistics {
        let data = try await request("/v1/personal/center", token: token)
        guard data.isObject else { throw APIError.invalidResponse }
        return PersonalStatistics(data: data)
    }
    func matches(token: String) async throws -> [PersonalMatch] {
        let data = try await request("/v1/new/personal/match", token: token)
        guard let values = data["res"].values else { throw APIError.invalidResponse }
        return try values.enumerated().map { try PersonalMatch(data: $0.element, index: $0.offset) }
    }
    func unread(token: String) async throws -> Int {
        let data = try await request("/v1/notice/center/unread", token: token)
        guard let count = data["count"].int, count >= 0 else { throw APIError.invalidResponse }
        return count
    }
}

// Matches pkg/duel/client.go findTrueCode: encrypt the second decoded field again.
struct LegacyMatchCaptcha: Sendable {
    let fields: [String]
    init(encrypted: String) throws {
        guard let input = Data(base64Encoded:encrypted), !input.isEmpty else { throw APIError.invalidResponse }
        let decoded = try Self.crypt(input,operation:CCOperation(kCCDecrypt))
        guard let text = String(data:decoded,encoding:.utf8) else { throw APIError.invalidResponse }
        let fields = text.components(separatedBy:",")
        guard fields.count == 3, fields.allSatisfy({ !$0.isEmpty }) else { throw APIError.invalidResponse }
        self.fields = fields
    }
    func trueCode() throws -> String {
        try Self.crypt(Data(fields[1].utf8),operation:CCOperation(kCCEncrypt)).base64EncodedString()
    }
    private static func crypt(_ input: Data, operation: CCOperation) throws -> Data {
        let key = Array(PrivateConfiguration.value("captchaKey").utf8), iv = Array(PrivateConfiguration.value("captchaIV").utf8)
        var output = [UInt8](repeating:0,count:input.count+kCCBlockSize3DES)
        let capacity = output.count; var written = 0
        let status = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                input.withUnsafeBytes { inputBytes in
                    output.withUnsafeMutableBytes { outputBytes in
                        CCCrypt(operation,CCAlgorithm(kCCAlgorithm3DES),CCOptions(kCCOptionPKCS7Padding),keyBytes.baseAddress,kCCKeySize3DES,ivBytes.baseAddress,inputBytes.baseAddress,input.count,outputBytes.baseAddress,capacity,&written)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw APIError.invalidResponse }
        return Data(output.prefix(written))
    }
}
extension BusinessAPI {
    func matchCaptcha(token: String) async throws -> LegacyMatchCaptcha {
        let data = try await request("/v1/captcha",token:token)
        guard let encrypted = data["res"].text else { throw APIError.invalidResponse }
        return try LegacyMatchCaptcha(encrypted:encrypted)
    }
}


// Values are supplied locally at build time; never commit PrivateConfiguration.json.
enum PrivateConfiguration {
    private static let values: [String:String] = {
        guard let url = Bundle.main.url(forResource:"PrivateConfiguration",withExtension:"json"),
              let data = try? Data(contentsOf:url),
              let values = try? JSONDecoder().decode([String:String].self,from:data) else {
            fatalError("Missing private build configuration")
        }
        return values
    }()
    static func value(_ key:String) -> String {
        guard let value = values[key], !value.isEmpty else { fatalError("Missing private configuration field: \(key)") }
        return value
    }
}
