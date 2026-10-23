import Foundation

struct SavedSession: Codable, Sendable, Equatable {
    let token: String
    let userID: String
    let phone: String
}

struct UserProfile: Sendable {
    let nickname: String?
    let avatarURL: URL?
    let displayID: String?
    let signature: String?
    let phone: String?
    let role: String?
    let isReal: Bool?
    let title: String?
    init(data: APIValue) {
        nickname = data["nickName"].text
        if let avatar = data["avatar"].text, let url = URL(string: avatar), url.scheme == "https" { avatarURL = url } else { avatarURL = nil }
        displayID = data["view_id"].text
        signature = data["signature"].text
        phone = data["phone"].text
        role = data["selectRole"].text
        isReal = data["isReal"].flag
        title = data["title"].text
    }
    var roleName: String {
        switch role {
        case "referee": "裁判"
        case "customer": "店家"
        case "player": "选手"
        default: "决斗者"
        }
    }
}

struct PersonalStatistics: Sendable {
    struct Category: Identifiable, Sendable {
        let id: String
        let name: String
        let count: Int?
        let typeID: Int
    }
    let total: Int?
    let categories: [Category]
    init(data: APIValue) {
        total = data["totalNums"].int
        categories = (data["matchTotal"].values ?? []).enumerated().map { entry in
            let row = entry.element
            let name = row["name"].text ?? "赛事"
            let type = row["id"].int ?? MatchKind.catalog.first { $0.title == name }?.id ?? 0
            return Category(id: String(type) + "-" + String(entry.offset), name: name, count: row["num"].int, typeID: type)
        }
    }
    var topCategories: [Category] {
        let order = MatchKind.catalog.map(\.id)
        return Array(categories.filter { ($0.count ?? 0) > 0 }.sorted {
            if $0.count != $1.count { return ($0.count ?? 0) > ($1.count ?? 0) }
            let left = order.firstIndex(of: $0.typeID) ?? Int.max
            let right = order.firstIndex(of: $1.typeID) ?? Int.max
            return left == right ? $0.id < $1.id : left < right
        }.prefix(3))
    }

}

struct PersonalMatch: Identifiable, Sendable {
    let id: String
    let matchID: String
    let name: String
    let address: String?
    let startTime: String?
    let status: String?
    let type: String?
    init(data: APIValue, index: Int) throws {
        guard data.isObject else { throw APIError.invalidResponse }
        guard let key = data["match_id"].text ?? data["id"].text else { throw APIError.invalidResponse }
        matchID = key
        id = key
        name = data["name"].text ?? data["match_name"].text ?? data["basic_info"]["name"].text ?? "我的赛事"
        address = data["address"].text ?? data["address_info"].text ?? data["basic_info"]["address_info"].text
        startTime = data["start_at"].text ?? data["startAt"].text ?? data["start_time"].text ?? data["basic_info"]["start_at"].text
        status = data["bottom_status"].text ?? data["status_name"].text ?? data["status"].text
        type = data["type"].text
    }
}

// Only the mode preference belongs in UserDefaults; credentials stay in Keychain.
enum TokenLogin {
    static let preferenceKey = "advanced.tokenLogin"
    static func normalized(_ input: String) throws -> String {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("bearer ") { value = String(value.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !value.isEmpty, value.lowercased() != "bearer", !value.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            throw APIError.business(0, "请输入有效的 token。")
        }
        return value
    }
    static func userID(in token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload), let value = try? JSONDecoder().decode(APIValue.self, from: data) else { return nil }
        return value["UserId"].text
    }
}
