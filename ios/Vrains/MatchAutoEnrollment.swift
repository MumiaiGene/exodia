import SwiftUI
import UserNotifications

struct ScheduledMatchEnrollment: Codable, Identifiable {
    enum Status: String, Codable {
        case waiting, checking, submitting, succeeded, attention, cancelled
        var title: String {
            switch self {
            case .waiting: "等待开放"
            case .checking: "正在检查"
            case .submitting: "正在报名"
            case .succeeded: "已报名"
            case .attention: "需要处理"
            case .cancelled: "已取消自动报名"
            }
        }
    }
    var id: String { userID + ":" + matchID }
    let userID: String
    let matchID: String
    var name: String
    var opensAt: Date
    var status: Status = .waiting
    var submitted = false
    var message: String?
    var nextCheck: Date = .distantPast
}

/// Shares a dispatch fence with manual enrollment. An ambiguous request stays fenced
/// until the process exits; the persisted scheduled job also prevents replay after relaunch.
@MainActor enum MatchEnrollmentFence {
    static var dispatched = Set<String>()
    static func claim(userID: String, matchID: String) throws {
        guard dispatched.insert(userID + ":" + matchID).inserted else {
            throw APIError.business(0, "已提交过报名，请先刷新核对结果，勿重复提交。")
        }
    }
    static func release(userID: String, matchID: String) {
        dispatched.remove(userID + ":" + matchID)
    }
}

