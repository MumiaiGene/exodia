import Foundation
import Security
import CryptoKit
import CommonCrypto
import Observation

struct CardPrinting: Identifiable, Hashable, Sendable {
    let versionID: Int64
    let sourceCardID: Int64?
    let name: String
    let originName: String?
    let number: String
    let rarity: String
    let packCode: String?
    let fetchedAt: String
    var id: Int64 { versionID }
    init(versionID: Int64, sourceCardID: Int64?, name: String, originName: String?, number: String, rarity: String, packCode: String?, fetchedAt: String) {
        self.versionID = versionID; self.sourceCardID = sourceCardID; self.name = name; self.originName = originName
        self.number = number; self.rarity = rarity; self.packCode = packCode; self.fetchedAt = fetchedAt
    }
    init(data: APIValue) throws {
        guard let version = data["id"].int, version > 0, let name = data["name_cn"].text,
              let number = data["number"].text, let rarity = data["rarity"].text else { throw CardCatalogError.invalidData }
        versionID = Int64(version); sourceCardID = data["card_id"].int.map(Int64.init)
        self.name = name; originName = data["name_origin"].text; self.number = number; self.rarity = rarity
        let parts = number.split(separator: "-", maxSplits: 1)
        packCode = parts.count == 2 ? String(parts[0]) : nil
        fetchedAt = data["fetched_at"].text ?? ISO8601DateFormatter().string(from: .now)
    }
    static func normalizedName(_ value: String) -> String { CardVocabulary.normalize(value).filter { !$0.isWhitespace } }
    func matches(names: [CardName]) -> Bool {
        let aliases = Set(names.map { Self.normalizedName($0.name) })
        return aliases.contains(Self.normalizedName(name)) || originName.map { aliases.contains(Self.normalizedName($0)) } == true
    }
}

struct CardPrintingDisplay: Identifiable, Sendable {
    let id: String
    let versionID: Int64
    let sourceCardID: Int64?
    let number: String
    let rarity: String
    let packName: String
    let date: String?
}

struct JHSSellerSummary: Identifiable, Sendable, Equatable {
    let id: Int64
    let username: String
    let province: String?
    let city: String?
    let minimumPrice: Double
    let quantity: Int
    init(data: APIValue) throws {
        guard let rawID=data["seller_user_id"].int,rawID>0,
              let price=data["min_price"].marketNumber,price>=0 else { throw JHSMarketplaceError.invalidData }
        id=Int64(rawID)
        username=data["seller_username"].text ?? "卖家 #\(rawID)"
        province=data["seller_province"].text
        city=data["seller_city"].text
        quantity=max(0,data["quantity"].int ?? 0)
        minimumPrice=price
    }
    var location: String? {
        let value=[province,city].compactMap{$0}.filter{!$0.isEmpty}.joined(separator:" · ")
        return value.isEmpty ? nil:value
    }
}

struct JHSSellerPage: Sendable, Equatable {
    let currentPage: Int
    let lastPage: Int
    let total: Int
    let sellers: [JHSSellerSummary]
    init(data: APIValue) throws {
        guard let current=data["current_page"].int,current>0,
              let last=data["last_page"].int,last>=0,
              let total=data["total"].int,total>=0,
              let normal=data["data"].values else { throw JHSMarketplaceError.invalidData }
        let pinned=data["pinned_products"].values ?? []
        var unique:[Int64:JHSSellerSummary]=[:]
        for value in normal+pinned {
            let seller=try JHSSellerSummary(data:value)
            if let existing=unique[seller.id],existing.minimumPrice<=seller.minimumPrice { continue }
            unique[seller.id]=seller
        }
        currentPage=current;lastPage=last;self.total=total
        sellers=unique.values.sorted{$0.minimumPrice==$1.minimumPrice ? $0.id<$1.id:$0.minimumPrice<$1.minimumPrice}
    }
}

struct JHSMarketProduct: Identifiable, Sendable, Equatable {
    let id: Int64
    let sellerID: Int64
    let price: Double
    let quantity: Int
    let condition: Int
    let remark: String?
    let cardID:Int64?
    init(data: APIValue, sellerID: Int64, cardID:Int64?=nil) throws {
        self.cardID=cardID
        guard let rawID=data["product_id"].int,rawID>0,
              let price=data["price"].marketNumber,price>=0,
              let quantity=data["quantity"].int,quantity>=0,
              let condition=data["condition"].int,condition>0 else { throw JHSMarketplaceError.invalidData }
        if let returned=data["seller_user_id"].int,Int64(returned) != sellerID { throw JHSMarketplaceError.invalidData }
        id=Int64(rawID);self.sellerID=sellerID;self.price=price;self.quantity=quantity;self.condition=condition
        let note=data["remark"].text?.trimmingCharacters(in:.whitespacesAndNewlines)
        remark=note?.isEmpty==false ? note:nil
    }
}

struct JHSSellerProducts: Sendable, Equatable {
    let sellerID: Int64
    let cardName: String?
    let cardNumber: String?
    let rarity: String?
    let imageURL: URL?
    let products: [JHSMarketProduct]
    init(data: APIValue, sellerID: Int64) throws {
        let body=data["products"].values == nil ? data["data"]:data
        guard let rows=body["products"].values else { throw JHSMarketplaceError.invalidData }
        self.sellerID=sellerID
        cardName=body["card_name_cn"].text
        cardNumber=body["card_version_number"].text
        rarity=body["card_version_rarity"].text
        if let address=body["card_version_image"].text,var parts=URLComponents(string:address) {
            if parts.scheme=="http" { parts.scheme="https" }
            imageURL=parts.url?.host == nil ? nil:parts.url
        } else { imageURL=nil }
        let cardID=body["card_id"].int.map(Int64.init)
        products=try rows.map{try JHSMarketProduct(data:$0,sellerID:sellerID,cardID:cardID)}
            .filter{$0.condition==1 && $0.quantity>0}
            .sorted{$0.price==$1.price ? $0.id<$1.id:$0.price<$1.price}
    }
}

actor JHSMarketplaceCache {
    static let shared=JHSMarketplaceCache()
    private var pages:[String:(Date,JHSSellerPage)]=[:]
    private var products:[String:(Date,JHSSellerProducts)]=[:]
    func page(versionID:Int64,page:Int,maximumAge:TimeInterval=45)->JHSSellerPage? {
        guard let value=pages["\(versionID):\(page)"],Date.now.timeIntervalSince(value.0)<maximumAge else{return nil};return value.1
    }
    func save(_ value:JHSSellerPage,versionID:Int64){pages["\(versionID):\(value.currentPage)"]=(.now,value)}
    func sellerProducts(versionID:Int64,sellerID:Int64,maximumAge:TimeInterval=60)->JHSSellerProducts? {
        guard let value=products["\(versionID):\(sellerID)"],Date.now.timeIntervalSince(value.0)<maximumAge else{return nil};return value.1
    }
    func save(_ value:JHSSellerProducts,versionID:Int64){products["\(versionID):\(value.sellerID)"]=(.now,value)}
    func invalidate(versionID:Int64) {
        pages=pages.filter{!$0.key.hasPrefix("\(versionID):")}
        products=products.filter{!$0.key.hasPrefix("\(versionID):")}
    }
}

