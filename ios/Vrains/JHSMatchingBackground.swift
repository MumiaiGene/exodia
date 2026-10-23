import BackgroundTasks
import Foundation
import Observation
import OSLog
import UIKit
import UserNotifications

@MainActor protocol JHSMatchBackgroundManaging:AnyObject {
    func request(id:UUID,title:String,ready:@escaping @MainActor (String?)->Void,expired:@escaping @MainActor ()->Void)
    func protected(_ id:UUID)->Bool
    func update(id:UUID,completed:Int64,total:Int64,subtitle:String)
    func finish(id:UUID,success:Bool)
    func cancel(id:UUID)
}

@MainActor final class JHSMatchBackgroundCoordinator:JHSMatchBackgroundManaging {
    static let shared=JHSMatchBackgroundCoordinator()
    static let prefix="app.vrains.ios.jhs.match."
    private final class Entry {
        let identifier:String
        var task:BGTask?
        init(_ identifier:String){self.identifier=identifier}
    }
    private var entries:[UUID:Entry]=[:]
    func request(id:UUID,title:String,ready:@escaping @MainActor (String?)->Void,expired:@escaping @MainActor ()->Void) {
        cancel(id:id)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting"),!ProcessInfo.processInfo.arguments.contains("--uitesting-jhs-system-background") {
            ready(nil);return
        }
        #endif
        guard #available(iOS 26.0,*) else{ready("此系统使用有限后台时间，暂停后可继续匹配");return}
        let identifier=Self.prefix+id.uuidString+"-"+UUID().uuidString
        let entry=Entry(identifier);entries[id]=entry
        // Exact identifiers avoid depending on wildcard handler dispatch. Info.plist permits this prefix.
        let registered=BGTaskScheduler.shared.register(forTaskWithIdentifier:identifier,using:.main){[weak self] task in
            Task{@MainActor in
                guard let self,self.entries[id] === entry,let continued=task as? BGContinuedProcessingTask else{task.setTaskCompleted(success:false);return}
                entry.task=continued
                continued.progress.totalUnitCount=1000
                continued.progress.completedUnitCount=0
                continued.expirationHandler={Task{@MainActor in
                    guard self.entries[id] === entry else{return}
                    expired()
                }}
                ready(nil)
            }
        }
        guard registered else{entries[id]=nil;ready("系统未允许持续后台处理，当前在前台匹配");return}
        let request=BGContinuedProcessingTaskRequest(identifier:identifier,title:"预购清单匹配",subtitle:title)
        request.strategy = .queue
        Task {
            do {
                if #available(iOS 27.0,*) {try await BGTaskScheduler.shared.submitTaskRequest(request)}
                else {try BGTaskScheduler.shared.submit(request)}
            } catch {
                Logger(subsystem:"app.vrains.ios",category:"JHSBackground").error("Continued task submission failed: \(String(describing:error),privacy:.public)")
                guard entries[id] === entry,entry.task==nil else{return}
                entries[id]=nil
                ready("持续后台请求未获准，当前在前台匹配")
            }
        }
    }
    func protected(_ id:UUID)->Bool {entries[id]?.task != nil}
    func update(id:UUID,completed:Int64,total:Int64,subtitle:String) {
        guard #available(iOS 26.0,*),let task=entries[id]?.task as? BGContinuedProcessingTask else{return}
        task.progress.totalUnitCount=max(1,total)
        task.progress.completedUnitCount=max(task.progress.completedUnitCount,min(completed,total-1))
        task.updateTitle("预购清单匹配",subtitle:subtitle)
    }
    func finish(id:UUID,success:Bool) {
        guard let entry=entries.removeValue(forKey:id) else{return}
        if let task=entry.task {
            task.expirationHandler=nil
            if #available(iOS 26.0,*),success,let continued=task as? BGContinuedProcessingTask {continued.progress.completedUnitCount=continued.progress.totalUnitCount}
            task.setTaskCompleted(success:success)
        } else {BGTaskScheduler.shared.cancel(taskRequestWithIdentifier:entry.identifier)}
    }
    func cancel(id:UUID){finish(id:id,success:false)}
}

struct JHSMatchNotificationRoute:Identifiable {let id:UUID}

@MainActor protocol JHSMatchNotifying:AnyObject {func deliver(_ job:JHSMatchJob) async}

