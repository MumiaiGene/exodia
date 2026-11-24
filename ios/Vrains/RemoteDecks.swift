import Foundation

enum RemoteDeckError: LocalizedError {
    case missingPhone, missingCards, unsupportedFormat, unsupportedCard(Int64), capacity, publicMainCount, ambiguousCreate
    case editBlocked(String)

    var errorDescription: String? {
        switch self {
        case .missingPhone: "一起来决斗账号需要绑定手机号才能读取牌组。"
        case .missingCards: "请先在本地卡组中录入逐张卡牌。"
        case .unsupportedFormat: "一起来决斗支持 OCG 和简体中文环境。请先切换本地卡组的禁限卡表。"
        case .unsupportedCard(let cid): "无法识别卡牌（CID \(cid)）的分组，请更新卡池后重试。"
        case .capacity: "主卡组最多 60 张，额外卡组和副卡组各最多 15 张。"
        case .publicMainCount: "公开牌组的主卡组需要有 40–60 张卡牌。"
        case .ambiguousCreate: "新建请求的结果尚未确认。请检查一起来决斗中是否已出现该牌组，再重试。"
        case .editBlocked(let message): message.isEmpty ? "该牌组关联了赛事，请先在一起来决斗处理赛事关联。" : message
        }
    }
}

struct RemoteDeckSummary: Identifiable, Sendable {
    static let simplified = "简体字中文环境（大师规则）"
    static let ocg = "OCG环境（大师规则）"

    let id: String
    let entity: [String: APIValue]
    let name: String
    var status: String { entity["status"]?.text ?? "" }
    var format: CardFormat { entity["deckType"]?.text == Self.simplified ? .simplified : .ocg }
    var updatedAt: Date? {
        guard let text=entity["updateTime"]?.text else { return nil }
        let iso=ISO8601DateFormatter()
        if let date=iso.date(from:text) { return date }
        iso.formatOptions.insert(.withFractionalSeconds)
        if let date=iso.date(from:text) { return date }
        let formatter=DateFormatter()
        formatter.locale=Locale(identifier:"en_US_POSIX")
        formatter.timeZone=TimeZone(identifier:"Asia/Shanghai")
        formatter.dateFormat="yyyy-MM-dd HH:mm:ss"
        return formatter.date(from:text)
    }

    init(_ value: APIValue) throws {
        guard case .object(let entity) = value, let id = value["id"].text, !id.isEmpty else {
            throw APIError.invalidResponse
        }
        self.entity = entity
        self.id = id
        name = value["deckName"].text ?? "未命名牌组"
    }
}

struct RemoteDeckCard: Equatable, Sendable {
    let cardID: APIValue
    let language: String
    let type: Int
    var quantity: Int

    var cid: Int64? { cardID.text.flatMap(Int64.init) }
    var zone: DeckZone { type == 0 ? .side : type == 4 ? .extra : .main }
    var payload: APIValue {
        .object(["cardId": cardID, "lang": .string(language), "windoCardType": .number(Double(type)),
                 "number": .number(Double(quantity))])
    }
}

struct RemoteDeckDetail: Sendable {
    let summary: RemoteDeckSummary
    let cards: [RemoteDeckCard]

    init(summary: RemoteDeckSummary, data: APIValue) throws {
        guard let groups = data["data"]["list"].values else { throw APIError.invalidResponse }
        self.summary = summary
        cards = try groups.flatMap { group -> [RemoteDeckCard] in
            guard let type = group["type"].int, (0...4).contains(type), let rows = group["list"].values else {
                throw APIError.invalidResponse
            }
            return try rows.map { row in
                guard let id = row["cardId"].text.flatMap(Int64.init), id > 0,
                      let quantity = row["number"].int, (1...90).contains(quantity),
                      let language = row["lang"].text else { throw APIError.invalidResponse }
                return RemoteDeckCard(cardID: row["cardId"], language: language, type: type, quantity: quantity)
            }
        }
    }

    func deckSnapshot() throws -> Deck {
        var deck = Deck.draft(name: summary.name)
        deck.banlist = summary.format.rawValue
        var state = DeckEditState(deck)
        state.description = summary.entity["note"]?.text ?? ""
        for card in cards {
            guard let cid = card.cid, state[card.zone].count <= 90 - card.quantity else { throw APIError.invalidResponse }
            state[card.zone].append(contentsOf: repeatElement(DeckCard(cid: cid), count: card.quantity))
        }
        deck = state.applying(to: deck)
        deck.cards = state.all.count
        deck.id = summary.id
        deck.isMine = false
        deck.updatedAt = summary.updatedAt
        return deck
    }