protocol JHSMarketplaceProviding:Sendable {
    func sellers(versionID:Int64,page:Int,force:Bool) async throws -> JHSSellerPage
    func products(versionID:Int64,sellerID:Int64,force:Bool) async throws -> JHSSellerProducts
    func addToCart(productID:Int64,cardID:Int64,sellerID:Int64,quantity:Int) async throws
    func invalidate(versionID:Int64) async
}

struct JHSMarketplaceClient: JHSMarketplaceProviding {
    let config: PrintingSourceConfig
    let transport: any APITransport
    let cache: JHSMarketplaceCache
    let usesRequestGate: Bool
    init(config: PrintingSourceConfig, transport: any APITransport = NetworkTransport(), cache: JHSMarketplaceCache = .shared, usesRequestGate: Bool = true) {
        self.config=config;self.transport=transport;self.cache=cache;self.usesRequestGate=usesRequestGate
    }
    func sellers(versionID:Int64,page:Int,force:Bool=false) async throws -> JHSSellerPage {
        guard versionID>0,page>0 else{throw JHSMarketplaceError.invalidData}
        if !force,let cached=await cache.page(versionID:versionID,page:page){return cached}
        let data=try await request(path:"v1/products",query:["card_version_id":String(versionID),"page":String(page),"condition":"1"])
        let result=try JHSSellerPage(data:data);guard result.currentPage==page else{throw JHSMarketplaceError.invalidData}
        await cache.save(result,versionID:versionID);return result
    }
    func products(versionID:Int64,sellerID:Int64,force:Bool=false) async throws -> JHSSellerProducts {
        guard versionID>0,sellerID>0 else{throw JHSMarketplaceError.invalidData}
        if !force,let cached=await cache.sellerProducts(versionID:versionID,sellerID:sellerID){return cached}
        let data=try await request(path:"v1/seller-products",query:["card_version_id":String(versionID),"seller_user_id":String(sellerID)])
        let result=try JHSSellerProducts(data:data,sellerID:sellerID)
        await cache.save(result,versionID:versionID);return result
    }
    func addToCart(productID:Int64,cardID:Int64,sellerID:Int64,quantity:Int) async throws { throw JHSMarketplaceError.writeUnavailable }
    func invalidate(versionID:Int64) async { await cache.invalidate(versionID:versionID) }
    private func request(path:String,query:[String:String]) async throws -> APIValue {
        var url=URLComponents(url:config.baseURL.appendingPathComponent(path),resolvingAgainstBaseURL:false)!
        url.queryItems=query.sorted{$0.key<$1.key}.map{URLQueryItem(name:$0.key,value:$0.value)}
        guard let address=url.url else{throw JHSMarketplaceError.configuration}
        var request=URLRequest(url:address);request.timeoutInterval=25
        request.setValue("Bearer \(config.apiKey)",forHTTPHeaderField:"Authorization")
        let result = try await (usesRequestGate ? JHSRequestGate.shared.perform(request,transport:transport):transport.data(for:request))
        if result.1.statusCode==401 {throw JHSMarketplaceError.authentication}
        if result.1.statusCode==404 {throw JHSMarketplaceError.notFound}
        guard result.1.statusCode==200 else{throw JHSMarketplaceError.unavailable}
        let value=try JSONDecoder().decode(APIValue.self,from:result.0)
        if value["error"].text != nil {throw JHSMarketplaceError.unavailable}
        return value
    }
}

struct PrintingSourceConfig: Codable, Sendable {
    let baseURL: URL
    let apiKey: String
    init(address: String, apiKey: String) throws {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "https", url.host != nil, apiKey.utf8.count >= 32 else { throw PrintingError.configuration }
        baseURL = url; self.apiKey = apiKey
    }
}
enum PrintingError: LocalizedError {
    case configuration, authentication, upstream, incomplete
    var errorDescription: String? {
        switch self {
        case .configuration: "当前构建缺少JHS协议组件，请联系开发者重新构建。"
        case .authentication: "收录数据服务认证失败，请检查服务密钥。"
        case .upstream: "收录数据服务暂时不可用，本机记录已保留。"
        case .incomplete: "收录列表未能完整读取，本机记录已保留。"
        }
    }
}
struct PrintingSourceStorage {
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.localdevelopment.Exodia.printings", kSecAttrAccount as String: "gateway"] }
    func load() throws -> PrintingSourceConfig? {
        var request = query
        request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw SessionStorageError(status: status) }
        return try JSONDecoder().decode(PrintingSourceConfig.self, from: data)
    }
    func save(_ config: PrintingSourceConfig) throws {
        let data = try JSONEncoder().encode(config)
        let attrs: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let update = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw SessionStorageError(status: update) }
        var item = query; item.merge(attrs) { _, new in new }
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw SessionStorageError(status: status) }
    }
}

struct JHSSavedSession: Codable, Sendable, Equatable {
    let token: String
    let phone: String
    let userID: String?
    let username: String?
    let avatarURL: URL?
}

protocol JHSSessionStorage: Sendable {
    func load() throws -> JHSSavedSession?
    func save(_ session:JHSSavedSession) throws
    func clear() throws
}

