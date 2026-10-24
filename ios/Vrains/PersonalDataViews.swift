import SwiftUI

struct AccountOverview: View {
    @Environment(AccountStore.self) private var account
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("我的赛场").font(.system(size: 21, weight: .bold))
                Spacer()
                if account.isLoading { ProgressView().tint(Design.accent) }
                else {
                    Button { Task { await account.refresh() } } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }
                        .accessibilityLabel("刷新个人资料")
                }
            }
            HStack(spacing: 0) {
                metric(account.statistics?.total.map(String.init) ?? "—", title: "赛事总场数")
                metric(account.sectionErrors["我的赛事"] == nil && account.statistics != nil ? String(account.matches.count) : "—", title: "进行中赛事")
                metric(account.unreadCount.map(String.init) ?? "—", title: "未读消息")
            }
            if let statistics = account.statistics, !statistics.categories.isEmpty {
                Divider()
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 85))], alignment: .leading, spacing: 14) {
                    ForEach(statistics.categories) { category in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(category.count.map(String.init) ?? "—").font(.system(size: 18, weight: .semibold, design: .rounded))
                            Text(category.name).font(.system(size: 11)).foregroundStyle(Design.secondary)
                        }
                    }
                }
            }
            ForEach(account.sectionErrors.keys.sorted(), id: \.self) { section in
                Text("\(section)：\(account.sectionErrors[section] ?? "")")
                    .font(.system(size: 11)).foregroundStyle(Design.secondary).accessibilityIdentifier("profile.loadError")
            }
        }.padding(20).background(Design.surface,in:RoundedRectangle(cornerRadius:25))
    }
    private func metric(_ value: String, title: String) -> some View {
        VStack(spacing: 8) {
            Text(value).font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundStyle(Design.accent)
            Text(title).font(.system(size: 10)).foregroundStyle(Design.secondary)
        }.frame(maxWidth: .infinity)
    }
}

struct PersonalMatchesSheet: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var selection = 1
    @State private var items: [MatchItem] = []
    @State private var loading = false
    @State private var error: String?
    @State private var version = UUID()
    @State private var page = 0
    @State private var hasMore = false
    private let titles = [1: "已报名", 2: "进行中", 3: "已结束"]
    // The server already filters the requested lifecycle; rows may carry finer phase IDs.
    private var visible: [MatchItem] { items }
    var body: some View {
        NavigationStack {
            List {
                Picker("比赛状态", selection: $selection) {
                    ForEach(1...3, id: \.self) { Text(titles[$0]!).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("personal.matches.status")
                if !account.isLoggedIn { Text("登录后查看已报名和参加过的比赛") }
                if let error {
                    Text(error).foregroundStyle(.secondary)
                    Button("重试") { Task { await load() } }
                }
                ForEach(visible) { match in
                    let kind = MatchKind.catalog.first { $0.id == match.typeID }?.title ?? "比赛"
                    NavigationLink { MatchSummaryScreen(match: match, kind: kind, usesTabAccessory: false) } label: {
                        LiveMatchRow(match: match, kind: kind, showsDisclosure: false)
                    }.buttonStyle(.plain).labelStyle(.titleAndIcon)
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                        .accessibilityIdentifier("personal.match.\(match.id)")
                        .onAppear { if match.id == items.last?.id, hasMore { Task { await load(reset: false) } } }
                }
                if loading { ProgressView("正在读取比赛") }
                else if error == nil, visible.isEmpty, account.isLoggedIn { EmptyState(icon:"calendar",title:"暂无\(titles[selection]!)的比赛",subtitle:"") }
            }.navigationTitle("我的比赛").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { ModalCloseButton() } }
                .task(id: "\(account.sessionVersion)-\(selection)") { await load() }
                .refreshable { await load() }
        }
    }
    private func load(reset: Bool = true) async {
        guard reset || (!loading && hasMore) else { return }
        guard account.isLoggedIn else { items = []; return }
        let requestVersion = UUID(); version = requestVersion
        let nextPage = reset ? 1 : page + 1
        let requestedStatus = selection == 1 ? 2 : selection == 2 ? 3 : 8
        if reset { items = []; page = 0; hasMore = false }
        loading = true; error = nil
        defer { if requestVersion == version { loading = false } }
        do {
            let data = try await account.fetchAuthenticated("/v1/personal/management/player", form: ["type":"0", "status":String(requestedStatus), "page":String(nextPage), "limit":"10"], method: "POST")
            try Task.checkCancellation()
            guard requestVersion == version else { return }
            let result = try Self.parsePage(data)
            var seen = Set(items.map(\.id))
            items += result.items.filter { seen.insert($0.id).inserted }
            page = nextPage
            hasMore = !result.items.isEmpty && nextPage * 10 < result.count
        } catch is CancellationError { }
        catch { if requestVersion == version { self.error = error.localizedDescription } }
    }
    static func parsePage(_ data: APIValue) throws -> (items: [MatchItem], count: Int) {
        guard let count = data["count"].int, count >= 0,
              let rows = data["res"].values else { throw APIError.invalidResponse }
        return (try rows.map(MatchItem.init), count)
    }

}