@Observable @MainActor final class MatchAutoEnrollmentStore {
    static let shared = MatchAutoEnrollmentStore()
    private(set) var jobs: [ScheduledMatchEnrollment] = []
    var error: String?
    var notificationMessage: String?
    var showsSchedules = false
    private(set) var isActive = false
    private var busy = false
    private var storageFailed = false
    private var verifiedOnActivation = Set<String>()
    private var clockCheckedAt = Date.distantPast
    private var serverOffset: TimeInterval = 0
    private let file: URL
    private let notifications = UNUserNotificationCenter.current()
    init(file: URL? = nil) {
        self.file = file ?? URL.applicationSupportDirectory.appendingPathComponent("scheduled-enrollments.json")
        do {
            if FileManager.default.fileExists(atPath: self.file.path) {
                jobs = try JSONDecoder().decode([ScheduledMatchEnrollment].self, from: Data(contentsOf: self.file))
                for i in jobs.indices {
                    if jobs[i].submitted { MatchEnrollmentFence.dispatched.insert(jobs[i].id) }
                    if jobs[i].status == .checking { jobs[i].status = .waiting }
                    if jobs[i].status == .submitting {
                        jobs[i].status = .attention
                        jobs[i].message = "报名曾经提交，等待核对结果，不会重复报名。"
                    }
                }
            }
        } catch { storageFailed = true; self.error = "无法读取自动报名记录，已停止自动执行。" }
    }
    func job(matchID: String, userID: String?) -> ScheduledMatchEnrollment? {
        jobs.first { $0.matchID == matchID && $0.userID == userID }
    }
    private func save() throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(jobs).write(to: file, options: .atomic)
    }
    func setActive(_ active: Bool) {
        if active != isActive { verifiedOnActivation = []; clockCheckedAt = .distantPast }
        isActive = active
        if !active { UIApplication.shared.isIdleTimerDisabled = false }
    }
    func schedule(_ detail: MatchDetail, account: AccountStore) async {
        guard !storageFailed else { return }
        guard let userID = account.session?.userID else { error = "请先登录一起来决斗。"; return }
        guard !detail.backup, detail.statusID == 2, !detail.hasParticipated,
              !detail.isFrozen, detail.errorCode == 0, !detail.onlinePayment,
              !detail.requiresDeck, !detail.hasOrder,
              let text = detail.signupStartsAt, let date = ISO8601DateFormatter().date(from: text), date > .now else {
            error = "仅支持尚未开放、无需线上支付和提交卡组的比赛。"; return
        }
        if let old = job(matchID: detail.id, userID: userID), old.submitted { return }
        let new = ScheduledMatchEnrollment(userID: userID, matchID: detail.id, name: detail.name, opensAt: date)
        let previous = jobs
        error = nil
        jobs.removeAll { $0.id == new.id }; jobs.append(new)
        do { try save() } catch { jobs = previous; self.error = "自动报名未保存，请重试。"; return }
        await scheduleReminder(new)
    }
    func cancel(_ id: String) {
        guard let i = jobs.firstIndex(where: { $0.id == id }), !jobs[i].submitted else { return }
        let old = jobs[i]
        jobs[i].status = .cancelled
        do { try save(); removeReminder(old) }
        catch { jobs[i] = old; self.error = "取消未保存，请重试。" }
    }
    func recordManualDispatch(matchID: String, userID: String?) throws {
        guard let job = job(matchID: matchID, userID: userID),
              [.waiting, .checking].contains(job.status), !job.submitted else { return }
        try update(job.id) { $0.status = .submitting; $0.submitted = true }
    }
    private func removeReminder(_ job: ScheduledMatchEnrollment) {
        notifications.removePendingNotificationRequests(withIdentifiers: ["enrollment." + job.id + ".before", "enrollment." + job.id + ".open"])
    }
    private func scheduleReminder(_ job: ScheduledMatchEnrollment) async {
        do {
            guard try await notifications.requestAuthorization(options: [.alert, .sound]) else {
                notificationMessage = "通知未开启，请自行在开放前打开 App。"; return
            }
            removeReminder(job)
            for (suffix, offset) in [("before", -120.0), ("open", 0.0)] {
                let time = job.opensAt.addingTimeInterval(offset).timeIntervalSinceNow
                guard time > 0 else { continue }
                let content = UNMutableNotificationContent()
                content.title = suffix == "before" ? "报名即将开放" : "报名已到开放时间"
                content.body = job.name + "。请打开 Vrains 并保持前台，自动报名才会执行。"
                content.sound = .default
                content.userInfo = ["matchAutoEnrollment": true]
                try await notifications.add(UNNotificationRequest(identifier: "enrollment." + job.id + "." + suffix, content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, time), repeats: false)))
            }
        } catch { notificationMessage = "提醒设置失败，请自行在开放前打开 App。" }
    }
    private func update(_ id: String, _ change: (inout ScheduledMatchEnrollment) -> Void) throws {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[i]); try save()
    }
    func tick(account: AccountStore, now: Date = .now) async {
        UIApplication.shared.isIdleTimerDisabled = isActive && jobs.contains {
            $0.userID == account.session?.userID && [.waiting, .checking, .submitting].contains($0.status)
                && abs($0.opensAt.timeIntervalSince(now)) <= 120
        }
        guard isActive, !busy, !storageFailed, let session = account.session else { return }
        busy = true; defer { busy = false }
        if now.timeIntervalSince(clockCheckedAt) > 30, jobs.contains(where: {
            $0.userID == session.userID && $0.status == .waiting && abs($0.opensAt.timeIntervalSince(now)) <= 600
        }) {
            let serverDate = await account.api.serverDate()
            serverOffset = serverDate.timeIntervalSinceNow
            clockCheckedAt = now
        }
        let serverNow = now.addingTimeInterval(serverOffset)
        for job in jobs where job.userID == session.userID {
            guard isActive, session.token == account.session?.token else { return }
            if job.submitted && job.status != .succeeded && !verifiedOnActivation.contains(job.id) {
                verifiedOnActivation.insert(job.id)
                await reconcile(job, account: account)
            } else if job.status == .waiting, job.nextCheck <= serverNow, job.opensAt <= serverNow {
                await attempt(job, account: account, now: serverNow)
            }
        }
    }
    private func reconcile(_ job: ScheduledMatchEnrollment, account: AccountStore) async {
        let version = account.sessionVersion
        do {
            let detail = try await account.api.matchDetail(id: job.matchID, backup: false, token: account.session?.token)
            guard version == account.sessionVersion else { return }
            if detail.hasParticipated {
                try update(job.id) { $0.status = .succeeded; $0.message = "服务器已确认报名成功。" }
                removeReminder(job)
            }
        } catch { /* Keep the durable uncertain state. Never replay signup. */ }
    }
    private func attempt(_ job: ScheduledMatchEnrollment, account: AccountStore, now: Date) async {
        let version = account.sessionVersion
        do {
            guard now.timeIntervalSince(job.opensAt) <= 600 else {
                try update(job.id) { $0.status = .attention; $0.message = "已错过自动报名窗口，请查看比赛详情。" }; return
            }
            try update(job.id) { $0.status = .checking }
            let detail = try await account.api.matchDetail(id: job.matchID, backup: false, token: account.session?.token)
            guard jobs.first(where: { $0.id == job.id })?.status != .cancelled else { return }
            guard version == account.sessionVersion, isActive else {
                try update(job.id) { $0.status = .waiting }; return
            }
            if detail.hasParticipated {
                try update(job.id) { $0.status = .succeeded; $0.message = "服务器已确认报名成功。" }; removeReminder(job); return
            }
            if let text = detail.signupStartsAt, let date = ISO8601DateFormatter().date(from: text), date > now {
                try update(job.id) { $0.opensAt = date; $0.status = .waiting }
                if let updated = jobs.first(where: { $0.id == job.id }) { await scheduleReminder(updated) }
                return
            }
            guard !detail.onlinePayment, !detail.requiresDeck, !detail.hasOrder, !detail.backup,
                  detail.statusID == 2, !detail.isFrozen, detail.errorCode == 0, !detail.isFull else {
                try update(job.id) { $0.status = .attention; $0.message = "比赛已满、关闭或报名条件发生变化，请查看详情。" }; return
            }
            if detail.awaitingOpening() {
                try update(job.id) { $0.status = .waiting; $0.nextCheck = now.addingTimeInterval(2) }; return
            }
            let enrollment = MatchEnrollment()
            await enrollment.run(detail: detail, account: account, beforeDispatch: {
                guard self.isActive, version == account.sessionVersion,
                      self.jobs.first(where: { $0.id == job.id })?.status != .cancelled else { throw CancellationError() }
                // Persist before any signup traffic. Failure must stop dispatch.
                try self.update(job.id) { $0.status = .submitting; $0.submitted = true }
            })
            guard version == account.sessionVersion else { return }
            try update(job.id) {
                guard $0.status != .cancelled else { return }
                $0.status = enrollment.completed ? .succeeded : .attention
                $0.message = enrollment.completed ? "服务器已确认报名成功。" : (enrollment.error ?? "请查看比赛详情。")
            }
            removeReminder(job)
        } catch {
            do {
                try update(job.id) {
                    guard $0.status != .cancelled else { return }
                    $0.status = $0.submitted ? .attention : .waiting
                    $0.nextCheck = now.addingTimeInterval(5)
                    $0.message = AccountStore.message(for: error)
                }
            } catch { storageFailed = true; self.error = "无法保存报名状态，自动执行已停止。" }
        }
    }
    /// Developer device launch can import explicitly requested matches without bundling personal defaults.
    func importLaunchRequests(account: AccountStore) async {
        guard account.isLoggedIn else { return }
        let args = ProcessInfo.processInfo.arguments
        let version = account.sessionVersion
        for (index, arg) in args.enumerated() where arg == "--schedule-match" && index + 1 < args.count {
            let id = args[index + 1]
            guard job(matchID: id, userID: account.session?.userID) == nil else { continue }
            do {
                let detail = try await account.api.matchDetail(id: id, backup: false, token: account.session?.token)
                guard version == account.sessionVersion else { return }
                await schedule(detail, account: account)
            } catch { self.error = AccountStore.message(for: error) }
        }
    }
}

