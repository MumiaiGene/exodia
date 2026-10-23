import SwiftUI

struct MatchDetail: Sendable {
    let id: String
    let name: String
    let organizer: String?
    let address: String?
    let startsAt: String?
    let typeID: Int?
    let statusID: Int?
    let environment: String?
    let rule: String?
    let rounds: Int?
    let winning: Int?
    let contact: String?
    let joinCondition: String?
    let costCents: Int?
    let signedCount: Int?
    let capacity: Int?
    let remarks: String?
    let prizes: String?
    let privacy: String?
    let registrationMessage: String?
    let signupStartsAt: String?
    let requiresDeck: Bool
    let usesQueue: Bool
    let onlinePayment: Bool
    let role: String?
    let isSignedUp: Bool
    let hasCheckedIn: Bool?
    let hasOrder: Bool
    let isFrozen: Bool
    let errorCode: Int
    let backup: Bool
    init(data: APIValue) throws {
        let info = data["info"], basic = info["basic_info"], desc = info["desc_info"]
        guard let id = info["id"].text, let name = basic["name"].text ?? info["Name"].text else { throw APIError.invalidResponse }
        self.id = id; self.name = name
        organizer = basic["customer_name"].text
        address = basic["address"].text.flatMap { $0.isEmpty ? nil : $0 } ?? basic["address_info"].text
        startsAt = basic["start_at"].text
        typeID = info["Type"].int; statusID = info["Status"].int
        environment = info["Condition"].int.flatMap { $0 == 1 ? "简体中文" : $0 == 2 ? "OCG" : nil }
        rule = desc["rule_display"].text
        rounds = info["Rounds"].int; winning = info["Winning"].int
        contact = desc["contact"].text; joinCondition = desc["join_condition"].text
        costCents = desc["cost_int"].int
        signedCount = info["player"]["sign_count"].int; capacity = info["player"]["player_count"].int
        remarks = desc["remarks"].text; prizes = desc["prize_desc"].text; privacy = info["privacy"].text
        registrationMessage = data["bottom"]["title"]["text"].text
        signupStartsAt = info["SignUpStartAt"].text.flatMap { $0.hasPrefix("1970") ? nil : $0 }
        requiresDeck = info["IsDeck"].flag ?? false
        usesQueue = info["is_queue"].flag ?? false
        onlinePayment = info["IsOnlinePayment"].int == 1
        role = data["role"].text
        isSignedUp = data["isSignup"].flag ?? false
        hasCheckedIn = data["isArrive"].flag
        hasOrder = data["isOrder"].flag ?? false
        isFrozen = info["IsFreeze"].flag ?? false
        errorCode = info["ErrorCode"].int ?? 0
        backup = data["backup"].flag ?? false
    }
    var costText: String? { costCents.map { $0 == 0 ? "免费" : (Double($0) / 100).formatted(.currency(code: "CNY").locale(Locale(identifier: "zh_CN"))) } }
    func awaitingOpening(at date: Date = .now) -> Bool {
        guard statusID == 2, !isSignedUp else { return false }
        if let title = registrationMessage, ["待开放", "未开放", "暂未开放"].contains(title) { return true }
        if let start = signupStartsAt, let opensAt = ISO8601DateFormatter().date(from:start), opensAt > date { return true }
        return false
    }
    var isFull: Bool {
        if let text = registrationMessage, ["报名已满", "已满", "满员", "名额已满", "人数已满", "报名人数已满"].contains(text) { return true }
        guard let capacity, capacity > 0, let signedCount else { return false }
        return signedCount >= capacity
    }
    var canRegister: Bool { statusID == 2 && !isSignedUp && !isFrozen && errorCode == 0 && !awaitingOpening() && (!isFull || hasOrder) }
    var hasParticipated: Bool { isSignedUp || role == "player" }
    var checkInStatus: String {
        switch hasCheckedIn { case true: "已签到"; case false: "未签到"; case nil: "签到状态未知" }
    }
    var canViewPersonalResults: Bool { hasParticipated && (statusID == 3 || statusID == 4 || statusID == 8) }
    var kind: String { MatchKind.catalog.first { $0.id == typeID }?.title ?? "比赛" }
}

extension BusinessAPI {
    func matchDetail(id: String, backup: Bool, token: String? = nil) async throws -> MatchDetail {
        guard !id.isEmpty, id.allSatisfy({ $0.isASCII && $0.isNumber }) else { throw APIError.invalidResponse }
        return try MatchDetail(data: await request("/v1/match/info/\(id)", form: ["backup": backup ? "true" : "false"], token: token))
    }
}