struct MessagesSheet: View {
    @Environment(AccountStore.self) private var account
    @State private var items: [Notice] = []
    @State private var error: String?
    @State private var loading = false
    @State private var page = 1
    @State private var total = 0
    @State private var hasMore = false
    var body: some View {
        NavigationStack {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let error {
                    Text(error).font(.subheadline).foregroundStyle(Design.secondary)
                    AccentButton(title: "重试") { Task { await load(reset: true) } }
                }
                if !loading, error == nil, items.isEmpty {
                    EmptyState(icon: "bell", title: "暂无消息", subtitle: "比赛通知会出现在这里。")
                }
                LazyVStack(spacing: 20) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(item.title).font(.headline).accessibilityIdentifier("notice.row.\(item.id)")
                            if !item.content.isEmpty { Text(item.content).font(.subheadline).lineSpacing(5).foregroundStyle(Design.secondary) }
                            if let date = item.date { Text(date).font(.caption).foregroundStyle(Design.secondary) }
                        }.frame(maxWidth:.infinity,alignment:.leading).padding(20).background(Design.surface,in:RoundedRectangle(cornerRadius:22))
                    }
                    InfiniteScrollFooter(itemCount: items.count, canLoadMore: hasMore && error == nil, isLoading: loading) {
                        await load(reset: false)
                    }
                }
            }.padding(24)
        }.background(Design.canvas).task { await load(reset: true) }
            .automaticPagination(itemCount: items.count, canLoadMore: hasMore && error == nil, isLoading: loading) { await load(reset: false) }
            .refreshable { await load(reset: true) }
            .navigationTitle("消息中心").navigationBarTitleDisplayMode(.inline)
            .toolbar {ToolbarItem(placement:.cancellationAction){ModalCloseButton().accessibilityIdentifier("navigation.back")}}
            .presentationDragIndicator(.visible)
        }
    }
    private func load(reset: Bool) async {
        guard !loading, reset || hasMore else { return }
        loading = true; error = nil
        defer { loading = false }
        let requestedPage = reset ? 1 : page + 1
        do {
            let data = try await account.fetchAuthenticated("/v1/notice/center", form: ["page": String(requestedPage), "limit": "20"])
            guard let list = data["list"].values, let count = data["count"].int else { throw APIError.invalidResponse }
            let next = list.enumerated().map { Notice(data: $0.element, fallbackID: "\(requestedPage)-\($0.offset)") }
            var ids = Set<String>()
            items = (reset ? next : items + next).filter { ids.insert($0.id).inserted }
            total = count; page = requestedPage
            hasMore = !next.isEmpty && requestedPage * 20 < count
        } catch is CancellationError { }
        catch { self.error = AccountStore.message(for: error) }
    }
    private struct Notice: Identifiable {
        let id: String
        let title: String
        let content: String
        let date: String?
        init(data: APIValue, fallbackID: String) {
            id = data["id"].text ?? fallbackID
            title = data["title"].text ?? "赛事通知"
            content = PlainHTML.text(data["content"].text ?? "")
            date = data["created_at"].text ?? data["create_time"].text
        }
    }
}

struct ProfileDetailsSheet: View {
    @Environment(AccountStore.self) private var account
    var body: some View {
        NavigationStack {
            List {
                LabeledContent("昵称", value: account.displayName)
                LabeledContent("决斗者 ID", value: account.profile?.displayID ?? "—")
                LabeledContent("手机号", value: account.maskedPhone)
                LabeledContent("当前身份", value: account.profile?.roleName ?? "—")
                LabeledContent("实名认证", value: account.profile?.isReal.map { $0 ? "已实名" : "未实名" } ?? "—")
                LabeledContent("个性签名", value: account.profile?.signature ?? "尚未填写")
                if let title = account.profile?.title { LabeledContent("称号", value: title) }
            }.navigationTitle("个人资料").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarLeading) { ModalCloseButton() } }
        }
    }
}