struct MatchAutoEnrollmentScreen: View {
    @Environment(AccountStore.self) private var account
    @State private var scheduler = MatchAutoEnrollmentStore.shared
    var body: some View {
        List {
            Section {
                Text("开放前两分钟会提醒你。请提前打开 App 并保持前台，届时自动尝试报名；锁屏、后台或退出时无法保证执行。临近开放时会保持屏幕常亮。")
                Text("仅在服务器确认后显示已报名。报名结果不明时不会重复提交。")
            }.foregroundStyle(.secondary)
            if let error = scheduler.error { Section { Text(error).foregroundStyle(.red) } }
            if let message = scheduler.notificationMessage { Section { Text(message).foregroundStyle(.orange) } }
            let jobs = scheduler.jobs.filter { $0.userID == account.session?.userID }.sorted { $0.opensAt < $1.opensAt }
            if jobs.isEmpty { Section { Text("尚未安排自动报名。在待开放比赛的详情中添加。") } }
            ForEach(jobs) { job in
                Section {
                    Text(job.name).font(.headline)
                    if let match = try? MatchItem(data: .object(["id": .string(job.matchID), "name": .string(job.name)])) {
                        NavigationLink("查看比赛详情") { MatchSummaryScreen(match: match, kind: "比赛") }
                    }
                    LabeledContent("开放报名", value: job.opensAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("状态", value: job.status.title)
                    if let message = job.message { Text(message).foregroundStyle(.secondary) }
                    if [.waiting, .checking].contains(job.status), !job.submitted {
                        Button("取消自动报名", role: .destructive) { scheduler.cancel(job.id) }
                    }
                    if job.submitted, job.status == .attention {
                        Button("核对报名结果") {
                            scheduler.setActive(false); scheduler.setActive(true)
                            Task { await scheduler.tick(account: account) }
                        }
                    }
                }
            }
        }.navigationTitle("自动报名").navigationBarTitleDisplayMode(.inline)
    }
}