enum MatchHTML {
    static func plain(_ source: String) -> String {
        source.replacingOccurrences(of: "(?is)<(script|style)[^>]*>.*?</\\1>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?i)<br[^>]*>|</p>|</div>|</li>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "\n[ \t]*\n[ \t]*\n+", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct MatchSummaryScreen: View {
    let match: MatchItem
    let kind: String
    var usesTabAccessory = true
    @Environment(AccountStore.self) private var account
    @State private var detail: MatchDetail?
    @State private var isLoading = false
    @State private var loadVersion = UUID()
    @State private var errorMessage: String?
    @Environment(MatchRegistrationAccessory.self) private var accessory
    @State private var detailTab = 0
    @State private var showingLogin = false
    @State private var confirmingWithdrawal = false
    @State private var withdrawing = false
    @State private var withdrawalError: String?
    @State private var enrollment = MatchEnrollment()
    @State private var loadedSessionVersion: UUID?
    @State private var resultsRefreshVersion = UUID()
    @State private var gradeSubmissions: [String: MatchGradeSubmission] = [:]
    @State private var gradeTarget: MatchGradeTarget?
    private var showsResults: Bool {
        account.isLoggedIn && loadedSessionVersion == account.sessionVersion && detail?.canViewPersonalResults == true
    }
    private var showsOwnParticipation: Bool {
        account.isLoggedIn && loadedSessionVersion == account.sessionVersion && detail?.hasParticipated == true
    }
    var body: some View {
        List {
            if let detail {
                Section { header(detail) }.listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                if showsResults, detailTab == 1 {
                    MatchPairingsSection(match: match, status: detail.statusID ?? 0, refreshVersion: resultsRefreshVersion, gradeTarget: $gradeTarget, submissions: $gradeSubmissions)
                        .id("pairings-\(match.id)-\(account.sessionVersion)-\(resultsRefreshVersion)")
                } else if showsResults, detailTab == 2 {
                    MatchResultsSection(match: match, showsKnockout: false, status: detail.statusID ?? 0, refreshVersion: resultsRefreshVersion)
                } else {
                Section("赛制与参赛") {
                    if let rule = detail.rule { LabeledContent("赛制", value: rule) }
                    if let rounds = detail.rounds, rounds > 0 { LabeledContent("轮数", value: "\(rounds) 轮") }
                    if let winning = detail.winning, winning > 0 { LabeledContent("晋级", value: "\(winning) 强") }
                    if let cost = detail.costText { LabeledContent("费用", value: cost) }
                    if let condition = detail.joinCondition { LabeledContent("参赛条件", value: condition) }
                    LabeledContent("卡表", value: detail.requiresDeck ? "需要提交" : "无提交要求")
                    if let contact = detail.contact { LabeledContent("联系信息", value: contact).textSelection(.enabled) }
                    if let signupStart = detail.signupStartsAt, let date = ISO8601DateFormatter().date(from: signupStart) { LabeledContent("开放报名", value: date.formatted(date: .abbreviated, time: .shortened)) }
                }
                if let prizes = detail.prizes { richSection("奖品说明", html: prizes) }
                if let remarks = detail.remarks { richSection("比赛说明", html: remarks) }
                if let privacy = detail.privacy { richSection("参赛须知", html: privacy) }
                }
            }
            if isLoading { ProgressView("正在加载比赛详情") }
            if let message = enrollment.error { Text(message).foregroundStyle(.red) }
            if let orderID = enrollment.orderID {
                LabeledContent("订单号", value: orderID)
                Text("待支付，请在小程序完成支付。").foregroundStyle(.secondary)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.secondary)
                Button("重试") { Task { await load() } }
            }
        }.background(Design.canvas)
        .navigationTitle(detail?.name ?? match.name).navigationBarTitleDisplayMode(.large)
        .onDisappear { accessory.action = nil }
        .task(id: "\(match.id)-\(account.sessionVersion)") { await load() }
        .onChange(of: account.sessionVersion) { _, _ in gradeTarget = nil; gradeSubmissions = [:] }
        .refreshable { await load(); resultsRefreshVersion = UUID() }
        .sheet(isPresented: $showingLogin) { LoginSheet() }
        .sheet(item: $gradeTarget) { target in
            MatchGradeSheet(target: target, submission: target.submission) { grade in
                let viewerIDs = Set([account.profile?.displayID, account.session?.userID].compactMap { $0 })
                guard showsResults,
                      MatchGradeTarget.isEligible(game: target.game, viewerIDs: viewerIDs, status: detail?.statusID ?? 0, backup: match.isBackup, stage: target.stage),
                      let id = target.game.submissionID else { return }
                let sessionVersion = account.sessionVersion
                await target.submission.submit {
                    _ = try await account.fetchAuthenticated("/v1/match/grades/" + id,
                        form: ["grade": String(grade.rawValue), "statusid": target.stage])
                }
                if sessionVersion == account.sessionVersion { resultsRefreshVersion = UUID() }
            }
        }
        .confirmationDialog("退出比赛？", isPresented: $confirmingWithdrawal, titleVisibility: .visible) {
            Button("退赛", role: .destructive) { Task { await withdraw() } }
        } message: {
            Text("退出后将释放报名名额。付费比赛的退款需另行申请。")
        }
        .alert("退赛失败", isPresented: Binding(get: { withdrawalError != nil }, set: { if !$0 { withdrawalError = nil } })) {
            Button("好", role: .cancel) { withdrawalError = nil }
        } message: { Text(withdrawalError ?? "") }
    }
    private func header(_ detail: MatchDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text(detail.kind)
                    .foregroundStyle(MatchKind(id: detail.typeID ?? 0, title: detail.kind).tint)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(MatchKind(id: detail.typeID ?? 0, title: detail.kind).tint.opacity(0.1), in: Capsule())
                if let environment = detail.environment {
                    Text(environment).padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                }
                Spacer(minLength: 6)
                if detail.statusID == 2, showsOwnParticipation {
                    Text("已报名").foregroundStyle(.green)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(Color.green.opacity(0.1), in: Capsule())
                        .accessibilityIdentifier("match.detail.signedUp")
                } else {
                    Text(detail.awaitingOpening() ? "待开放" : detail.statusID == 2 && detail.isFull && !detail.hasParticipated && !detail.hasOrder ? "报名已满" : (detail.statusID == 4 ? "比赛中" : detail.statusID.flatMap(MatchStatus.init(rawValue:))?.title) ?? "比赛")
                        .foregroundStyle(.secondary)
                }

            }.font(.caption.weight(.semibold)).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if let start = detail.startsAt { Label(start, systemImage: "clock").font(.subheadline.weight(.medium)) }
                Spacer(minLength: 0)
                if let count = detail.signedCount {
                    Text(detail.capacity.map { "\(count) / \($0) 人" } ?? "\(count) 人")
                        .font(.subheadline.weight(.medium)).foregroundStyle(.secondary).fixedSize()
                }
            }
            if let organizer = detail.organizer { Text(organizer).font(.subheadline.weight(.semibold)) }
            if let address = detail.address {
                Text(address).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            if detail.statusID == 2 {
                HStack(spacing: 12) {
                    registrationAction(detail)
                    if showsOwnParticipation { checkInStatus(detail) }
                    Spacer()
                }.padding(.top, 2)
            } else if showsOwnParticipation {
                checkInStatus(detail)
            }
            if showsResults {
                Picker("比赛详情", selection: Binding(get: { detailTab }, set: { tab in
                    if tab == 1, detailTab != 1 { resultsRefreshVersion = UUID() }
                    detailTab = tab
                })) {
                    Text("比赛信息").tag(0); Text("比赛对局").tag(1); Text("瑞士轮").tag(2)
                }.pickerStyle(.segmented).padding(.top, 6).accessibilityIdentifier("match.detail.tabs")
            }
        }.padding(.vertical, 4).labelStyle(.titleAndIcon)
    }
    @ViewBuilder private func registrationAction(_ detail: MatchDetail) -> some View {
            if detail.awaitingOpening() {
                Button { } label: { Text("待开放").font(.headline).padding(.horizontal,24).frame(height:44) }
                    .buttonStyle(.borderedProminent).clipShape(Capsule())
                    .disabled(true).accessibilityIdentifier("match.detail.pending")
            } else if detail.isSignedUp {
                if showsOwnParticipation, match.startsAt.map({ $0 > Date.now }) ?? true {
                    Button(role: .destructive) { confirmingWithdrawal = true } label: {
                        HStack(spacing: 6) {
                            if withdrawing { ProgressView() }
                            Text(withdrawing ? "退赛中" : "退赛")
                        }.font(.headline)
                            .padding(.horizontal, 24).frame(height: 44).contentShape(Capsule())
                    }.buttonStyle(.borderedProminent).clipShape(Capsule())
                        .disabled(withdrawing || isLoading).accessibilityIdentifier("match.detail.withdraw")
                }
            } else if detail.isFull && !detail.hasOrder {
                Button { } label: { Text("报名已满").font(.headline).padding(.horizontal,24).frame(height:44) }
                    .buttonStyle(.borderedProminent).clipShape(Capsule()).disabled(true)
                    .accessibilityIdentifier("match.detail.full")
            } else if detail.canRegister {
                Button {
                    if account.isLoggedIn {
                        Task { await enrollment.run(detail: detail, account: account); if enrollment.completed { await load() } }
                    } else { showingLogin = true }
                } label: {
                    HStack(spacing: 8) {
                        if enrollment.busy { ProgressView().tint(.white) }
                        if enrollment.completed { Text("已报名") }
                        else { Text(enrollment.busy ? enrollment.title : enrollment.orderID != nil || detail.hasOrder ? "待支付" : "报名") }
                    }.font(.headline).padding(.horizontal,24).frame(height:44)
                }.buttonStyle(.borderedProminent).clipShape(Capsule()).disabled(isLoading || enrollment.busy || enrollment.completed).accessibilityIdentifier("match.detail.register")
            }
    }
    private func checkInStatus(_ detail: MatchDetail) -> some View {
        Label(detail.checkInStatus, systemImage: detail.hasCheckedIn == true ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(detail.hasCheckedIn == true ? Color.green : detail.hasCheckedIn == false ? Color.orange : Color.secondary)
            .accessibilityIdentifier("match.detail.checkIn")
    }
    private func withdraw() async {
        guard let detail, detail.statusID == 2, detail.isSignedUp, showsOwnParticipation,
              !withdrawing, match.startsAt.map({ $0 > Date.now }) ?? true else { return }
        withdrawing = true
        defer { withdrawing = false }
        do {
            _ = try await account.fetchAuthenticated("/v1/match/signup/" + detail.id, form: ["remark": "因个人原因申请退赛"], method: "DELETE")
            enrollment = MatchEnrollment()
            await load()
            if let errorMessage { withdrawalError = errorMessage }
            else if self.detail?.isSignedUp == true { withdrawalError = "服务端仍显示已报名，尚未确认退赛成功，请刷新后重试。" }
        } catch { withdrawalError = error is URLError ? "网络连接失败，暂时无法确认退赛结果，请刷新后重试。" : error.localizedDescription }
    }
    @ViewBuilder private func richSection(_ title: String, html: String) -> some View {
        Section(title) {
            DisclosureGroup("阅读\(title)") {
                Text(MatchHTML.plain(html)).font(.subheadline).textSelection(.enabled)
            }
        }
    }
    private func load() async {
        let sessionVersion = account.sessionVersion
        let version = UUID(); loadVersion = version
        isLoading = true; errorMessage = nil
        defer { if loadVersion == version { isLoading = false } }
        do {
            let value = try await account.api.matchDetail(id: match.id, backup: match.isBackup, token: account.session?.token)
            try Task.checkCancellation()
            guard version == loadVersion, sessionVersion == account.sessionVersion else { return }
            if loadedSessionVersion != sessionVersion {
                detailTab = account.isLoggedIn && value.hasParticipated && [3, 4].contains(value.statusID ?? 0) ? 1 : 0
            }
            detail = value
            loadedSessionVersion = sessionVersion
            if !account.isLoggedIn || !value.canViewPersonalResults { detailTab = 0 }
            accessory.action = nil

        } catch is CancellationError { }
        catch {
            guard version == loadVersion else { return }
            errorMessage = error is URLError ? "暂时无法加载比赛详情，请重试。" : error.localizedDescription
        }
    }
}