    func updatedEntity(from deck: Deck) -> [String: APIValue] {
        var entity = summary.entity
        entity["deckName"] = .string(deck.name)
        entity["note"] = .string(deck.deckDescription ?? "")
        if let format = deck.banlist.flatMap(CardFormat.init(rawValue:)),
           entity["deckType"]?.text == nil || format != summary.format {
            entity["deckType"] = .string(format == .simplified ? RemoteDeckSummary.simplified : RemoteDeckSummary.ocg)
        }
        return entity
    }
}

struct RemoteDeckAPI: Sendable {
    let transport: any APITransport

    private static let origin = URL(string: "https://yugiohcarddbapi.windoent.com")!
    private static let deckPath = "/mini/deckGroup/deck/"

    func cardToken(phone: String) async throws -> String {
        let data = try await request("/user/user/getToken", form: ["phone": phone])
        guard let token = data["token"].text else { throw APIError.invalidResponse }
        return token
    }

    func list(token: String) async throws -> [RemoteDeckSummary] {
        let data = try await request(Self.deckPath + "decklist", token: token)
        guard let list = data["list"].values else { throw APIError.invalidResponse }
        return try list.map(RemoteDeckSummary.init)
    }

    func detail(_ summary: RemoteDeckSummary, token: String) async throws -> RemoteDeckDetail {
        let data = try await request(Self.deckPath + "getDeckBatchCard", query: ["deckId": summary.id, "selectType": "0"],
                                     token: token, jsonContentType: true)
        return try RemoteDeckDetail(summary: summary, data: data)
    }

    func createDraft(name: String, token: String) async throws {
        _ = try await request(Self.deckPath + "save", token: token,
                              json: .object(["status": .string("非公开"), "deckName": .string(name)]),
                              requireCode: true)
    }
    func delete(id: String, token: String) async throws {
        _ = try await request(Self.deckPath + "deleteId/" + id, token: token, requireCode: true)
    }

    func checkEdit(id: String, token: String) async throws {
        do {
            _ = try await request("/mini/other/v1/match/edit/deck/check", query: ["deckId": id], token: token,
                                  jsonContentType: true, requireCode: true)
        } catch APIError.business(let code, let message) where !(10108...10112).contains(code) {
            throw RemoteDeckError.editBlocked(message)
        }
    }

    func save(entity: [String: APIValue], cards: [RemoteDeckCard], token: String) async throws {
        _ = try await request(Self.deckPath + "deckAddBatchCard", token: token,
                              json: .object(["deckEntity": .object(entity), "list": .array(cards.map(\.payload))]),
                              requireCode: true)
    }

    private func request(_ path: String, query: [String: String] = [:], token: String? = nil,
                         form: [String: String]? = nil, json: APIValue? = nil,
                         jsonContentType: Bool = false, requireCode: Bool = false) async throws -> APIValue {
        var components = URLComponents(url: Self.origin.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = (form != nil || json != nil) ? "POST" : "GET"
        request.setValue(json != nil || jsonContentType ? "application/json;charset=utf-8" : "application/x-www-form-urlencoded",
                         forHTTPHeaderField: "Content-Type")
        if let token { request.setValue(token, forHTTPHeaderField: "token") }
        if let form { request.httpBody = BusinessAPI.encodeForm(form) }
        if let json { request.httpBody = try JSONEncoder().encode(json) }
        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else { throw APIError.http(response.statusCode) }
        let value = try JSONDecoder().decode(APIValue.self, from: data)
        guard value.isObject else { throw APIError.invalidResponse }
        if let code = value["code"].int {
            guard code == 0 || (!requireCode && code == 200) else {
                throw APIError.business(code, value["msg"].text ?? "")
            }
        } else if requireCode {
            throw APIError.invalidResponse
        }
        return value
    }
}

@MainActor
struct RemoteDeckSession {
    private let api: RemoteDeckAPI
    let userID: String
    private let account: AccountStore
    private let version: UUID
    private let token: String