struct JHSKeychainSessionStorage: JHSSessionStorage {
    let service:String
    init(service:String="com.localdevelopment.Exodia.jhs.account"){self.service=service}
    private var query:[String:Any] {
        [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"jhs-session"]
    }
    func load() throws -> JHSSavedSession? {
        var request=query;request[kSecReturnData as String]=true;request[kSecMatchLimit as String]=kSecMatchLimitOne
        var result:CFTypeRef?;let status=SecItemCopyMatching(request as CFDictionary,&result)
        if status==errSecItemNotFound{return nil}
        guard status==errSecSuccess,let data=result as? Data,
              let session=try? JSONDecoder().decode(JHSSavedSession.self,from:data),!session.token.isEmpty else{throw SessionStorageError(status:status)}
        return session
    }
    func save(_ session:JHSSavedSession) throws {
        let attrs:[String:Any]=[kSecValueData as String:try JSONEncoder().encode(session),kSecAttrAccessible as String:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let update=SecItemUpdate(query as CFDictionary,attrs as CFDictionary)
        if update==errSecSuccess{return}
        guard update==errSecItemNotFound else{throw SessionStorageError(status:update)}
        var item=query;item.merge(attrs){_,new in new};let status=SecItemAdd(item as CFDictionary,nil)
        guard status==errSecSuccess else{throw SessionStorageError(status:status)}
    }
    func clear() throws {
        let status=SecItemDelete(query as CFDictionary)
        guard status==errSecSuccess || status==errSecItemNotFound else{throw SessionStorageError(status:status)}
    }
}

enum JHSAuthError:LocalizedError {
    case invalidPhone,invalidCode,rejected(String),invalidResponse,waitToResend
    var errorDescription:String? {
        switch self {
        case .invalidPhone:"当前账号没有可用于绑定的中国大陆手机号。"
        case .invalidCode:"请输入短信中的4至8位数字验证码。"
        case .rejected(let message):message.isEmpty ? "集换社拒绝了本次登录，请稍后重试。":message
        case .invalidResponse:"集换社返回了无法识别的登录结果。"
        case .waitToResend:"请等待倒计时结束后再获取验证码。"
        }
    }
}

struct JHSAuthAPI:Sendable {
    static let baseURL=URL(string:"\(PrivateConfiguration.value("marketplaceOrigin"))/api")!
    let transport:any APITransport
    init(transport:any APITransport=NetworkTransport()){self.transport=transport}
    func sendCode(phone:String) async throws {
        _=try await post("market/auth/send-sms",body:["phone":phone,"check_phone_exists":0])
    }
    func login(phone:String,code:String) async throws -> JHSSavedSession {
        let value=try await post("market/auth/login-or-signup",body:["phone":phone,"code":code])
        let data=value["token"].text == nil && value["data"].isObject ? value["data"]:value
        guard let token=data["token"].text,!token.isEmpty else{throw JHSAuthError.invalidResponse}
        let avatar=data["avatar"].text.flatMap(URL.init(string:)).flatMap{$0.scheme=="https" ? $0:nil}
        return JHSSavedSession(token:token,phone:phone,userID:data["user_id"].text,username:data["username"].text,avatarURL:avatar)
    }
    private func post(_ path:String,body:[String:Any]) async throws -> APIValue {
        var request=URLRequest(url:Self.baseURL.appendingPathComponent(path));request.httpMethod="POST";request.timeoutInterval=20
        request.setValue("application/json",forHTTPHeaderField:"Content-Type");request.setValue("application/json",forHTTPHeaderField:"Accept")
        JHSRequestHeaders.apply(to:&request)
        request.httpBody=try JSONSerialization.data(withJSONObject:body)
        let (bytes,response)=try await transport.data(for:request)
        guard (200..<300).contains(response.statusCode) else{throw JHSAuthError.rejected("集换社登录服务请求失败（\(response.statusCode)）。")}
        guard !bytes.isEmpty,let value=try? JSONDecoder().decode(APIValue.self,from:bytes) else{throw JHSAuthError.invalidResponse}
        if let error=value["error"].text {throw JHSAuthError.rejected(error)}
        if let code=value["code"].int,code != 200 {throw JHSAuthError.rejected(value["message"].text ?? value["msg"].text ?? "")}
        return value
    }
}

@Observable @MainActor
final class JHSAccountStore {
    private(set) var session:JHSSavedSession?
    private(set) var resendAt=Date.distantPast
    private(set) var isSending=false
    private(set) var isBinding=false
    var message:String?
    let api:JHSAuthAPI
    private let storage:any JHSSessionStorage
    var isBound:Bool{session != nil}
    var maskedPhone:String {
        guard let phone=session?.phone,phone.count==11 else{return "已绑定"}
        return "\(phone.prefix(3)) ···· \(phone.suffix(4))"
    }
    init(api:JHSAuthAPI=JHSAuthAPI(),storage:any JHSSessionStorage=JHSKeychainSessionStorage()) {
        self.api=api;self.storage=storage
        do{session=try storage.load()}catch{message=error.localizedDescription}
    }
    static func validPhone(_ phone:String)->Bool{phone.range(of:"^1[3-9][0-9]{9}$",options:.regularExpression) != nil}
    func sendCode(phone:String) async throws {
        guard Self.validPhone(phone) else{throw JHSAuthError.invalidPhone}
        guard !isSending,Date.now>=resendAt else{throw JHSAuthError.waitToResend}
        isSending=true;resendAt = .now.addingTimeInterval(60);defer{isSending=false}
        try await api.sendCode(phone:phone);message=nil
    }
    func bind(phone:String,code:String) async throws {
        guard Self.validPhone(phone) else{throw JHSAuthError.invalidPhone}
        guard code.range(of:"^[0-9]{4,8}$",options:.regularExpression) != nil else{throw JHSAuthError.invalidCode}
        guard !isBinding else{return};isBinding=true;defer{isBinding=false}
        let newSession=try await api.login(phone:phone,code:code);try Task.checkCancellation()
        try storage.save(newSession);session=newSession;message=nil
    }
    func importToken(_ input: String) throws {
        let token = try TokenLogin.normalized(input)
        let imported = JHSSavedSession(token: token, phone: "", userID: nil, username: nil, avatarURL: nil)
        try storage.save(imported)
        session = imported; message = nil
    }
    func unbind() throws {try storage.clear();session=nil;message=nil}
}

struct PrintingClient: Sendable {
    let config: PrintingSourceConfig
    let transport: any APITransport
    init(config: PrintingSourceConfig, transport: any APITransport = NetworkTransport()) { self.config = config; self.transport = transport }
    func searchAll(keyword: String) async throws -> [CardPrinting] {
        var records: [Int64: CardPrinting] = [:]
        var page = 1, lastPage = 1
        var reportedTotal: Int?
        repeat {
            try Task.checkCancellation()
            var url = URLComponents(url: config.baseURL.appendingPathComponent("v1/cards/search"), resolvingAgainstBaseURL: false)!
            url.queryItems = [URLQueryItem(name: "keyword", value: keyword), URLQueryItem(name: "page", value: String(page))]
            var request = URLRequest(url: url.url!)
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await JHSRequestGate.shared.perform(request, transport: transport)
            if response.statusCode == 401 { throw PrintingError.authentication }
            guard response.statusCode == 200 else { throw PrintingError.upstream }
            let value = try JSONDecoder().decode(APIValue.self, from: data)
            guard value["error"] == .null, let rows = value["data"].values,
                  value["current_page"].int == page, let last = value["last_page"].int,
                  let total = value["total"].int, last >= page, last <= 100 else { throw PrintingError.incomplete }
            if let reportedTotal, reportedTotal != total { throw PrintingError.incomplete }
            reportedTotal = total; lastPage = last
            for row in rows {
                let record = try CardPrinting(data: row)
                if let old = records[record.versionID], old.number != record.number || old.rarity != record.rarity || old.name != record.name { throw PrintingError.incomplete }
                records[record.versionID] = record
            }
            page += 1
        } while page <= lastPage
        guard records.count == reportedTotal else { throw PrintingError.incomplete }
        return records.values.sorted { $0.number == $1.number ? $0.rarity < $1.rarity : $0.number < $1.number }
    }
}

enum JHSRequestHeaders {
    // Static initialization serializes first creation; subsequent requests reuse this installation ID.
    static let deviceID:String = resolveDeviceID(defaults:.standard)
    static func resolveDeviceID(defaults:UserDefaults)->String {
        let key="exodia.jhs.deviceID"
        if let stored=defaults.string(forKey:key),let id=UUID(uuidString:stored) {return id.uuidString}
        let id=UUID().uuidString
        defaults.set(id,forKey:key)
        return id
    }
    static func userAgent(osVersion:OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion)->String {
        let version="\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
        return PrivateConfiguration.value("jhsUserAgent").replacingOccurrences(of:"{osVersion}",with:version)
    }
    static func apply(to request:inout URLRequest) {
        request.setValue(userAgent(),forHTTPHeaderField:"User-Agent")
        request.setValue(deviceID,forHTTPHeaderField:"x-device-id")
        request.setValue("*/*",forHTTPHeaderField:"Accept")
        request.setValue("zh-Hans-CN;q=1.0, ja-CN;q=0.9",forHTTPHeaderField:"Accept-Language")
    }
}

actor JHSRequestGate {
    static let shared = JHSRequestGate()
    func perform(_ request: URLRequest, transport: any APITransport) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        let result = try await transport.data(for: request)
        if result.1.statusCode == 403 || result.1.statusCode == 429 {
            let raw=result.1.value(forHTTPHeaderField:"Retry-After") ?? ""
            let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.timeZone=TimeZone(secondsFromGMT:0);formatter.dateFormat="EEE, dd MMM yyyy HH:mm:ss z"
            let delay=TimeInterval(raw) ?? formatter.date(from:raw)?.timeIntervalSinceNow ?? 60
            throw JHSRequestLimitError(statusCode:result.1.statusCode,retryAfter:delay.isFinite ? max(60,delay):60)
        }
        return result
    }
}