private struct MatchRichTextScreen: View {
    let title: String
    let html: String
    var body: some View {
        if let content = try? NewsDetail(data: .object(["title": .string(title), "details": .string(html)])) {
            NewsRichText(document: NewsHTML.document(content)).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        }
    }
}

@Observable @MainActor
final class MatchEnrollment {
    enum Phase: Equatable { case idle, verifying, checking, submitting, queueing, confirming, enrolled, orderCreated, uncertain, failed }
    private(set) var phase: Phase = .idle
    private(set) var orderID: String?
    private(set) var dispatched = false
    var error: String?
    var busy: Bool { [.verifying, .checking, .submitting, .queueing, .confirming].contains(phase) }
    var completed: Bool { phase == .enrolled }
    var title: String {
        switch phase {
        case .verifying: "正在验证"
        case .checking: "正在预检"
        case .submitting: "正在报名"
        case .queueing: "排队中"
        case .confirming: "正在确认订单"
        case .enrolled: "已报名"
        case .orderCreated: "订单已生成 · 待支付"
        case .uncertain: "正在核对报名结果"
        default: "报名"
        }
    }
    func run(detail: MatchDetail, account: AccountStore, ticket: String? = nil, pause: @escaping () async throws -> Void = { try await Task.sleep(for: .seconds(5)) }) async {
        guard !busy, !dispatched else { return }
        error = nil
        do {
            guard detail.canRegister else { throw APIError.business(0, "当前比赛不可报名。") }
            if detail.hasOrder {
                phase = .confirming
                let order = try await account.fetchAuthenticated("/v1/match/order/confirm/" + detail.id)
                guard let id = order["order_id"].text, !id.isEmpty, id != "0" else { throw APIError.invalidResponse }
                orderID = id; phase = .orderCreated; return
            }
            var code = ticket
            if detail.onlinePayment, code?.isEmpty != false {
                phase = .verifying
                guard let token = account.session?.token else { throw APIError.sessionExpired }
                code = try await account.api.matchCaptcha(token:token).trueCode()
            }
            if account.profile?.isReal == false { throw APIError.business(0, "请先在小程序完成实名认证。") }
            phase = .checking
            _ = try await account.fetchAuthenticated("/v1/match/player/check/" + detail.id)
            try Task.checkCancellation()
            // Never automatically repeat this state-changing GET after dispatch.
            phase = .submitting; dispatched = true
            do {
                _ = try await account.fetchAuthenticated("/v1/match/signup/" + detail.id, form: detail.onlinePayment ? ["code": code!] : [:])
            } catch APIError.business(let code, let message) where code == 40029 {
                phase = .uncertain
                error = message.isEmpty ? "报名结果暂未确认，请查询比赛订单。" : message
                return
            }
            if detail.onlinePayment {
                if detail.usesQueue {
                    phase = .queueing
                    var granted = false
                    // Bounded observation; interruption never repeats signup or claims success.
                    for _ in 0..<120 {
                        try await pause(); try Task.checkCancellation()
                        let result: APIValue
                        do { result = try await account.fetchAuthenticated("/v1/match/monitor/signup/" + detail.id, includeEnvelope: true) }
                        catch APIError.business(let code, _) where code != 10313 && code != 10314 { continue }
                        guard result["msg"].text == "报名成功" else {
                            throw APIError.business(0, result["msg"].text ?? "排队未完成。")
                        }
                        granted = true; break
                    }
                    guard granted else { throw APIError.business(0, "排队结果尚未确认，请查询比赛订单。") }
                }
                phase = .confirming
                let order = try await account.fetchAuthenticated("/v1/match/order/confirm/" + detail.id)
                guard let id = order["order_id"].text, !id.isEmpty, id != "0" else { throw APIError.invalidResponse }
                orderID = id; phase = .orderCreated
            } else {
                phase = .confirming
                let latest = try await account.api.matchDetail(id: detail.id, backup: detail.backup, token: account.session?.token)
                guard latest.isSignedUp else { throw APIError.business(0, "报名结果尚未确认，请刷新详情核对，勿重复提交。") }
                phase = .enrolled
            }
        } catch {
            phase = dispatched ? .uncertain : .failed
            self.error = error is CancellationError ? "查询已中断，请刷新详情或比赛订单核对，勿重复报名。" : AccountStore.message(for: error)
        }
    }
}