enum PlainHTML {
    static func text(_ html: String) -> String {
        html.replacingOccurrences(of: "(?is)<(script|style)[^>]*>.*?</\\1>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?i)<br\\s*/?>|</p>|</div>|</li>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct MatchOrder: Identifiable {
    let id: String
    let number: String
    let name: String
    let image: URL?
    let status: Int
    let total: Double?
    init(_ row: APIValue) throws {
        guard let id = row["id"].text, let number = row["order_id"].text,
              let name = row["name"].text, let status = row["status"].int else { throw APIError.invalidResponse }
        self.id = id; self.number = number; self.name = name; self.status = status
        total = row["cost"].text.flatMap(Double.init)
        image = row["image"].text.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
    }
}

struct MatchOrdersSheet: View {
    @Environment(AccountStore.self) private var account
    @State private var orders: [MatchOrder] = []
    @State private var statusNames: [String: String] = [:]
    @State private var page = 0
    @State private var hasMore = false
    @State private var loading = false
    @State private var error: String?
    @State private var generation = UUID()
    var body: some View {
        NavigationStack {
            List {
                ForEach(orders) { order in
                    Section {
                        HStack {
                            Text("订单 \(order.number)").font(.subheadline)
                            Spacer()
                            Text(statusNames[String(order.status)] ?? "状态 \(order.status)").font(.caption).foregroundStyle(order.status == 0 ? .orange : .secondary)
                        }
                        HStack(spacing: 12) {
                            AsyncImage(url: order.image) { image in image.resizable().scaledToFit() } placeholder: { Image(systemName:"receipt").foregroundStyle(.secondary) }
                                .frame(width:48,height:48)
                            Text(order.name).font(.subheadline)
                        }
                        if let total = order.total { HStack { Spacer(); Text(total.formatted(.currency(code:"CNY").locale(Locale(identifier:"zh_CN")))).font(.headline) } }
                    }.accessibilityIdentifier("orders.row.\(order.id)")
                }
                if loading { ProgressView() }
                if let error { Text(error).foregroundStyle(.secondary); Button("重试") { Task { await load(reset:true) } } }
                else if !loading, orders.isEmpty, !hasMore { EmptyState(icon:"receipt",title:"暂无比赛订单",subtitle:"") }
                if hasMore, !loading, error == nil {
                    if orders.isEmpty { ProgressView().task(id:page) { await load(reset:false) } }
                    else { Button("加载更多") { Task { await load(reset:false) } } }
                }
            }.navigationTitle("比赛订单").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.topBarLeading) { ModalCloseButton() } }
                .task(id:account.sessionVersion) { await load(reset:true) }
                .refreshable { await load(reset:true) }
        }
    }
    private func load(reset: Bool) async {
        guard reset || (!loading && hasMore) else { return }
        if reset { generation = UUID(); orders = []; page = 0; hasMore = false }
        let version = generation; let next = reset ? 1 : page + 1
        loading = true; error = nil
        defer { if generation == version { loading = false } }
        do {
            let data = try await account.fetchAuthenticated("/v1/match/order/index", form:["type":"1","status":"-2","page":String(next),"limit":"10"])
            try Task.checkCancellation(); guard generation == version else { return }
            guard let count = data["count"].int, let rows = data["res"].values else { throw APIError.invalidResponse }
            statusNames = Self.options(data["orderStatusMap"])
            let parsed = try rows.map(MatchOrder.init)
            var seen = Set(orders.map(\.id)); orders += parsed.filter { seen.insert($0.id).inserted }
            page = next; hasMore = !rows.isEmpty && next * 10 < count
        } catch is CancellationError { }
        catch { if generation == version { self.error = error.localizedDescription } }
    }
    static func options(_ value: APIValue) -> [String: String] {
        var result: [String:String] = [:]
        for row in value.values ?? [] {
            if case .object(let values) = row { for (key, value) in values { if let title = value.text { result[key] = title } } }
        }
        return result
    }
}