struct JHSProtocolProfile: Codable, Sendable {
    struct Selector: Codable, Sendable { let masterKeyHex: String; let ivPrefixHex: String }
    let schema: String
    let version: Int
    let prefixXorHex: String
    let blockXorHex: String
    let selectors: [String: Selector]
    func validate() throws {
        guard schema == "jhs-jm-random-v1", version == 1,
              try hex(prefixXorHex).count == 17, try hex(blockXorHex).count == 18, selectors["0"] != nil else { throw PrintingError.configuration }
        for config in selectors.values { guard try hex(config.masterKeyHex).count == 16, try hex(config.ivPrefixHex).count == 15 else { throw PrintingError.configuration } }
    }
    func hex(_ text: String) throws -> Data {
        let chars = Array(text); guard chars.count % 2 == 0 else { throw PrintingError.configuration }
        var bytes = Data()
        for index in stride(from: 0, to: chars.count, by: 2) { guard let value = UInt8(String(chars[index...index+1]), radix:16) else { throw PrintingError.configuration }; bytes.append(value) }
        return bytes
    }
    private var storage: [String: Any] { [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"com.localdevelopment.Exodia.jhs.protocol",kSecAttrAccount as String:"profile"] }
    static func load() throws -> Self? {
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"com.localdevelopment.Exodia.jhs.protocol",kSecAttrAccount as String:"profile",kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        var value: CFTypeRef?; let status = SecItemCopyMatching(query as CFDictionary,&value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw SessionStorageError(status:status) }
        return try JSONDecoder().decode(Self.self,from:data)
    }
    static func resolved(bundle:Bundle = .main) throws -> Self? {
        if let stored=try load(){return stored}
        guard let url=bundle.url(forResource:"JHSProtocolProfile",withExtension:"json") else{return nil}
        let profile=try JSONDecoder().decode(Self.self,from:Data(contentsOf:url));try profile.validate();return profile
    }
    static func save(_ data: Data) throws {
        guard data.count < 128 * 1024 else { throw PrintingError.configuration }
        let profile = try JSONDecoder().decode(Self.self,from:data);try profile.validate()
        let attrs: [String:Any] = [kSecValueData as String:data,kSecAttrAccessible as String:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(profile.storage as CFDictionary,attrs as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw SessionStorageError(status:status) }
        var item = profile.storage;item.merge(attrs) { _,new in new }
        let insert = SecItemAdd(item as CFDictionary,nil)
        guard insert == errSecSuccess else { throw SessionStorageError(status:insert) }
    }
    func crypt(_ input: Data, key: Data, iv: Data?, decrypt: Bool, ecb: Bool = false) throws -> Data {
        var output = Data(count:input.count+16), count = 0
        let capacity = output.count
        let status = key.withUnsafeBytes { k in input.withUnsafeBytes { src in output.withUnsafeMutableBytes { dst in
            if let iv { return iv.withUnsafeBytes { v in CCCrypt(CCOperation(decrypt ? kCCDecrypt:kCCEncrypt),CCAlgorithm(kCCAlgorithmAES),CCOptions(kCCOptionPKCS7Padding),k.baseAddress,16,v.baseAddress,src.baseAddress,input.count,dst.baseAddress,capacity,&count) } }
            return CCCrypt(CCOperation(decrypt ? kCCDecrypt:kCCEncrypt),CCAlgorithm(kCCAlgorithmAES),CCOptions(ecb ? kCCOptionECBMode:0),k.baseAddress,16,nil,src.baseAddress,input.count,dst.baseAddress,capacity,&count)
        } } }
        guard status == kCCSuccess else { throw PrintingError.configuration };return output.prefix(count)
    }
    func xor(_ input: Data) throws -> Data {
        let prefix = [UInt8](try hex(prefixXorHex)), block = [UInt8](try hex(blockXorHex)), remainder = input.count % 18
        return Data(input.enumerated().map { i,v in v ^ (i<remainder ? prefix[i] : block[(i-remainder)%18]) })
    }
    func encode(_ input: Data) throws -> String {
        guard let config = selectors["0"] else { throw PrintingError.configuration }
        var key = Data(count:16);let random = key.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault,16,$0.baseAddress!) }
        guard random == errSecSuccess else { throw PrintingError.configuration }
        var iv = try hex(config.ivPrefixHex);iv.append(key[0])
        var cipher = try crypt(input,key:key,iv:iv,decrypt:false)
        cipher.append(try crypt(key,key:hex(config.masterKeyHex),iv:nil,decrypt:false,ecb:true));cipher.append(contentsOf:[1,0])
        return try xor(cipher).base64EncodedString()
    }
    func decode(_ input: String) throws -> Data {
        guard let bytes = Data(base64Encoded:input) else { throw PrintingError.incomplete }
        let decoded = try xor(bytes)
        guard decoded.count>=34,decoded[decoded.count-2]==1,let config=selectors[String(decoded.last!)] else { throw PrintingError.incomplete }
        let key = try crypt(decoded.subdata(in:(decoded.count-18)..<(decoded.count-2)),key:hex(config.masterKeyHex),iv:nil,decrypt:true,ecb:true)
        var iv = try hex(config.ivPrefixHex);iv.append(key[0])
        return try crypt(decoded.prefix(decoded.count-18),key:key,iv:iv,decrypt:true)
    }
}

struct AnonymousPrintingClient: Sendable {
    let profile: JHSProtocolProfile
    let transport: any APITransport
    func searchAll(keyword: String) async throws -> [CardPrinting] {
        try profile.validate()
        var page = 1, last = 1, total: Int?, records: [Int64:CardPrinting] = [:]
        repeat {
            let params: [String:Any] = ["game_key":"ygo","game_sub_key":"ocg","keyword":keyword,"type":"card_version","page":page]
            var url = URLComponents(string:"\(PrivateConfiguration.value("marketplaceOrigin"))/api/market/search/match-product")!
            url.queryItems = [URLQueryItem(name:"raw_data",value:try profile.encode(JSONSerialization.data(withJSONObject:params)))]
            var request = URLRequest(url:url.url!);request.timeoutInterval=20;JHSRequestHeaders.apply(to:&request)
            let (bytes,response) = try await JHSRequestGate.shared.perform(request,transport:transport)
            guard response.statusCode==200 else { throw PrintingError.upstream }
            var value = try JSONDecoder().decode(APIValue.self,from:bytes)
            if let encrypted=value["raw_data"].text { value=try JSONDecoder().decode(APIValue.self,from:profile.decode(encrypted)) }
            guard value["error"] == .null,let rows=value["data"].values,value["current_page"].int==page,let reported=value["total"].int,let end=value["last_page"].int,end>=page,end<=20 else { throw PrintingError.incomplete }
            if let total,total != reported { throw PrintingError.incomplete };total=reported;last=end
            for row in rows { let record=try CardPrinting(data:row);guard records[record.id]==nil else{throw PrintingError.incomplete};records[record.id]=record }
            page+=1
        } while page<=last
        guard records.count==total else{throw PrintingError.incomplete};return Array(records.values)
    }
}