@Observable final class MatchRegistrationAccessory {
    var title = "报名"
    var action: (() -> Void)?
}

struct MatchResultPlayer: Identifiable, Sendable {
    let id: String
    let rank: Int
    let nickname: String
    let score: Int
    let avatar: URL?
    init?(_ row: APIValue) {
        guard let rank = row["rank"].int, rank > 0, let score = row["score"].int else { return nil }
        self.rank = rank; self.score = score
        id = row["sid"].text ?? String(rank)
        nickname = row["nickname"].text.flatMap { $0.isEmpty ? nil : $0 } ?? "选手"
        avatar = row["avatar"].text.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
    }
}

struct SwissRankRound: Identifiable {
    let id: String
    let title: String
    static func parse(_ data: APIValue) -> [SwissRankRound] {
        var seen = Set<String>()
        return (data.values ?? []).compactMap { row in
            guard row["statusId"].int == 4, let id = row["rounds"].text,
                  let title = row["title"].text, seen.insert(id).inserted else { return nil }
            return SwissRankRound(id: id, title: title.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

struct MatchResultsSection: View {
    let match: MatchItem
    var showsKnockout = true
    var status = 8
    var refreshVersion = UUID()
    @Environment(AccountStore.self) private var account
    @State private var players: [MatchResultPlayer] = []
    @State private var current: MatchResultPlayer?
    @State private var knockout: [KnockoutRound] = []
    @State private var roundTitle: String?
    @State private var error: String?
    @State private var loading = false
    @State private var page = 0
    @State private var total = 0
    @State private var hasMore = false
    @State private var generation = UUID()
    @State private var roundChoices: [SwissRankRound] = []
    @State private var selectedRound = ""
    private var isLive: Bool { [3, 4].contains(status) && !match.isBackup }
    var body: some View {
        ForEach(showsKnockout ? knockout : []) { round in
            Section("淘汰赛 · " + round.title) {
                ForEach(round.games) { game in DuelResultRow(game: game) }
            }
        }
        if isLive, !roundChoices.isEmpty {
            Section {
                Picker("轮次", selection: $selectedRound) {
                    ForEach(roundChoices) { round in Text(round.title).tag(round.id) }
                }.accessibilityIdentifier("match.results.round")
                    .onChange(of: selectedRound) { old, new in
                        if !old.isEmpty, old != new { Task { await load(reset: true) } }
                    }
            }
        }
        Section(isLive ? "我的排名" : "我的成绩") {
            if let current { resultRow(current).accessibilityIdentifier("match.results.current") }
            else if !loading { Text(account.isLoggedIn ? "暂无个人成绩记录" : "登录后查看个人成绩").foregroundStyle(.secondary) }
        }
        Section(roundTitle ?? "比赛成绩") {
            ForEach(players) { player in resultRow(player).accessibilityIdentifier("match.results.player.\(player.id)") }
            if loading { ProgressView("正在读取成绩") }
            if let error {
                Text(error).foregroundStyle(.secondary)
                Button("重试") { Task { await load(reset: page == 0) } }
            } else if !loading, players.isEmpty { Text("暂无已公布的排名").foregroundStyle(.secondary) }
            if hasMore, !loading, error == nil { Button("加载更多成绩") { Task { await load(reset: false) } } }
        }
        .task(id: "\(match.id)-\(account.sessionVersion)-\(refreshVersion)-\(status)") { await load(reset: true) }
    }
    private func resultRow(_ player: MatchResultPlayer) -> some View {
        HStack(spacing: 12) {
            Text(String(player.rank)).font(.headline).monospacedDigit().frame(width: 30)
            AsyncImage(url: player.avatar) { image in image.resizable().scaledToFill() } placeholder: {
                Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
            }.frame(width: 36, height: 36).clipShape(Circle())
            Text(player.nickname).font(.subheadline).lineLimit(2)
            Spacer(minLength: 6)
            Text("\(player.score) 分").font(.headline).monospacedDigit().foregroundStyle(Design.accent).fixedSize()
        }.padding(.vertical, 4)
    }
    private func request(_ kind: String, page: Int) async throws -> APIValue {
        try await account.api.request("/v1/match/against/\(kind)/\(match.id)", form: ["backup": match.isBackup ? "true" : "false", "page": String(page), "limit": "20"], token: account.session?.token)
    }
    private func load(reset: Bool) async {
        if !reset, loading || !hasMore { return }
        if reset { generation = UUID(); players = []; current = nil; roundTitle = nil; knockout = []; page = 0; hasMore = false }
        let version = generation; let next = page + 1
        loading = true; error = nil
        defer { if generation == version { loading = false } }
        do {
            if reset, !isLive {
                // The overview may omit personal results; the paged standings contain the authoritative currentUser.
                if let overview = try? await request("resultview", page: 1), version == generation {
                    roundTitle = overview["againstSwissTitle"].text
                    knockout = KnockoutRound.parse(overview["againstResultOff"])
                    current = MatchResultPlayer(overview["currentUser"])
                }
            }
            let data: APIValue
            if isLive {
                data = try await account.fetchAuthenticated("/v1/match/against/swiss/rank/" + match.id,
                    form: ["backup": "false", "page": String(next), "limit": "20", "round": selectedRound], method: "POST")
            } else { data = try await request("resultswiss", page: next) }
            try Task.checkCancellation()
            guard version == generation else { return }
            if isLive {
                roundChoices = SwissRankRound.parse(data["filter"])
                if selectedRound.isEmpty { selectedRound = data["selectFilter"]["rounds"].text ?? roundChoices.last?.id ?? "" }
                roundTitle = data["selectFilter"]["title"].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? roundChoices.first { $0.id == selectedRound }?.title
            }
            guard let rows = data["againstResultSwiss"].values ?? (data["count"].int == 0 ? [] : nil) else { throw APIError.invalidResponse }
            let parsed = rows.compactMap(MatchResultPlayer.init)
            guard parsed.count == rows.count else { throw APIError.invalidResponse }
            var seen = Set(players.map(\.id))
            players += parsed.filter { seen.insert($0.id).inserted }
            current = MatchResultPlayer(data["currentUser"]) ?? current
            total = data["count"].int ?? players.count
            page = next; hasMore = rows.count == 20 && players.count < total
        } catch is CancellationError { }
        catch { if version == generation { self.error = error.localizedDescription } }
    }
}

struct DuelResult: Identifiable, Sendable {
    let id: String
    let submissionID: String?
    let aName: String
    let bName: String
    let aResult: Int
    let bResult: Int
    let aUser: String?
    let bUser: String?
    let table: String?
    let finished: Bool
    let aAvatar: URL?
    let bAvatar: URL?
    let statusText: String?
    let statusID: Int?
    func belongs(to playerIDs: Set<String>) -> Bool {
        [aUser, bUser].compactMap { $0 }.contains { playerIDs.contains($0) }
    }
    init?(_ row: APIValue, key: String, finished: Bool? = nil) {
        let aID = row["a_id"].text ?? row["a_user_id"].text
        let bID = row["b_id"].text ?? row["b_user_id"].text
        let a = row["anickname"].text ?? row["a_nickname"].text
        let b = row["bnickname"].text ?? row["b_nickname"].text
        guard a != nil || b != nil || aID.flatMap(Int.init).map({ $0 > 0 }) == true || bID.flatMap(Int.init).map({ $0 > 0 }) == true else { return nil }
        id = row["id"].text ?? key
        submissionID = row["id"].text.flatMap { Int($0).map { $0 > 0 } == true ? $0 : nil }
        aName = a ?? (aID == "0" ? "轮空" : "未命名选手")
        bName = b ?? (bID == "0" ? "轮空" : "未命名选手")
        aAvatar = (row["a_avatar"].text ?? row["aavatar"].text).flatMap(URL.init(string:))
        bAvatar = (row["b_avatar"].text ?? row["bavatar"].text).flatMap(URL.init(string:))
        statusText = row["status_view"].text?.replacingOccurrences(of: "成绩", with: "对局")
        statusID = row["status_id"].int
        aResult = row["aresult"].int ?? row["a_result"].int ?? 0
        bResult = row["bresult"].int ?? row["b_result"].int ?? 0
        aUser = aID; bUser = bID
        table = row["desk_name"].text ?? row["desk_num"].text.map { "第\($0)桌" }
        self.finished = finished ?? row["status_id"].int.map { $0 >= 3 } ?? (aResult != 0 && bResult != 0)
    }
    static func resultTitle(_ result: Int) -> String {
        switch result { case 1: "胜"; case 2: "平"; case 3: "负"; case 4: "双败"; default: "待填报" }
    }
    static func resultSymbol(_ result: Int) -> String {
        switch result {
        case 1: "trophy.fill"
        case 2: "equal.circle.fill"
        case 3: "flag.fill"
        case 4: "flag.2.crossed.fill"
        default: "clock.fill"
        }
    }
    static func resultColor(_ result: Int) -> Color {
        switch result { case 1: .green; case 2: .blue; case 3: .primary; case 4: .red; default: .secondary }
    }
}
struct KnockoutRound: Identifiable, Sendable {
    let id: String
    let title: String
    let games: [DuelResult]
    static func parse(_ data: APIValue) -> [KnockoutRound] {
        (data.values ?? []).enumerated().compactMap { index, row in
            guard let title = row["title"].text, let rows = row["result"].values else { return nil }
            let games = rows.enumerated().compactMap { DuelResult($0.element, key: "\(index)-\($0.offset)", finished: true) }
            return games.isEmpty ? nil : KnockoutRound(id: String(index), title: title, games: games)
        }
    }
}
struct DuelResultRow: View {
    let game: DuelResult
    var viewerIDs: Set<String> = []
    private var statusColor: Color {
        switch game.statusID {
        case 1: .orange
        case 2: .blue
        case 3: .green
        case 4: .red
        default: .secondary
        }
    }
    private var ownResult: Int? {
        if viewerIDs.contains(game.aUser ?? "") { return game.aResult }
        if viewerIDs.contains(game.bUser ?? "") { return game.bResult }
        return nil
    }
    private var outcome: (icon: String, title: String, color: Color) {
        if !game.finished { return ("bolt.horizontal.circle.fill", "对局中", .orange) }
        if let ownResult {
            guard (1...4).contains(ownResult) else { return ("clock.fill", "待确认", .secondary) }
            return (DuelResult.resultSymbol(ownResult), DuelResult.resultTitle(ownResult), DuelResult.resultColor(ownResult))
        }
        let result = game.aResult == 4 ? 4 : 2
        return (DuelResult.resultSymbol(result), DuelResult.resultTitle(result), DuelResult.resultColor(result))
    }
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Color.clear.frame(maxWidth: .infinity).frame(height: 1)
                Text(game.table ?? "对局").font(.caption.weight(.medium)).fixedSize()
                Text(game.statusText ?? (game.finished ? "已结束" : "进行中"))
                    .font(.caption2.weight(.medium)).foregroundStyle(statusColor)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(statusColor.opacity(0.13), in: Capsule())
                    .fixedSize().frame(maxWidth: .infinity, alignment: .trailing)
            }.foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 10) {
                player(game.aName, avatar: game.aAvatar)
                VStack(spacing: 9) {
                    if game.finished, ownResult == nil {
                        HStack(spacing: 12) {
                            resultIcon(game.aResult, player: game.aName)
                            resultIcon(game.bResult, player: game.bName)
                        }
                    } else {
                        Image(systemName: outcome.icon).font(.system(size: 30, weight: .semibold))
                        Text(outcome.title).font(.caption.weight(.semibold))
                    }
                }.foregroundStyle(outcome.color).frame(width: 70).padding(.top, 12)
                player(game.bName, avatar: game.bAvatar)
            }
        }.padding(.vertical, 14).accessibilityElement(children: .combine).accessibilityIdentifier("duel.row.\(game.id)")
    }
    private func resultIcon(_ result: Int, player: String) -> some View {
        return Image(systemName: DuelResult.resultSymbol(result))
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(DuelResult.resultColor(result))
            .accessibilityLabel("\(player)：\(DuelResult.resultTitle(result))")
    }
    private func player(_ name: String, avatar: URL?) -> some View {
        VStack(spacing: 8) {
            AsyncImage(url: avatar) { image in image.resizable().scaledToFill() } placeholder: {
                Image(systemName: "person.fill").resizable().scaledToFit().padding(14).foregroundStyle(.secondary)
            }.frame(width: 52, height: 52).background(Color.secondary.opacity(0.1), in: Circle()).clipShape(Circle())
            Text(name).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center).lineLimit(3)
        }.frame(maxWidth: .infinity, minHeight: 106, alignment: .top)
    }
}