@MainActor protocol JHSNotificationDelivery:AnyObject {
    func status() async -> UNAuthorizationStatus
    func authorize() async throws -> Bool
    func add(_ request:UNNotificationRequest) async throws
}
@MainActor final class JHSSystemNotificationDelivery:JHSNotificationDelivery {
    private let center=UNUserNotificationCenter.current()
    func status() async -> UNAuthorizationStatus {await center.notificationSettings().authorizationStatus}
    func authorize() async throws -> Bool {try await center.requestAuthorization(options:[.alert,.sound,.badge])}
    func add(_ request:UNNotificationRequest) async throws {try await center.add(request)}
}

@Observable @MainActor final class JHSMatchNotifications:NSObject,JHSMatchNotifying,UNUserNotificationCenterDelegate {
    static let shared=JHSMatchNotifications()
    static let category="JHS_MATCH_RESULT"
    nonisolated static let jobKey="jhsMatchJobID"
    var pendingJobID:UUID?
    private(set) var permissionDenied=false
    private var permissionTask:Task<Void,Never>?
    private let center=UNUserNotificationCenter.current()
    private let delivery:any JHSNotificationDelivery
    init(delivery:any JHSNotificationDelivery=JHSSystemNotificationDelivery()) {self.delivery=delivery;super.init()}
    private var isolatedTest:Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--uitesting") && !ProcessInfo.processInfo.arguments.contains("--uitesting-jhs-system-background")
        #else
        false
        #endif
    }
    func configure(){
        center.delegate=self
        Task{permissionDenied=await delivery.status() == .denied}
    }
    func requestPermission() {
        guard !isolatedTest,permissionTask==nil else{return}
        permissionTask=Task {
            defer{permissionTask=nil}
            let status=await delivery.status()
            if status == .notDetermined {
                do{permissionDenied = !(try await delivery.authorize())}
                catch{permissionDenied=true}
            } else {permissionDenied=status == .denied}
        }
    }
    static func content(for job:JHSMatchJob)->UNMutableNotificationContent? {
        let content=UNMutableNotificationContent()
        switch job.status {
        case .completed,.partial:
            content.title="匹配完成"
            content.body=job.plans.isEmpty ? "没有符合条件的购买方案。":"找到 \(job.plans.count) 种购买方案。"
            if job.hasGaps{content.body+="部分店铺查询失败，点击查看结果。"}
        case .failed:content.title="匹配失败";content.body="未能完成匹配，点击查看原因。"
        case .paused:content.title="匹配已暂停";content.body="系统后台处理已停止，进度已保存，点击继续匹配。"
        default:return nil
        }
        content.body+="\n"+job.title+" · "+job.elapsedLabel(at:.now)
        content.sound = .default
        content.categoryIdentifier=category
        content.threadIdentifier="jhs.match"
        content.userInfo=[jobKey:job.id.uuidString]
        return content
    }
    func deliver(_ job:JHSMatchJob) async {
        guard !isolatedTest,let content=Self.content(for:job) else{return}
        await permissionTask?.value
        let status=await delivery.status()
        guard [.authorized,.provisional,.ephemeral].contains(status) else{permissionDenied=status == .denied;return}
        let request=UNNotificationRequest(identifier:"jhs.match.\(job.id).\(job.status == .paused ? "paused":"result")",content:content,trigger:nil)
        do{try await delivery.add(request)}catch{ /* Notification delivery never changes a saved match result. */ }
    }
    func open(userInfo:[AnyHashable:Any]) {
        guard let raw=userInfo[Self.jobKey] as? String,let id=UUID(uuidString:raw) else{return}
        pendingJobID=id
    }
    nonisolated func userNotificationCenter(_ center:UNUserNotificationCenter,didReceive response:UNNotificationResponse,withCompletionHandler completionHandler:@escaping ()->Void) {
        let raw=response.notification.request.content.userInfo[Self.jobKey] as? String
        if response.actionIdentifier==UNNotificationDefaultActionIdentifier,let raw,let id=UUID(uuidString:raw) {
            Task{@MainActor in self.pendingJobID=id}
        }
        completionHandler()
    }
    nonisolated func userNotificationCenter(_ center:UNUserNotificationCenter,willPresent notification:UNNotification,withCompletionHandler completionHandler:@escaping (UNNotificationPresentationOptions)->Void) {
        completionHandler([.banner,.sound,.list])
    }
}

@MainActor final class JHSMatchAppDelegate:NSObject,UIApplicationDelegate {
    func application(_ application:UIApplication,didFinishLaunchingWithOptions launchOptions:[UIApplication.LaunchOptionsKey:Any]?=nil)->Bool {
        JHSMatchNotifications.shared.configure()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting-jhs-open-notification"),let job=JHSMatchJobsStore.shared.jobs.first {
            JHSMatchNotifications.shared.open(userInfo:[JHSMatchNotifications.jobKey:job.id.uuidString])
        }
        #endif
        return true
    }
}