#if DEBUG
struct UITestJHSMarketplaceClient:JHSMarketplaceProviding {
    func sellers(versionID:Int64,page:Int,force:Bool) async throws -> JHSSellerPage {
        if ProcessInfo.processInfo.arguments.contains("--uitesting-jhs-market-long") {
            let rows=(0..<12).map{["seller_user_id":77+$0,"seller_username":"测试卡牌店 \($0+1)","seller_province":"上海","seller_city":"浦东","min_price":10+$0,"quantity":3] as [String:Any]}
            let bytes=try JSONSerialization.data(withJSONObject:["current_page":1,"last_page":1,"total":12,"data":rows])
            return try JHSSellerPage(data:JSONDecoder().decode(APIValue.self,from:bytes))
        }
        return try JHSSellerPage(data:decode("""
        {"current_page":1,"last_page":1,"total":1,"data":[{"seller_user_id":77,"seller_username":"测试卡牌店","seller_province":"上海","seller_city":"浦东","min_price":10,"quantity":3}]}
        """))
    }
    func products(versionID:Int64,sellerID:Int64,force:Bool) async throws -> JHSSellerProducts {
        try JHSSellerProducts(data:decode("""
        {"card_id":139,"card_version_image":"https://example.test/jhs-card.jpg","products":[{"product_id":7001,"seller_user_id":77,"price":10,"quantity":2,"condition":1,"remark":"轻微白边"},{"product_id":7002,"seller_user_id":77,"price":12,"quantity":1,"condition":1,"remark":"无明显瑕疵"}]}
        """),sellerID:sellerID)
    }
    func addToCart(productID:Int64,cardID:Int64,sellerID:Int64,quantity:Int) async throws {
        guard productID>0,cardID>0,sellerID>0,quantity==1 else{throw JHSMarketplaceError.invalidData}
    }
    func invalidate(versionID:Int64) async{}
    private func decode(_ text:String) throws -> APIValue{try JSONDecoder().decode(APIValue.self,from:Data(text.utf8))}
}
#endif