enum SubmittedGrade: Int, CaseIterable, Identifiable {
    case win = 1, draw = 2, lose = 3
    var id: Int { rawValue }
    var title: String { switch self { case .win: "胜"; case .lose: "负"; case .draw: "平" } }
    var icon: String { DuelResult.resultSymbol(rawValue) }
    var color: Color { DuelResult.resultColor(rawValue) }
}

struct MatchGradeTarget: Identifiable {
    let game: DuelResult
    let roundTitle: String
    let stage: String
    let submission: MatchGradeSubmission
    var id: String { game.id }
    static func isEligible(game: DuelResult, viewerIDs: Set<String>, status: Int, backup: Bool, stage: String) -> Bool {
        guard [3, 4].contains(status), !backup, stage == "4",
              game.statusID == 1, !game.finished, game.submissionID != nil,
              Int(game.aUser ?? "").map({ $0 > 0 }) == true,
              Int(game.bUser ?? "").map({ $0 > 0 }) == true else { return false }
        if viewerIDs.contains(game.aUser ?? "") { return game.aResult == 0 }
        if viewerIDs.contains(game.bUser ?? "") { return game.bResult == 0 }
        return false
    }
}

@Observable @MainActor
final class MatchGradeSubmission {
    enum Phase: Equatable { case idle, submitting, submitted, uncertain, failed }
    private(set) var phase: Phase = .idle
    private(set) var message: String?
    var canSubmit: Bool { phase == .idle || phase == .failed }
    func submit(_ send: () async throws -> Void) async {
        guard canSubmit else { return }
        phase = .submitting; message = nil
        do {
            try await send()
            phase = .submitted; message = "成绩已提交，等待确认。"
        } catch let error as APIError {
            if case .business = error {
                phase = .failed; message = error.localizedDescription
            } else if error.requiresLogin {
                phase = .failed; message = error.localizedDescription
            } else {
                phase = .uncertain; message = "暂时无法确认提交结果，请刷新对局核对成绩。"
            }
        } catch {
            phase = .uncertain; message = "暂时无法确认提交结果，请刷新对局核对成绩。"
        }
    }
}

