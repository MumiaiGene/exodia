import Foundation
import Security

protocol SessionStorage: Sendable {
    func load() throws -> SavedSession?
    func save(_ session: SavedSession) throws
    func clear() throws
}

struct KeychainSessionStorage: SessionStorage {
    let service: String
    init(service: String = "com.localdevelopment.Exodia.account") { self.service = service }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: "business-session"]
    }
    func load() throws -> SavedSession? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw SessionStorageError(status: status) }
        guard let session = try? JSONDecoder().decode(SavedSession.self, from: data), !session.token.isEmpty else { throw APIError.invalidResponse }
        return session
    }
    func save(_ session: SavedSession) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(session),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw SessionStorageError(status: update) }
        var item = query
        item.merge(attributes) { _, new in new }
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw SessionStorageError(status: status) }
    }
    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SessionStorageError(status: status) }
    }
}

struct SessionStorageError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? {
        switch status {
        case errSecMissingEntitlement: "此 App 的签名缺少安全存储权限（\(status)），请安装正确签名的版本。"
        case errSecInteractionNotAllowed: "设备安全存储暂不可用（\(status)），请解锁设备后重试。"
        default: "无法访问本机安全存储（\(status)），请稍后重试。"
        }
    }
}