struct DirectJHSMarketplaceClient:JHSMarketplaceProviding {
    let profile:JHSProtocolProfile
    let session:JHSSavedSession?
    let transport:any APITransport
    let cache:JHSMarketplaceCache
    let usesRequestGate:Bool
    init(profile: JHSProtocolProfile, session: JHSSavedSession?, transport: any APITransport = NetworkTransport(), cache: JHSMarketplaceCache = .shared, usesRequestGate: Bool = true) {
        self.profile=profile;self.session=session;self.transport=transport;self.cache=cache;self.usesRequestGate=usesRequestGate
    }
    func sellers(versionID:Int64,page:Int,force:Bool=false) async throws -> JHSSellerPage {
        guard versionID>0,page>0 else{throw JHSMarketplaceError.invalidData}
        if !force,let cached=await cache.page(versionID:versionID,page:page){return cached}
        let value=try await encrypted(path:"market/card-versions/products",parameters:["game_key":"ygo","game_sub_key":"ocg","card_version_id":versionID,"page":page,"condition":1],token:nil)
        let result=try JHSSellerPage(data:value);guard result.currentPage==page else{throw JHSMarketplaceError.invalidData}
        await cache.save(result,versionID:versionID);return result
    }
    func products(versionID:Int64,sellerID:Int64,force:Bool=false) async throws -> JHSSellerProducts {
        guard versionID>0,sellerID>0 else{throw JHSMarketplaceError.invalidData}
        guard let token=session?.token,!token.isEmpty else{throw JHSMarketplaceError.loginRequired}
        if !force,let cached=await cache.sellerProducts(versionID:versionID,sellerID:sellerID){return cached}
        let value=try await encrypted(path:"market/products/bySellerCardVersionId",parameters:["game_key":"ygo","game_sub_key":"ocg","card_version_id":versionID,"seller_user_id":sellerID,"append_warehouse":0,"is_grading_card":0,"token":token],token:token)
        let result=try JHSSellerProducts(data:value,sellerID:sellerID);await cache.save(result,versionID:versionID);return result
    }
    func addToCart(productID:Int64,cardID:Int64,sellerID:Int64,quantity:Int=1) async throws {
        guard productID>0,cardID>0,sellerID>0,quantity>0,quantity<=3 else{throw JHSMarketplaceError.invalidData}
        guard let token=session?.token,!token.isEmpty else{throw JHSMarketplaceError.loginRequired}
        _=try await formPost(path:"market/carts/increment",query:["game_key":"ygo","game_sub_key":"ocg","token":token],body:["product_id":productID,"card_id":cardID,"quantity":quantity],token:token)
        guard try await cartContainsProduct(productID:productID,sellerID:sellerID) else{throw JHSMarketplaceError.rejected("购物车写入后未能读取到该商品")}
    }
    func cartContainsProduct(productID:Int64,sellerID:Int64) async throws -> Bool {
        guard productID>0,sellerID>0 else{throw JHSMarketplaceError.invalidData}
        guard let token=session?.token,!token.isEmpty else{throw JHSMarketplaceError.loginRequired}
        // Legacy cart/order endpoints read ordinary parameters, without raw_data.
        var url=URLComponents(string:"\(PrivateConfiguration.value("marketplaceOrigin"))/api/market/orders/preview")!
        url.queryItems=[URLQueryItem(name:"game_key",value:"ygo"),URLQueryItem(name:"game_sub_key",value:"ocg"),URLQueryItem(name:"seller_user_id",value:String(sellerID)),URLQueryItem(name:"token",value:token)]
        var request=URLRequest(url:url.url!);request.timeoutInterval=20
        JHSRequestHeaders.apply(to:&request)
        request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")
        let (bytes,response)=try await perform(request)
        if response.statusCode==401{throw JHSMarketplaceError.loginRequired}
        guard response.statusCode==200 else{throw JHSMarketplaceError.unavailable}
        var value=try JSONDecoder().decode(APIValue.self,from:bytes)
        if let raw=value["raw_data"].text{value=try JSONDecoder().decode(APIValue.self,from:profile.decode(raw))}
        try check(value);return containsProduct(productID,in:value)
    }
    func plainAccountRead(path:String,parameters:[String:String]=[:]) async throws -> APIValue {
        guard let token=session?.token,!token.isEmpty else{throw JHSMarketplaceError.loginRequired}
        var url=URLComponents(string:"\(PrivateConfiguration.value("marketplaceOrigin"))/api/\(path)")!
        var query=parameters;query["game_key"]="ygo";query["game_sub_key"]="ocg";query["token"]=token
        url.queryItems=query.sorted{$0.key<$1.key}.map{URLQueryItem(name:$0.key,value:$0.value)}
        var request=URLRequest(url:url.url!);request.timeoutInterval=20
        JHSRequestHeaders.apply(to:&request)
        request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")
        let (bytes,response)=try await perform(request)
        if response.statusCode==401{throw JHSMarketplaceError.loginRequired}
        guard response.statusCode==200 else{throw JHSMarketplaceError.unavailable}
        var value=try JSONDecoder().decode(APIValue.self,from:bytes)
        if let raw=value["raw_data"].text{value=try JSONDecoder().decode(APIValue.self,from:profile.decode(raw))}
        try check(value);return value
    }
    func cartSellers(page:Int) async throws -> JHSCartSellerPage {
        try JHSCartSellerPage(plainAccountReadValue:await plainAccountRead(path:"market/carts/sellers",parameters:["page":String(page)]))
    }
    func cartItems(sellerID:Int64) async throws -> [JHSCartItem] {
        let value=try await plainAccountRead(path:"market/carts",parameters:["seller_user_id":String(sellerID)])
        return try JHSCartItem.decode(value,sellerID:sellerID)
    }
    func changeCartQuantity(item:JHSCartItem,quantity:Int) async throws -> [JHSCartItem] {
        guard quantity>=0,(quantity==0 || abs(quantity-item.quantity)==1),item.cartID>0 else{throw JHSMarketplaceError.invalidData}
        guard let token=session?.token,!token.isEmpty else{throw JHSMarketplaceError.loginRequired}
        let increasing=quantity>item.quantity
        guard !increasing || (item.cardID != nil && !item.isInvalid && item.stock.map{quantity<=$0} != false) else{throw JHSMarketplaceError.invalidData}
        var body:[String:Any]=["cart_id":item.cartID,"product_id":item.productID,"quantity":1,"seller_user_id":item.sellerID]
        if let cardID=item.cardID {body["card_id"]=cardID}
        let path=quantity==0 ? "market/carts/remove":increasing ? "market/carts/increment":"market/carts/decrement"
        _=try await formPost(path:path,query:["game_key":"ygo","game_sub_key":"ocg","token":token],body:body,token:token)
        let rows=try await cartItems(sellerID:item.sellerID)
        if quantity==0 {
            guard !rows.contains(where:{$0.id==item.id}) else{throw JHSMarketplaceError.rejected("商品尚未移除，请刷新后重试。")}
        } else {
            guard rows.first(where:{$0.id==item.id})?.quantity==quantity else{throw JHSMarketplaceError.rejected("数量已变化，请刷新后确认。")}
        }
        return rows
    }
    func invalidate(versionID:Int64) async{await cache.invalidate(versionID:versionID)}
    private func encrypted(path:String,parameters:[String:Any],token:String?) async throws -> APIValue {
        try profile.validate();var url=URLComponents(string:"\(PrivateConfiguration.value("marketplaceOrigin"))/api/\(path)")!
        let raw=try profile.encode(JSONSerialization.data(withJSONObject:parameters))
        var items=[URLQueryItem(name:"raw_data",value:raw)];if let token{items.append(URLQueryItem(name:"token",value:token))};url.queryItems=items
        var request=URLRequest(url:url.url!);request.timeoutInterval=20;JHSRequestHeaders.apply(to:&request)
        if let token{request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")}
        let (bytes,response)=try await perform(request);guard response.statusCode==200 else{throw JHSMarketplaceError.unavailable}
        var value=try JSONDecoder().decode(APIValue.self,from:bytes)
        if let encrypted=value["raw_data"].text{value=try JSONDecoder().decode(APIValue.self,from:profile.decode(encrypted))}
        try check(value);return value
    }
    private func formPost(path:String,query:[String:String],body:[String:Any],token:String) async throws -> APIValue {
        try profile.validate()
        var url=URLComponents(string:"\(PrivateConfiguration.value("marketplaceOrigin"))/api/\(path)")!
        url.queryItems=query.sorted{$0.key<$1.key}.map{URLQueryItem(name:$0.key,value:$0.value)}
        guard let address=url.url else{throw JHSMarketplaceError.invalidData}
        var request=URLRequest(url:address);request.httpMethod="POST";request.timeoutInterval=20
        JHSRequestHeaders.apply(to:&request)
        request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")
        request.setValue("application/x-www-form-urlencoded",forHTTPHeaderField:"Content-Type")
        var fields=URLComponents()
        fields.queryItems=body.sorted{$0.key<$1.key}.map{URLQueryItem(name:$0.key,value:String(describing:$0.value))}
        fields.queryItems!.append(URLQueryItem(name:"token",value:token))
        // Form values must escape '+' rather than treating it as a space.
        request.httpBody=Data((fields.percentEncodedQuery ?? "").replacingOccurrences(of:"+",with:"%2B").utf8)
        let (bytes,response)=try await perform(request)
        if response.statusCode==401{throw JHSMarketplaceError.loginRequired}
        guard var value=try? JSONDecoder().decode(APIValue.self,from:bytes) else{throw JHSMarketplaceError.unavailable}
        if let encrypted=value["raw_data"].text{value=try JSONDecoder().decode(APIValue.self,from:profile.decode(encrypted))}
        guard (200..<300).contains(response.statusCode) else{throw JHSMarketplaceError.rejected(businessMessage(value) ?? "HTTP \(response.statusCode)")}
        try check(value);return value
    }
    private func perform(_ request:URLRequest) async throws -> (Data,HTTPURLResponse) {
        try await (usesRequestGate ? JHSRequestGate.shared.perform(request,transport:transport):transport.data(for:request))
    }
    private func check(_ value:APIValue) throws {
        if value["error"].text=="MARKET_LOGIN_REQUIRED"{throw JHSMarketplaceError.loginRequired}
        if value["error"].text != nil || value["code"].int.map({$0 != 200})==true{throw JHSMarketplaceError.rejected(businessMessage(value) ?? "上游业务校验失败")}
    }
    private func businessMessage(_ value:APIValue)->String? {
        [value["message"].text,value["msg"].text,value["error_description"].text,value["error"].text,value["code"].int.map(String.init)]
            .compactMap{$0?.trimmingCharacters(in:.whitespacesAndNewlines)}.first(where:{!$0.isEmpty})
    }
    private func containsProduct(_ productID:Int64,in value:APIValue)->Bool {
        switch value {
        case .object(let object):
            if object["product_id"]?.int.map(Int64.init)==productID{return true}
            return object.values.contains{containsProduct(productID,in:$0)}
        case .array(let values):return values.contains{containsProduct(productID,in:$0)}
        default:return false
        }
    }
}

enum PrintingSearch {
    static func search(keyword: String, transport: any APITransport = NetworkTransport()) async throws -> [CardPrinting] {
        if let profile=try JHSProtocolProfile.resolved() { return try await AnonymousPrintingClient(profile:profile,transport:transport).searchAll(keyword:keyword) }
        if let config=try PrintingSourceStorage().load() { return try await PrintingClient(config:config,transport:transport).searchAll(keyword:keyword) }
        throw PrintingError.configuration
    }
}


enum JHSMarketplaceError:LocalizedError {
    case configuration,invalidData,loginRequired,authentication,notFound,unavailable,writeUnavailable,rejected(String)
    var errorDescription:String? {
        switch self {
        case .configuration:"当前构建缺少集换社配置。"
        case .invalidData:"集换社返回的数据不完整。"
        case .loginRequired:"请先登录集换社。"
        case .authentication:"集换社会话已失效，请重新登录。"
        case .notFound:"未找到对应的商品。"
        case .unavailable:"暂时无法连接集换社。"
        case .writeUnavailable:"当前服务不支持此操作。"
        case .rejected(let reason):reason
        }
    }
}
extension APIValue {
    var marketNumber:Double? {
        let value:Double?
        switch self {case .number(let n):value=n;case .string(let s):value=Double(s);default:value=nil}
        return value.flatMap{$0.isFinite ? $0:nil}
    }
}

protocol JHSCartProviding:Sendable {
    func cartSellers(page:Int) async throws -> JHSCartSellerPage
    func cartItems(sellerID:Int64) async throws -> [JHSCartItem]
    func changeCartQuantity(item:JHSCartItem,quantity:Int) async throws -> [JHSCartItem]
}
extension DirectJHSMarketplaceClient:JHSCartProviding {}

struct JHSCartSeller:Identifiable,Sendable {
    let id:Int64
    let name:String
    let region:String
    var count:Int
    var total:Double
    var invalidCount:Int
    var insufficientCount:Int
    init(_ value:APIValue) throws {
        guard let id=value["seller_user_id"].int,id>0 else{throw JHSMarketplaceError.invalidData}
        self.id=Int64(id);name=value["seller_user_username"].text ?? "卖家 \(id)"
        let rawRegion=value["seller_region"].text?.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
        region=rawRegion.count==2 ? (Locale(identifier:"zh_CN").localizedString(forRegionCode:rawRegion.uppercased()) ?? rawRegion):rawRegion
        count=value["cart_count"].int ?? value["carts"].values?.count ?? 0
        total=value["total_price"].marketNumber ?? 0
        invalidCount=value["invalid_num"].int ?? 0;insufficientCount=value["quantity_insufficient_num"].int ?? 0
    }
}
struct JHSCartSellerPage:Sendable {
    let sellers:[JHSCartSeller]
    let currentPage:Int
    let lastPage:Int
    init(plainAccountReadValue value:APIValue) throws {
        guard let rows=value["data"].values,let current=value["current_page"].int,current>0,
              let last=value["last_page"].int,last>=current else{throw JHSMarketplaceError.invalidData}
        sellers=try rows.map(JHSCartSeller.init);currentPage=current;lastPage=last
    }
}
struct JHSCartItem: Identifiable, Sendable {
    var id:Int64 {cartID}
    let cartID:Int64
    let productID:Int64
    let cardID:Int64?
    let sellerID:Int64
    let sellerName:String
    let name:String
    let number:String
    let rarity:String
    let quantity:Int
    let price:Double?
    let stock:Int?
    let isInvalid:Bool
    let remark:String?
    let imageURL:URL?
    static func decode(_ value:APIValue,sellerID:Int64=0) throws -> [JHSCartItem] {
        var items:[JHSCartItem]=[]
        func walk(_ node:APIValue,sellerID:Int64,sellerName:String="") throws {
            if let rows=node.values {for row in rows{try walk(row,sellerID:sellerID,sellerName:sellerName)};return}
            guard case .object(let object)=node else{throw JHSMarketplaceError.invalidData}
            let seller=Int64(node["seller_user_id"].int ?? Int(sellerID))
            let shop=node["seller_user_username"].text ?? node["seller_username"].text ?? sellerName
            if let quantity=node["quantity"].int,let cart=node["cart_id"].int ?? node["product_id"].int {
                let product=node["product_id"].int ?? 0
                guard cart>0,quantity>0 else{throw JHSMarketplaceError.invalidData}
                let price=node["product_price"].marketNumber ?? node["price"].marketNumber
                let stock=node["product_quantity"].int
                let invalid=node["cart_status"].int==0 || product<=0 || stock==0
                guard invalid || price.map({$0>=0})==true else{throw JHSMarketplaceError.invalidData}
                items.append(JHSCartItem(cartID:Int64(cart),productID:Int64(product),cardID:node["card_id"].int.map(Int64.init),sellerID:seller,
                    sellerName:shop,name:node["card_name_cn"].text ?? node["name_cn"].text ?? "卡片商品",
                    number:node["card_version_number"].text ?? node["number"].text ?? "",
                    rarity:node["card_version_rarity"].text ?? node["rarity"].text ?? "",quantity:quantity,price:price,stock:stock,isInvalid:invalid,
                    remark:[node["product_remark_only"].text,node["product_remark"].text].compactMap{$0.map(PlainHTML.text)}.first{!$0.isEmpty},
                    imageURL:(node["card_version_image"].text ?? node["image"].text).flatMap(URL.init(string:))))
                return
            }
            let children=["data","carts"].compactMap{object[$0]}
            guard !children.isEmpty else{throw JHSMarketplaceError.invalidData}
            for child in children{try walk(child,sellerID:seller,sellerName:shop)}
        }
        try walk(value,sellerID:sellerID)
        guard Set(items.map(\.id)).count==items.count else{throw JHSMarketplaceError.invalidData}
        return items
    }
}

@Observable @MainActor final class JHSCartStore {
    private(set) var sellers:[JHSCartSeller]=[]
    private(set) var items:[Int64:[JHSCartItem]]=[:]
    private(set) var expanded:Set<Int64>=[]
    private(set) var loadingSellers:Set<Int64>=[]
    private(set) var changing:Set<Int64>=[]
    private(set) var sellerErrors:[Int64:String]=[:]
    private(set) var loading=false
    private(set) var hasMore=false
    var error:String?
    var writeError:String?
    private var client:(any JHSCartProviding)?
    private var page=0
    private var generation=UUID()
    func reset(client:(any JHSCartProviding)?) async {
        generation=UUID();self.client=client;sellers=[];items=[:];expanded=[];loadingSellers=[];changing=[];sellerErrors=[:]
        error=nil;writeError=nil;page=0;loading=false;hasMore=client != nil
        if client != nil {await loadMore()}
    }
    func loadMore() async {
        guard let client,!loading,hasMore else{return}
        let current=generation,next=page+1
        loading=true
        defer{if current==generation{loading=false}}
        do {
            let result=try await client.cartSellers(page:next)
            guard current==generation else{return}
            guard result.currentPage==next else{throw JHSMarketplaceError.invalidData}
            let existing=Set(sellers.map(\.id))
            sellers+=result.sellers.filter{!existing.contains($0.id)}
            page=next;hasMore=next<result.lastPage;error=nil
        } catch is CancellationError {} catch {if current==generation{self.error=error.localizedDescription}}
    }
    func toggle(_ sellerID:Int64) async {
        if expanded.contains(sellerID){expanded.remove(sellerID);return}
        expanded.insert(sellerID)
        if items[sellerID]==nil{await loadItems(sellerID)}
    }
    func loadItems(_ sellerID:Int64) async {
        guard let client,!loadingSellers.contains(sellerID) else{return}
        let current=generation
        loadingSellers.insert(sellerID);sellerErrors[sellerID]=nil
        defer{if current==generation{loadingSellers.remove(sellerID)}}
        do {
            let result=try await client.cartItems(sellerID:sellerID)
            guard current==generation else{return}
            items[sellerID]=result
        } catch is CancellationError {} catch {if current==generation{sellerErrors[sellerID]=error.localizedDescription}}
    }
    func change(_ item:JHSCartItem,to quantity:Int,confirmedRemoval:Bool=false) async {
        guard quantity>0 || confirmedRemoval else{return}
        guard let client,changing.isEmpty,!loadingSellers.contains(item.sellerID),(quantity==0 || abs(quantity-item.quantity)==1),
              items[item.sellerID]?.first(where:{$0.id==item.id})?.quantity==item.quantity else{return}
        let current=generation
        changing.insert(item.id)
        defer{if current==generation{changing.remove(item.id)}}
        do {
            let result=try await client.changeCartQuantity(item:item,quantity:quantity)
            guard current==generation else{return}
            items[item.sellerID]=result
            if result.isEmpty {sellers.removeAll{$0.id==item.sellerID};expanded.remove(item.sellerID)}
            else if let index=sellers.firstIndex(where:{$0.id==item.sellerID}) {
                sellers[index].count=result.count
                sellers[index].invalidCount=result.filter(\.isInvalid).count
                sellers[index].insufficientCount=result.filter{row in !row.isInvalid && row.stock.map{row.quantity>$0}==true}.count
                sellers[index].total=result.filter{!$0.isInvalid}.reduce(0){$0+($1.price ?? 0)*Double($1.quantity)}
            }
        } catch {
            guard current==generation else{return}
            writeError=error.localizedDescription
            // A transport failure can occur after the write; read before allowing another change.
            await loadItems(item.sellerID)
        }
    }
}

#if DEBUG
actor UITestJHSCartClient:JHSCartProviding {
    private var quantity=1
    private var removed=false
    private var invalidRemoved=false
    private(set) var pageRequests=0
    private(set) var detailRequests=0
    private(set) var writes=0
    var failWrites=false
    func setFailWrites(){failWrites=true}
    private func value(_ text:String) throws -> APIValue {try JSONDecoder().decode(APIValue.self,from:Data(text.utf8))}
    func cartSellers(page:Int) async throws -> JHSCartSellerPage {
        pageRequests+=1
        return try JHSCartSellerPage(plainAccountReadValue:value("""
        {"current_page":1,"last_page":1,"data":[{"seller_user_id":77,"seller_user_username":"测试卡牌店","seller_region":"cn","cart_count":2,"total_price":"10.00","invalid_num":1,"quantity_insufficient_num":0}]}
        """))
    }
    func cartItems(sellerID:Int64) async throws -> [JHSCartItem] {
        detailRequests+=1
        let normal=removed ? "":"{\"cart_id\":7001,\"product_id\":8001,\"card_id\":139,\"card_name_cn\":\"青眼白龙\",\"card_version_number\":\"TEST-001\",\"card_version_rarity\":\"UR\",\"cart_status\":1,\"quantity\":\(quantity),\"product_price\":10,\"product_quantity\":3,\"product_remark_only\":\"轻微白边\",\"card_version_image\":\"https://example.test/cart-card.jpg\"},"
        let expired=invalidRemoved ? "":"{\"cart_id\":7002,\"product_id\":8002,\"card_id\":140,\"card_name_cn\":\"失效卡片\",\"product_remark_only\":\"\",\"product_remark\":\"\",\"product_desc\":\"<label data-type=\\\"sub_title\\\">类型：</label>效果怪兽\",\"cart_status\":0,\"quantity\":1,\"product_price\":null,\"product_quantity\":0}"
        let normalRow=normal.hasSuffix(",") ? String(normal.dropLast()):normal
        return try JHSCartItem.decode(value("["+[normalRow,expired].filter{!$0.isEmpty}.joined(separator:",")+"]"),sellerID:sellerID)
    }
    func changeCartQuantity(item:JHSCartItem,quantity:Int) async throws -> [JHSCartItem] {
        writes+=1
        if failWrites{throw JHSMarketplaceError.unavailable}
        if item.id==7001 {self.quantity=quantity;removed=quantity==0}
        if item.id==7002 && quantity==0{invalidRemoved=true}
        return try await cartItems(sellerID:item.sellerID)
    }
}
#endif

struct JHSPreorderItem:Codable,Identifiable,Sendable {
    var id:Int64 {versionID}
    let versionID:Int64
    let cardCID:Int64
    let artworkID:Int64?
    let sourceCardID:Int64?
    let name:String
    let number:String
    let rarity:String
    let packName:String
    var imageURL:URL?
    var printing:CardPrintingDisplay {.init(id:"jhs:\(versionID)",versionID:versionID,sourceCardID:sourceCardID,number:number,rarity:rarity,packName:packName,date:nil)}
}
@Observable @MainActor final class JHSPreorderStore {
    static let storageKey="exodia.jhs.preorders.v1"
    static let shared:JHSPreorderStore = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            return JHSPreorderStore(defaults:UserDefaults(suiteName:"com.localdevelopment.Exodia.preorders.uitesting")!)
        }
        #endif
        return JHSPreorderStore()
    }()
    private(set) var items:[JHSPreorderItem]
    private let defaults:UserDefaults
    init(defaults:UserDefaults = .standard) {
        self.defaults=defaults
        items=defaults.data(forKey:Self.storageKey).flatMap{try? JSONDecoder().decode([JHSPreorderItem].self,from:$0)} ?? []
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting-jhs-background-flow") {
            items=[JHSPreorderItem(versionID:512088,cardCID:4041,artworkID:nil,sourceCardID:139,name:"黑魔导",number:"TEST-JP001",rarity:"UR",packName:"测试",imageURL:nil)]
        }
        #endif
    }
    private var resolving:Set<Int64>=[]
    private(set) var imageURLs:[Int64:URL]=[:]
    func rememberImage(_ url:URL?,versionID:Int64) {
        guard let url else{return}
        imageURLs[versionID]=url
        if let index=items.firstIndex(where:{$0.id==versionID}),items[index].imageURL != url {
            var updated=items;updated[index].imageURL=url;try? save(updated)
        }
    }
    func resolveImage(_ item:JHSPreorderItem,session:JHSSavedSession?,client supplied:(any JHSMarketplaceProviding)?=nil) async {
        guard item.imageURL==nil,imageURLs[item.id]==nil,!resolving.contains(item.id),session != nil else{return}
        resolving.insert(item.id);defer{resolving.remove(item.id)}
        do {
            let client:any JHSMarketplaceProviding
            if let supplied {client=supplied}
            else {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--uitesting-jhs-market") {client=UITestJHSMarketplaceClient()}
            else {guard let profile=try JHSProtocolProfile.resolved() else{return};client=DirectJHSMarketplaceClient(profile:profile,session:session)}
            #else
            guard let profile=try JHSProtocolProfile.resolved() else{return}
            client=DirectJHSMarketplaceClient(profile:profile,session:session)
            #endif
            }
            let page=try await client.sellers(versionID:item.id,page:1,force:false)
            if let seller=page.sellers.first {
                let detail=try await client.products(versionID:item.id,sellerID:seller.id,force:false)
                rememberImage(detail.imageURL,versionID:item.id)
            }
        } catch { /* An unavailable version keeps its image placeholder, never another source. */ }
    }
    func contains(_ versionID:Int64)->Bool {items.contains{$0.versionID==versionID}}
    func add(_ item:JHSPreorderItem) throws {
        guard item.versionID>0,item.cardCID>0,!contains(item.versionID) else{return}
        try save([item]+items)
    }
    func remove(_ ids:Set<Int64>) throws {try save(items.filter{!ids.contains($0.id)})}
    func toggle(_ item:JHSPreorderItem) throws {
        if contains(item.id){try remove([item.id])}else{try add(item)}
    }
    private func save(_ updated:[JHSPreorderItem]) throws {
        let data=try JSONEncoder().encode(updated)
        defaults.set(data,forKey:Self.storageKey);items=updated
    }
}