struct MatchGradeSheet: View {
    let target: MatchGradeTarget
    let submission: MatchGradeSubmission
    let submit: (SubmittedGrade) async -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var grade: SubmittedGrade?
    @State private var confirming = false
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 4) {
                    Text("提交成绩").font(.title3.weight(.semibold)).accessibilityIdentifier("match.grade.title")
                    Text([target.roundTitle, target.game.table].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    ForEach(SubmittedGrade.allCases) { result in
                        Button { grade = result } label: {
                            VStack(spacing: 10) {
                                Image(systemName: result.icon).font(.system(size: 28, weight: .semibold)).foregroundStyle(result.color)
                                Text(result.title).font(.headline).foregroundStyle(.primary)
                            }.frame(maxWidth: .infinity, minHeight: 88)
                                .background(grade == result ? Design.accent.opacity(0.12) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                                .overlay { RoundedRectangle(cornerRadius: 16).stroke(grade == result ? Design.accent : .clear, lineWidth: 2) }
                                .contentShape(RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain).disabled(!submission.canSubmit)
                            .accessibilityLabel(result.title)
                            .accessibilityAddTraits(grade == result ? .isSelected : [])
                            .accessibilityIdentifier("match.grade.option.\(result.rawValue)")
                    }
                }
                if let message = submission.message {
                    Label(message, systemImage: submission.phase == .submitted ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(submission.phase == .submitted ? Color.green : Color.secondary)
                        .accessibilityIdentifier("match.grade.message")
                }
                if submission.phase == .submitting { ProgressView("正在提交成绩") }
                HStack(spacing: 12) {
                    Button { dismiss() } label: { Text("取消").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                        .disabled(submission.phase == .submitting)
                        .accessibilityIdentifier("match.grade.cancel")
                    Button { confirming = true } label: { Text("提交").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                        .disabled(grade == nil || !submission.canSubmit)
                        .accessibilityIdentifier("match.grade.confirm")
                }.controlSize(.large)
                Text("请按自己的对局结果填报，确认无误后提交。")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(.horizontal, 24).padding(.vertical, 20)
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(submission.message == nil ? 340 : 400), .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(submission.phase == .submitting)
        .onChange(of: submission.phase) { _, phase in
            if phase == .submitted { dismiss() }
        }
        .alert("确认提交我的成绩：\(grade?.title ?? "")？", isPresented: $confirming) {
            if let grade { Button("确认提交：\(grade.title)") { Task { await submit(grade) } } }
            Button("取消", role: .cancel) { }
        } message: { Text("\(target.roundTitle) · \(target.game.table ?? "对局")") }
    }
}
struct DuelRound: Identifiable {
    let id: String
    let title: String
    let round: String
    let stage: String
    var games: [DuelResult]
    var page: Int
    var total: Int
}

struct MatchPairingsSection: View {
    let match: MatchItem
    let status: Int
    var refreshVersion = UUID()
    @Environment(AccountStore.self) private var account
    @State private var rounds: [DuelRound] = []
    @State private var expanded = Set<String>()
    @State private var loading = false
    @State private var loadingRound: String?
    @State private var error: String?
    @State private var generation = UUID()
    @State private var didLoad = false
    @Binding var gradeTarget: MatchGradeTarget?
    @Binding var submissions: [String: MatchGradeSubmission]
    private var viewerIDs: Set<String> { Set([account.profile?.displayID, account.session?.userID].compactMap { $0 }) }
    private func displayedGames(in round: DuelRound) -> [DuelResult] {
        round.games.filter { round.stage != "4" || $0.belongs(to: viewerIDs) }
    }
    private var ongoing: [DuelResult] { rounds.flatMap { displayedGames(in: $0) }.filter { !$0.finished } }
    private var visibleRounds: [DuelRound] {
        rounds.filter { round in
            let games = displayedGames(in: round)
            if round.stage == "4", !games.isEmpty, !games.contains(where: \.finished) { return false }
            return games.isEmpty || games.contains(where: \.finished) || round.page * 30 < round.total
        }
    }
    var body: some View {
        if !ongoing.isEmpty {
            Section("进行中的对局") {
                ForEach(ongoing) { game in
                    VStack {
                        DuelResultRow(game: game, viewerIDs: viewerIDs)
                        if let round = rounds.first(where: { $0.games.contains(where: { $0.id == game.id }) }),
                           MatchGradeTarget.isEligible(game: game, viewerIDs: viewerIDs, status: status, backup: match.isBackup, stage: round.stage) {
                            Button(submissions[game.id]?.phase == .submitted ? "成绩已提交" : submissions[game.id]?.phase == .uncertain ? "核对提交状态" : "提交成绩") {
                                if submissions[game.id] == nil { submissions[game.id] = MatchGradeSubmission() }
                                if let submission = submissions[game.id] {
                                    gradeTarget = MatchGradeTarget(game: game, roundTitle: round.title, stage: round.stage, submission: submission)
                                }
                            }.buttonStyle(.borderedProminent).controlSize(.regular)
                                .accessibilityIdentifier("match.grade.open.\(game.id)")
                        }
                    }
                }
            }
        }
        ForEach(visibleRounds) { round in
            Section {
                Button {
                    if expanded.contains(round.id) { expanded.remove(round.id) } else { expanded.insert(round.id) }
                } label: {
                    HStack {
                        Text(round.title).font(.headline)
                        Spacer()
                        Image(systemName: expanded.contains(round.id) ? "chevron.up" : "chevron.down").font(.caption)
                    }.foregroundStyle(Design.ink).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("duel.round.\(round.id)")
                if expanded.contains(round.id) {
                    ForEach(displayedGames(in: round).filter(\.finished)) { DuelResultRow(game: $0, viewerIDs: viewerIDs) }
                    if displayedGames(in: round).isEmpty {
                        Text(round.stage == "4" ? "暂无我的对局" : "暂无对局").foregroundStyle(.secondary)
                    }
                    if round.page * 30 < round.total {
                        Button("加载更多对局") { Task { await loadMore(round.id) } }.disabled(loadingRound != nil)
                    }
                }
            }
        }
        Section {
            if loading { ProgressView("正在读取对局") }
            if let error { Text(error).foregroundStyle(.secondary); Button("重新查询") { Task { await load() } } }
            if !loading, error == nil, rounds.isEmpty { Text("暂无对局记录").foregroundStyle(.secondary) }
        }.onAppear {
            guard !didLoad else { return }
            didLoad = true
            Task { await load() }
        }.onChange(of: account.sessionVersion) { _, _ in
            gradeTarget = nil; submissions = [:]; generation = UUID(); rounds = []
            Task { await load() }
        }
        .onChange(of: refreshVersion) { _, _ in Task { await load() } }
    }
    private func request(round: String, stage: String, page: Int) async throws -> APIValue {
        try await account.fetchAuthenticated("/v1/match/against/index/" + match.id, form: ["backup": match.isBackup ? "true" : "false", "page": String(page), "limit": "30", "search_id":"", "round":round, "status_id":stage, "grade_type":"0"], method:"POST")
    }
    static func parse(_ data: APIValue) throws -> [DuelResult] {
        guard let rows = data["res"].values else { throw APIError.invalidResponse }
        return try rows.enumerated().map { index, row in
            guard let game = DuelResult(row, key:String(index)) else { throw APIError.invalidResponse }
            return game
        }
    }
    // Swiss rounds show only the viewer's games, so filtering page one is insufficient.
    static func personalRoundPages(first: APIValue, viewerIDs: Set<String>, fetch: (Int) async throws -> APIValue) async throws -> (games: [DuelResult], page: Int) {
        var games = try parse(first)
        var page = 1
        var total = first["count"].int ?? 0
        var seen = Set(games.map(\.id))
        while page * 30 < total && !games.contains(where: { $0.belongs(to: viewerIDs) }) {
            try Task.checkCancellation()
            let data = try await fetch(page + 1)
            let next = try parse(data)
            page += 1
            total = data["count"].int ?? total
            games += next.filter { seen.insert($0.id).inserted }
            if next.isEmpty { break }
        }
        return (games, page)
    }
    private func load() async {
        guard account.isLoggedIn else { error = "登录后查看比赛对局"; return }
        let version = UUID(); generation = version; rounds = []; loading = true; error = nil
        defer { if generation == version { loading = false } }
        do {
            let first = try await request(round:"", stage:"", page:1)
            let filters = first["filter"].values ?? []
            let selected = first["selectFilter"]
            let list = filters.isEmpty ? [selected] : filters
            for filter in list {
                try Task.checkCancellation()
                guard version == generation else { return }
                guard let round = filter["rounds"].text, let stage = filter["statusId"].text else { throw APIError.invalidResponse }
                let data: APIValue
                if round == selected["rounds"].text, stage == selected["statusId"].text { data = first }
                else { data = try await request(round:round, stage:stage, page:1) }
                guard version == generation else { return }
                let id = stage + "-" + round
                let result: (games: [DuelResult], page: Int)
                if stage == "4" {
                    result = try await Self.personalRoundPages(first: data, viewerIDs: viewerIDs) { page in
                        try await request(round: round, stage: stage, page: page)
                    }
                } else { result = (try Self.parse(data), 1) }
                guard version == generation else { return }
                rounds.append(DuelRound(id:id, title:filter["title"].text?.trimmingCharacters(in:.whitespacesAndNewlines) ?? "第\(round)轮", round:round, stage:stage, games:result.games, page:result.page, total:data["count"].int ?? 0))
                expanded.insert(id)
            }
        } catch is CancellationError { }
        catch { if version == generation { self.error = error.localizedDescription } }
    }
    private func loadMore(_ id: String) async {
        guard loadingRound == nil, let old = rounds.first(where: { $0.id == id }) else { return }
        let version = generation; loadingRound = id
        defer { loadingRound = nil }
        do {
            let data = try await request(round:old.round, stage:old.stage, page:old.page+1)
            guard version == generation, let index = rounds.firstIndex(where: { $0.id == id }) else { return }
            var seen = Set(old.games.map(\.id))
            rounds[index].games += try Self.parse(data).filter { seen.insert($0.id).inserted }
            rounds[index].page += 1
        } catch { if version == generation { self.error = error.localizedDescription } }
    }
}