    init(account: AccountStore) async throws {
        guard let session = account.session else { throw APIError.sessionExpired }
        let version = account.sessionVersion
        let phone: String
        if AccountStore.validPhone(session.phone) {
            phone = session.phone
        } else {
            let data = try await account.fetchAuthenticated("/v1/user/info")
            guard let boundPhone = data["user"]["phone"].text, AccountStore.validPhone(boundPhone) else {
                throw RemoteDeckError.missingPhone
            }
            phone = boundPhone
        }
        try Task.checkCancellation()
        guard version == account.sessionVersion else { throw CancellationError() }
        let api = RemoteDeckAPI(transport: account.api.transport)
        let token = try await api.cardToken(phone: phone)
        self.account = account
        self.version = version
        self.api = api
        self.userID = session.userID
        self.token = token
        try checkSession()
    }

    func list() async throws -> [RemoteDeckSummary] {
        try await perform { try await api.list(token: token) }
    }

    func detail(_ summary: RemoteDeckSummary) async throws -> RemoteDeckDetail {
        try await perform { try await api.detail(summary, token: token) }
    }

    func createDraft(name: String) async throws {
        try await perform { try await api.createDraft(name: name, token: token) }
    }
    func delete(id: String) async throws {
        let owned=try await list()
        guard owned.contains(where:{$0.id==id}) else { return }
        try await perform { try await api.checkEdit(id:id,token:token) }
        try await perform { try await api.delete(id:id,token:token) }
        let remaining=try await list()
        guard !remaining.contains(where:{$0.id==id}) else {
            throw RemoteDeckError.editBlocked("服务端尚未确认删除，请刷新后核对。")
        }
    }

    func save(deck: Deck, replacing detail: RemoteDeckDetail, cards: [RemoteDeckCard]) async throws {
        if detail.summary.status == "公开", !(40...60).contains(deck.mainCards.count) {
            throw RemoteDeckError.publicMainCount
        }
        try await perform { try await api.checkEdit(id: detail.summary.id, token: token) }
        try await perform { try await api.save(entity: detail.updatedEntity(from: deck), cards: cards, token: token) }
    }

    private func perform<Value>(_ request: () async throws -> Value) async throws -> Value {
        try checkSession()
        let result = try await request()
        try checkSession()
        return result
    }

    private func checkSession() throws {
        try Task.checkCancellation()
        guard version == account.sessionVersion else { throw CancellationError() }
    }
}

extension RemoteDeckCard {
    static func payload(for deck: Deck, format: CardFormat, keeping original: [RemoteDeckCard],
                        database: CardDatabase) async throws -> [RemoteDeckCard] {
        guard format != .tcg else { throw RemoteDeckError.unsupportedFormat }
        guard deck.mainCardArtworks != nil || deck.mainCardCIDs != nil || deck.cards == 0 else {
            throw RemoteDeckError.missingCards
        }
        let state = DeckEditState(deck)
        var result: [RemoteDeckCard] = []
        for zone in DeckZone.allCases {
            let cards = state[zone]
            guard cards.count <= zone.capacity else { throw RemoteDeckError.capacity }
            let quantities = Dictionary(grouping: cards, by: \.cid).mapValues(\.count)
            var processed = Set<Int64>()
            for card in cards where processed.insert(card.cid).inserted {
                var remaining = quantities[card.cid, default: 0]
                for var row in original where row.cid == card.cid && row.zone == zone && remaining > 0 {
                    row.quantity = min(remaining, row.quantity)
                    remaining -= row.quantity
                    result.append(row)
                }
                guard remaining > 0 else { continue }
                let type: Int
                switch zone {
                case .extra: type = 4
                case .side: type = 0
                case .main:
                    let info = try await database.details(cid: card.cid).card
                    if info.isMonster { type = 1 }
                    else if info.isTrap { type = 3 }
                    else if (info.typeBits ?? 0) & 2 != 0 || info.typeText.hasPrefix("[魔法") { type = 2 }
                    else { throw RemoteDeckError.unsupportedCard(card.cid) }
                }
                let language = original.first { $0.cid == card.cid }?.language ?? format.rawValue
                if let index = result.lastIndex(where: { $0.cid == card.cid && $0.type == type && $0.language == language }) {
                    result[index].quantity += remaining
                } else {
                    result.append(RemoteDeckCard(cardID: .number(Double(card.cid)), language: language,
                                                 type: type, quantity: remaining))
                }
            }
        }
        return result
    }
}
