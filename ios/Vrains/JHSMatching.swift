import Foundation
import Observation
import CryptoKit
import UIKit

struct JHSMatchRequest:Codable,Sendable,Identifiable {
    var id:Int64 {item.id}
    let item:JHSPreorderItem
    let quantity:Int
    let minimumCents:Int64
    let maximumCents:Int64
    var valid:Bool {quantity>0 && quantity<=999 && minimumCents>=0 && maximumCents>=minimumCents && maximumCents<=100_000_000_000}
}
struct JHSMatchCriteria:Codable,Sendable,Equatable {
    var japaneseOnly=false
    var minimumTotalCents:Int64?=nil
    var maximumTotalCents:Int64?=nil
    var valid:Bool {
        let low=minimumTotalCents ?? 0,high=maximumTotalCents ?? 100_000_000_000
        return low>=0 && high>=low && high<=100_000_000_000
    }
    func accepts(remark:String?)->Bool {
        guard japaneseOnly else{return true}
        let text=PlainHTML.text(remark ?? "")
        return !text.contains("非日版") && !text.contains("非日本版") && (text.contains("日版") || text.contains("日本版"))
    }
    func accepts(total:Int64)->Bool {total>=(minimumTotalCents ?? 0) && total<=(maximumTotalCents ?? 100_000_000_000)}
}
struct JHSMatchAPICounts:Codable,Sendable,Equatable {
    var sellerLists=0
    var cardVersions=0
    var sellerProfiles=0
}
struct JHSMatchShipping:Codable,Sendable {
    let sellerID:Int64
    let feeCents:Int64
    let freeAboveCents:Int64?
    func charge(subtotal:Int64)->Int64 {freeAboveCents.map{subtotal >= $0}==true ? 0:feeCents}
    init(sellerID:Int64,feeCents:Int64,freeAboveCents:Int64?=nil) {
        self.sellerID=sellerID;self.feeCents=feeCents;self.freeAboveCents=freeAboveCents
    }
    init(sellerID:Int64,value:APIValue) throws {
        let body=value["shipping_price"] == .null ? value["data"]:value
        guard let fee=Self.money(body["shipping_price"]),fee>=0 else{throw JHSMatchingError.message("卖家运费读取失败")}
        self.sellerID=sellerID;feeCents=fee
        if body["free_shipping_amount"] != .null {
            guard let threshold=Self.money(body["free_shipping_amount"]),threshold>=0 else{throw JHSMatchingError.message("包邮规则读取失败")}
            freeAboveCents=threshold>0 ? threshold:nil
        } else {freeAboveCents=nil}
    }
    static func money(_ value:APIValue)->Int64? {
        let number:Double?
        switch value{case .number(let n):number=n;case .string(let s):number=Double(s);default:number=nil}
        guard let n=number,n.isFinite,n>=0,n<=1_000_000_000 else{return nil}
        return Int64((n*100).rounded())
    }
}
struct JHSMatchCandidate:Codable,Sendable,Identifiable {
    var id:Int64 {productID}
    let versionID:Int64
    let productID:Int64
    let sellerID:Int64
    let sellerName:String
    let unitCents:Int64
    let stock:Int
    let remark:String?
    var cardID:Int64?=nil
    var imageURL:URL?=nil
}
struct JHSMatchSnapshot:Codable,Sendable,Identifiable {
    var id:Int64 {versionID}
    let versionID:Int64
    var candidates:[JHSMatchCandidate]
    var issues:[String]
}
struct JHSMatchLine:Codable,Sendable,Identifiable {
    var id:Int64 {candidate.productID}
    let candidate:JHSMatchCandidate
    let quantity:Int
    var subtotal:Int64 {candidate.unitCents*Int64(quantity)}
}
struct JHSMatchOrder:Codable,Sendable,Identifiable {
    var id:Int64 {sellerID}
    let sellerID:Int64
    let sellerName:String
    let lines:[JHSMatchLine]
    let shippingCents:Int64
    let freeAboveCents:Int64?
    var subtotal:Int64 {lines.reduce(0){$0+$1.subtotal}}
    var total:Int64 {subtotal+shippingCents}
}
struct JHSMatchPlan:Codable,Sendable,Identifiable {
    var id:String {orders.flatMap(\.lines).sorted{$0.id<$1.id}.map{"\($0.id):\($0.quantity)"}.joined(separator:",")}
    let orders:[JHSMatchOrder]
    var goodsCents:Int64 {orders.reduce(0){$0+$1.subtotal}}
    var shippingCents:Int64 {orders.reduce(0){$0+$1.shippingCents}}
    var total:Int64 {goodsCents+shippingCents}
}
enum JHSMatchStatus:String,Codable,Sendable {
    case queued,collecting,optimizing,paused,completed,partial,cancelled,failed
    var title:String {
        switch self {
        case .queued:"等待匹配";case .collecting:"查询商品中";case .optimizing:"计算跨店方案中";case .paused:"等待继续";case .completed:"匹配完成";case .partial:"匹配完成";case .cancelled:"已取消";case .failed:"匹配失败"
        }
    }
    var active:Bool {self == .queued || self == .collecting || self == .optimizing}
}
struct JHSMatchJob:Codable,Sendable,Identifiable {
    let id:UUID
    let createdAt:Date
    let accountKey:String
    let requests:[JHSMatchRequest]
    var status:JHSMatchStatus = .queued
    var snapshots:[JHSMatchSnapshot]=[]
    var shipping:[JHSMatchShipping]=[]
    var unknownShipping:[Int64]=[]
    var plans:[JHSMatchPlan]=[]
    var message:String=""
    var completedAt:Date?
    var criteria:JHSMatchCriteria?=nil
    var apiCounts:JHSMatchAPICounts?=nil
    var requiresManualResume:Bool?=nil
    var backgroundMessage:String?=nil
    var title:String {createdAt.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM:.omitted)).minute(.twoDigits).second(.twoDigits).locale(Locale(identifier:"zh_CN")))}
    func elapsed(at now:Date)->TimeInterval? {
        let end:Date
        if status.active || status == .paused {end=now}
        else if let completedAt {end=completedAt}
        else {return nil}
        let value=max(0,end.timeIntervalSince(createdAt))
        return value.isFinite && value<Double(Int.max) ? value:nil
    }
    func elapsedLabel(at now:Date)->String {
        guard let elapsed=elapsed(at:now) else{return "耗时未记录"}
        let seconds=Int(elapsed),hours=seconds/3600,minutes=seconds%3600/60,remainder=seconds%60
        if hours>0{return "耗时 \(hours)小时\(minutes)分\(remainder)秒"}
        if minutes>0{return "耗时 \(minutes)分\(remainder)秒"}
        return "耗时 \(remainder)秒"
    }
    var hasGaps:Bool {!unknownShipping.isEmpty || snapshots.contains{!$0.issues.isEmpty}}
}
enum JHSMatchingError:LocalizedError {
    case message(String)
    var errorDescription:String? {if case .message(let text)=self{return text};return nil}
}
protocol JHSMatchingProviding:Sendable {
    func waitForRequestSlot() async throws
    func sellers(versionID:Int64,page:Int) async throws -> JHSSellerPage
    func products(versionID:Int64,sellerID:Int64) async throws -> JHSSellerProducts
    func shipping(sellerID:Int64) async throws -> JHSMatchShipping
}
extension JHSMatchingProviding {
    func waitForRequestSlot() async throws {try Task.checkCancellation()}
}

struct JHSRequestLimitError:LocalizedError,Sendable {
    let statusCode:Int
    var retryAfter:TimeInterval=60
    var errorDescription:String? {"集换社暂时限制访问，匹配已暂停，请稍后手动继续"}
}

// One shared budget across matching jobs, accounts and endpoint types. No burst allowance.
actor JHSMatchingRateLimiter {
    static let shared=JHSMatchingRateLimiter()
    private let clock=ContinuousClock()
    private var next:ContinuousClock.Instant?
    private let interval:Duration
    init(interval:Duration = .milliseconds(200)) {self.interval=interval}
    func deferRequests(seconds:TimeInterval) {
        let deadline=clock.now.advanced(by:.seconds(max(60,seconds)))
        if next == nil || next! < deadline {next=deadline}
    }
    func acquire() async throws {
        while true {
            try Task.checkCancellation()
            let now=clock.now
            if let deadline=next,deadline>now {
                try await clock.sleep(until:deadline)
                continue
            }
            next=now.advanced(by:interval)
            return
        }
    }
}

struct DirectJHSMatchingClient:JHSMatchingProviding {
    let client:DirectJHSMarketplaceClient
    func waitForRequestSlot() async throws {try await JHSMatchingRateLimiter.shared.acquire()}
    func sellers(versionID:Int64,page:Int) async throws -> JHSSellerPage {
        return try await client.sellers(versionID:versionID,page:page,force:true)
    }
    func products(versionID:Int64,sellerID:Int64) async throws -> JHSSellerProducts {
        return try await client.products(versionID:versionID,sellerID:sellerID,force:true)
    }
    func shipping(sellerID:Int64) async throws -> JHSMatchShipping {
        return try JHSMatchShipping(sellerID:sellerID,value:await client.plainAccountRead(path:"market/users/\(sellerID)"))
    }
}

// Exact top-three search over collected product lots; shipping is charged once per used seller.
// Bounds deliberately assume zero shipping whenever a free-shipping threshold might be reachable.
// This keeps the bound admissible, even though adding an item can lower the final shipping charge.
enum JHSMatchOptimizer {
    static func solve(requests:[JHSMatchRequest],snapshots:[JHSMatchSnapshot],shipping:[JHSMatchShipping],criteria:JHSMatchCriteria=JHSMatchCriteria()) throws -> [JHSMatchPlan] {
        guard !requests.isEmpty,requests.allSatisfy(\.valid),criteria.valid,Set(requests.map(\.id)).count==requests.count else{throw JHSMatchingError.message("请检查匹配数量及价格区间")}
        var rules:[Int64:JHSMatchShipping]=[:]
        for rule in shipping {
            guard rules[rule.sellerID]==nil,rule.feeCents>=0,rule.freeAboveCents.map({$0>0}) != false else{throw JHSMatchingError.message("运费规则无效或重复")}
            rules[rule.sellerID]=rule
        }
        var lots:[Int64:[JHSMatchCandidate]]=[:],seen:Set<Int64>=[]
        for snapshot in snapshots {
            for lot in snapshot.candidates {
                guard let request=requests.first(where:{$0.id==lot.versionID}),lot.stock>0,criteria.accepts(remark:lot.remark),
                      lot.unitCents>=request.minimumCents,lot.unitCents<=request.maximumCents,rules[lot.sellerID] != nil else{continue}
                guard seen.insert(lot.id).inserted else{throw JHSMatchingError.message("商品数据重复，请重新匹配")}
                lots[lot.versionID,default:[]].append(lot)
            }
        }
        for id in lots.keys {lots[id]?.sort{$0.unitCents == $1.unitCents ? $0.id<$1.id:$0.unitCents<$1.unitCents}}
        let sorted=requests.sorted{(lots[$0.id]?.count ?? 0)<(lots[$1.id]?.count ?? 0)}
        func minimum(_ rows:[JHSMatchCandidate],_ start:Int,_ quantity:Int)->Int64? {
            var needed=quantity,cost:Int64=0
            for row in rows.dropFirst(start) {let take=min(needed,row.stock);cost+=Int64(take)*row.unitCents;needed-=take;if needed==0{return cost}}
            return needed==0 ? cost:nil
        }
        var future=[Int64](repeating:0,count:sorted.count+1),maximumSpend:[Int64:Int64]=[:]
        for index in sorted.indices.reversed() {
            guard let least=minimum(lots[sorted[index].id] ?? [],0,sorted[index].quantity) else{return []}
            future[index]=least+future[index+1]
            let grouped=Dictionary(grouping:lots[sorted[index].id] ?? [],by:\.sellerID)
            for (seller,rows) in grouped {
                var needed=sorted[index].quantity
                for row in rows.sorted(by:{$0.unitCents>$1.unitCents}) {
                    let take=min(needed,row.stock);maximumSpend[seller,default:0]+=Int64(take)*row.unitCents;needed-=take;if needed==0{break}
                }
            }
        }
        var best:[JHSMatchPlan]=[],chosen:[JHSMatchLine]=[],subtotals:[Int64:Int64]=[:],visits=0
        func mandatoryShipping()->Int64 {
            subtotals.reduce(0){sum,entry in
                guard entry.value>0 || chosen.contains(where:{$0.candidate.sellerID==entry.key}),let rule=rules[entry.key] else{return sum}
                if rule.freeAboveCents==nil || maximumSpend[entry.key,default:0] < rule.freeAboveCents! {return sum+rule.feeCents}
                return sum
            }
        }
        func visitCard(_ index:Int,_ goods:Int64) throws {
            visits+=1;if visits%128==0{try Task.checkCancellation()}
            if index==sorted.count {
                let grouped=Dictionary(grouping:chosen,by:{$0.candidate.sellerID})
                let orders=grouped.map {seller,lines -> JHSMatchOrder in
                    let subtotal=lines.reduce(Int64(0)){$0+$1.subtotal},rule=rules[seller]!
                    return JHSMatchOrder(sellerID:seller,sellerName:lines[0].candidate.sellerName,lines:lines.sorted{$0.id<$1.id},shippingCents:rule.charge(subtotal:subtotal),freeAboveCents:rule.freeAboveCents)
                }.sorted{$0.sellerID<$1.sellerID}
                let plan=JHSMatchPlan(orders:orders)
                guard criteria.accepts(total:plan.total) else{return}
                if !best.contains(where:{$0.id==plan.id}) {best.append(plan);best.sort{$0.total == $1.total ? $0.id<$1.id:$0.total<$1.total};if best.count>3{best.removeLast()}}
                return
            }
            let request=sorted[index],rows=lots[request.id] ?? []
            func allocate(_ position:Int,_ needed:Int,_ cost:Int64) throws {
                visits+=1;if visits%128==0{try Task.checkCancellation()}
                guard let remaining=minimum(rows,position,needed) else{return}
                if let maximum=criteria.maximumTotalCents,cost+remaining+future[index+1]+mandatoryShipping()>maximum{return}
                if best.count==3,cost+remaining+future[index+1]+mandatoryShipping() >= best[2].total{return}
                if needed==0{try visitCard(index+1,cost);return}
                guard position<rows.count else{return}
                let row=rows[position],maximum=min(needed,row.stock)
                for take in stride(from:maximum,through:0,by:-1) {
                    if take>0 {
                        chosen.append(JHSMatchLine(candidate:row,quantity:take));subtotals[row.sellerID,default:0]+=Int64(take)*row.unitCents
                    }
                    try allocate(position+1,needed-take,cost+Int64(take)*row.unitCents)
                    if take>0 {
                        chosen.removeLast();subtotals[row.sellerID,default:0]-=Int64(take)*row.unitCents
                        if !chosen.contains(where:{$0.candidate.sellerID==row.sellerID}){subtotals[row.sellerID]=nil}
                    }
                }
            }
            try allocate(0,request.quantity,goods)
        }
        try Task.checkCancellation();try visitCard(0,0);return best
    }
}

@Observable @MainActor final class JHSMatchJobsStore {
    static var storageURL:URL {
        let name=ProcessInfo.processInfo.arguments.contains("--uitesting") ? "JHSMatchTasks-uitesting.json":"JHSMatchTasks.json"
        return FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Exodia").appendingPathComponent(name)
    }
    static let shared=JHSMatchJobsStore(url:storageURL,background:JHSMatchBackgroundCoordinator.shared,notifications:JHSMatchNotifications.shared)
    private(set) var jobs:[JHSMatchJob]
    var persistenceError:String?
    private let url:URL
    private var storageReadable=true
    private let factory:@MainActor (JHSSavedSession)throws->any JHSMatchingProviding
    private var client:(any JHSMatchingProviding)?
    private var accountKey:String?
    private var token:String?
    private var worker:Task<Void,Never>?
    private var generation=UUID()
    private var backgroundID:UIBackgroundTaskIdentifier = .invalid
    private var backgroundOwner:UUID?
    private let background:(any JHSMatchBackgroundManaging)?
    private let notifications:(any JHSMatchNotifying)?
    private var readyIDs:Set<UUID>=[]
    init(url:URL,background:(any JHSMatchBackgroundManaging)?=nil,notifications:(any JHSMatchNotifying)?=nil,factory:@escaping @MainActor (JHSSavedSession)throws->any JHSMatchingProviding = JHSMatchJobsStore.defaultClient) {
        self.url=url;self.factory=factory;self.background=background;self.notifications=notifications
        jobs=[]
        if FileManager.default.fileExists(atPath:url.path) {
            do {jobs=try JSONDecoder().decode([JHSMatchJob].self,from:Data(contentsOf:url))}
            catch{storageReadable=false;persistenceError="历史任务读取失败，原文件已保留。"}
        }
        for index in jobs.indices where jobs[index].status.active {jobs[index].status = .paused;jobs[index].requiresManualResume=background != nil;jobs[index].message="点击继续匹配"}
        if background != nil {
            for index in jobs.indices where jobs[index].status == .paused {
                jobs[index].requiresManualResume=true;jobs[index].message="点击继续匹配"
            }
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting-jhs-results") {
            let item=JHSPreorderItem(versionID:512088,cardCID:4041,artworkID:nil,sourceCardID:139,name:"黑魔导",number:"TEST-JP001",rarity:"UR",packName:"测试",imageURL:nil)
            let request=JHSMatchRequest(item:item,quantity:2,minimumCents:500,maximumCents:1500)
            let lot=JHSMatchCandidate(versionID:item.id,productID:7001,sellerID:77,sellerName:"测试卡牌店",unitCents:1000,stock:3,remark:"轻微白边",cardID:139)
            let plan=JHSMatchPlan(orders:[JHSMatchOrder(sellerID:77,sellerName:"测试卡牌店",lines:[JHSMatchLine(candidate:lot,quantity:2)],shippingCents:0,freeAboveCents:2000)])
            var sample=JHSMatchJob(id:UUID(),createdAt:Date(),accountKey:"77",requests:[request])
            sample.completedAt=sample.createdAt.addingTimeInterval(83);sample.status = .completed;sample.plans=[plan];sample.message="已找到 1 种方案"
            sample.apiCounts=JHSMatchAPICounts(sellerLists:2,cardVersions:5,sellerProfiles:3)
            sample.snapshots=[JHSMatchSnapshot(versionID:item.id,candidates:[lot],issues:[])]
            jobs=[sample]
        }
        #endif
    }
    static func defaultClient(_ session:JHSSavedSession) throws -> any JHSMatchingProviding {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting-jhs-match") {return UITestJHSMatchingClient()}
        #endif
        guard let profile=try JHSProtocolProfile.resolved() else{throw JHSMarketplaceError.configuration}
        return DirectJHSMatchingClient(client:DirectJHSMarketplaceClient(profile:profile,session:session))
    }
    static func key(_ session:JHSSavedSession)->String {
        session.userID ?? SHA256.hash(data:Data(session.token.utf8)).map{String(format:"%02x",$0)}.joined()
    }
    func configure(session:JHSSavedSession?) {
        if token != session?.token {pause();token=session?.token;accountKey=session.map(Self.key);client=nil}
        guard let session else{return}
        do {if client==nil{client=try factory(session)};resume()}catch{persistenceError=error.localizedDescription}
    }
    @discardableResult func submit(_ requests:[JHSMatchRequest],session:JHSSavedSession,criteria:JHSMatchCriteria=JHSMatchCriteria()) throws -> UUID {
        if let request=requests.first(where:{$0.maximumCents==0}) {
            throw JHSMatchingError.message("“\(request.item.name)”的单价上限为 ¥0，只能匹配免费商品，请调整价格区间后再匹配")
        }
        if criteria.maximumTotalCents==0 {throw JHSMatchingError.message("总价上限为 ¥0，请调整价格区间后再匹配")}
        guard !requests.isEmpty,requests.allSatisfy(\.valid),criteria.valid,Set(requests.map(\.id)).count==requests.count else{throw JHSMatchingError.message("请选择卡牌并填写有效的数量、价格区间")}
        configure(session:session)
        guard client != nil else{throw JHSMarketplaceError.configuration}
        var job=JHSMatchJob(id:UUID(),createdAt:Date(),accountKey:Self.key(session),requests:requests)
        job.criteria=criteria;job.apiCounts=JHSMatchAPICounts()
        jobs.insert(job,at:0)
        do {try persist()}catch{jobs.removeAll{$0.id==job.id};throw error}
        requestBackground(job.id);return job.id
    }
    private func requestBackground(_ id:UUID) {
        guard let job=jobs.first(where:{$0.id==id}) else{return}
        guard let background else{readyIDs.insert(id);start();return}
        background.request(id:id,title:job.title,ready:{[weak self] message in
            guard let self,let job=self.jobs.first(where:{$0.id==id}),job.status == .queued,job.accountKey==self.accountKey else{background.cancel(id:id);return}
            self.update(id){$0.backgroundMessage=message};self.save()
            self.readyIDs.insert(id);self.start()
        },expired:{[weak self] in self?.systemStopped(id)})
    }
    func cancel(_ id:UUID) {
        guard let index=jobs.firstIndex(where:{$0.id==id}),jobs[index].status.active || jobs[index].status == .paused else{return}
        let wasRunning=jobs[index].status == .collecting || jobs[index].status == .optimizing
        if wasRunning {generation=UUID();worker?.cancel();worker=nil;endBackgroundTime()}
        readyIDs.remove(id);background?.cancel(id:id)
        jobs[index].status = .cancelled;jobs[index].completedAt=Date();jobs[index].message="已保留已查询资料";save()
        start()
    }
    private func systemStopped(_ id:UUID) {
        guard let index=jobs.firstIndex(where:{$0.id==id}) else{background?.finish(id:id,success:false);return}
        guard jobs[index].status.active else{
            background?.finish(id:id,success:jobs[index].status == .completed || jobs[index].status == .partial)
            if backgroundOwner==id{endBackgroundTime()}
            return
        }
        let running=jobs[index].status == .collecting || jobs[index].status == .optimizing
        if running{generation=UUID();worker?.cancel();worker=nil;endBackgroundTime()}
        readyIDs.remove(id)
        jobs[index].status = .paused;jobs[index].requiresManualResume=true;jobs[index].message="后台处理已停止，点击继续匹配"
        save();background?.finish(id:id,success:false)
        let snapshot=jobs[index]
        Task{await notifications?.deliver(snapshot)}
        start()
    }
    func pause() {
        generation=UUID();worker?.cancel();worker=nil
        for index in jobs.indices where jobs[index].status.active {
            background?.cancel(id:jobs[index].id)
            jobs[index].status = .paused;jobs[index].requiresManualResume=background != nil;jobs[index].message="点击继续匹配"
        }
        readyIDs.removeAll();save();endBackgroundTime()
    }
    func resume() {
        guard let accountKey,client != nil else{return}
        for index in jobs.indices where jobs[index].status == .paused && jobs[index].accountKey==accountKey && jobs[index].requiresManualResume != true {
            jobs[index].status = .queued;readyIDs.insert(jobs[index].id)
        }
        save();start()
    }
    func resume(_ id:UUID,session:JHSSavedSession?) {
        configure(session:session)
        guard let index=jobs.firstIndex(where:{$0.id==id}),jobs[index].status == .paused,jobs[index].accountKey==accountKey else{return}
        jobs[index].status = .queued;jobs[index].requiresManualResume=false;jobs[index].backgroundMessage=nil
        save();requestBackground(id)
    }
    func backgroundTime() {
        guard worker != nil,backgroundID == .invalid,
              let job=jobs.first(where:{$0.status == .collecting || $0.status == .optimizing}),background?.protected(job.id) != true else{return}
        let id=job.id
        backgroundOwner=id
        backgroundID=UIApplication.shared.beginBackgroundTask(withName:"预购清单匹配") {[weak self] in
            Task{@MainActor in self?.systemStopped(id)}
        }
    }
    func hasBackgroundProtection(_ id:UUID)->Bool {background?.protected(id)==true}
    func endBackgroundTime() {if backgroundID != .invalid {UIApplication.shared.endBackgroundTask(backgroundID);backgroundID = .invalid};backgroundOwner=nil}
    private func persist() throws {
        guard storageReadable else{throw JHSMatchingError.message("历史任务读取失败，无法安全保存新任务。")}
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try JSONEncoder().encode(jobs).write(to:url,options:.atomic)
    }
    private func save() {do{try persist()}catch{persistenceError=error.localizedDescription}}
    private func start() {
        guard worker==nil,client != nil,jobs.contains(where:{$0.status == .queued && $0.accountKey==accountKey && readyIDs.contains($0.id)}) else{return}
        let epoch=generation
        worker=Task{[weak self] in await self?.run(epoch:epoch)}
    }
    private func run(epoch:UUID) async {
        defer{if generation==epoch{worker=nil;endBackgroundTime()}}
        while !Task.isCancelled,generation==epoch,let client,
              let id=jobs.first(where:{$0.status == .queued && $0.accountKey==accountKey && readyIDs.contains($0.id)})?.id {
            do {
                guard let index=jobs.firstIndex(where:{$0.id==id}) else{return}
                jobs[index].status = .collecting;save();backgroundTime()
                let requests=jobs[index].requests
                let criteria=jobs[index].criteria ?? JHSMatchCriteria()
                for (requestIndex,request) in requests.enumerated() {
                    guard generation==epoch,!Task.isCancelled else{return}
                    if jobs.first(where:{$0.id==id})?.snapshots.contains(where:{$0.id==request.id})==true{continue}
                    var candidates:[JHSMatchCandidate]=[],issues:[String]=[],summaries:[Int64:JHSSellerSummary]=[:]
                    do {
                        var page=1,last:Int?,expectedTotal:Int?
                        while true {
                            try Task.checkCancellation();update(id){$0.message="\(request.item.name)：卖家第 \(page) 页"}
                            try await client.waitForRequestSlot()
                            countCall(id,kind:0)
                            let result=try await client.sellers(versionID:request.id,page:page)
                            try Task.checkCancellation();guard generation==epoch else{return}
                            report(id,units:Int64(requestIndex*1000+200*page/max(1,result.lastPage)))
                            guard result.currentPage==page,(last==nil || last==result.lastPage),(expectedTotal==nil || expectedTotal==result.total) else{throw JHSMatchingError.message("卖家分页已变化，请重新匹配")}
                            last=result.lastPage;expectedTotal=result.total
                            for seller in result.sellers {summaries[seller.id]=seller}
                            if page>=result.lastPage{break};page+=1
                        }
                        if let total=expectedTotal,summaries.count<total {issues.append("卖家列表读取不完整，请重新匹配")}
                    } catch {if error is JHSRequestLimitError{throw error};if Task.isCancelled{throw CancellationError()};issues.append(error.localizedDescription)}
                    for (sellerIndex,seller) in summaries.values.sorted(by:{$0.id<$1.id}).enumerated() {
                        try Task.checkCancellation();guard generation==epoch else{return}
                        if seller.minimumPrice>Double(request.maximumCents)/100 || seller.quantity<=0 {continue}
                        update(id){$0.message="\(request.item.name)：核对 \(seller.username)"}
                        do {
                            try await client.waitForRequestSlot()
                            countCall(id,kind:1)
                            let detail=try await client.products(versionID:request.id,sellerID:seller.id)
                            try Task.checkCancellation();guard generation==epoch else{return}
                            report(id,units:Int64(requestIndex*1000+200+800*(sellerIndex+1)/max(1,summaries.count)))
                            let eligible=detail.products.filter{!$0.price.isNaN && $0.price.isFinite && $0.price>=0 && $0.price<=1_000_000_000}.filter {
                                let cents=Int64(($0.price*100).rounded());return cents>=request.minimumCents && cents<=request.maximumCents && $0.quantity>0 && $0.condition==1 && criteria.accepts(remark:$0.remark)
                            }
                            guard !eligible.isEmpty else{continue}
                            if let job=jobs.first(where:{$0.id==id}),!job.shipping.contains(where:{$0.sellerID==seller.id}),!job.unknownShipping.contains(seller.id) {
                                do {
                                    try await client.waitForRequestSlot()
                                    countCall(id,kind:2)
                                    let rule=try await client.shipping(sellerID:seller.id)
                                    try Task.checkCancellation();guard generation==epoch else{return}
                                    guard rule.sellerID==seller.id,rule.feeCents>=0 else{throw JHSMatchingError.message("运费资料不完整")}
                                    update(id){$0.shipping.append(rule)}
                                } catch {if error is JHSRequestLimitError{throw error};if Task.isCancelled{throw CancellationError()};update(id){$0.unknownShipping.append(seller.id)};issues.append("\(seller.username)：运费读取失败")}
                            }
                            JHSPreorderStore.shared.rememberImage(detail.imageURL,versionID:request.id)
                            candidates+=eligible.map{JHSMatchCandidate(versionID:request.id,productID:$0.id,sellerID:seller.id,sellerName:seller.username,unitCents:Int64(($0.price*100).rounded()),stock:$0.quantity,remark:$0.remark,cardID:$0.cardID,imageURL:detail.imageURL)}
                        } catch {if error is JHSRequestLimitError{throw error};if Task.isCancelled{throw CancellationError()};issues.append("\(seller.username)：\(error.localizedDescription)")}
                    }
                    guard generation==epoch else{return}
                    update(id){$0.snapshots.append(JHSMatchSnapshot(versionID:request.id,candidates:candidates,issues:issues))}
                    try persist()
                    report(id,units:Int64((requestIndex+1)*1000))
                }
                update(id){$0.status = .optimizing;$0.message="计算商品总价与各店运费，寻找最低的三种跨店方案"}
                try persist()
                report(id,units:Int64(requests.count*1000))
                guard let snapshot=jobs.first(where:{$0.id==id}) else{return}
                let solver=Task.detached(priority:.utility){try JHSMatchOptimizer.solve(requests:snapshot.requests,snapshots:snapshot.snapshots,shipping:snapshot.shipping,criteria:snapshot.criteria ?? JHSMatchCriteria())}
                let plans=try await withTaskCancellationHandler(operation:{try await solver.value},onCancel:{solver.cancel()})
                try Task.checkCancellation();guard generation==epoch else{return}
                update(id){$0.plans=plans;$0.status = $0.hasGaps ? .partial:.completed;$0.completedAt=Date();$0.message=plans.isEmpty ? "当前资料中没有满足全部数量及价格区间的方案":"已找到 \(plans.count) 种方案"}
                try persist()
                await finish(id,success:true)
            } catch {
                guard generation==epoch else{return}
                let limited=error is JHSRequestLimitError
                if let limit=error as? JHSRequestLimitError {await JHSMatchingRateLimiter.shared.deferRequests(seconds:limit.retryAfter)}
                update(id){$0.status = (Task.isCancelled || limited) ? .paused:.failed;$0.requiresManualResume=limited;if !Task.isCancelled && !limited{$0.completedAt=Date()};$0.message=error.localizedDescription}
                save()
                await finish(id,success:false)
                if Task.isCancelled{return}
            }
        }
    }
    private func report(_ id:UUID,units:Int64) {
        guard let job=jobs.first(where:{$0.id==id}) else{return}
        background?.update(id:id,completed:units,total:Int64((job.requests.count+1)*1000),subtitle:job.message)
    }
    private func finish(_ id:UUID,success:Bool) async {
        // Keep the execution lease until the notification request has been handed to the system.
        defer {
            readyIDs.remove(id);background?.finish(id:id,success:success)
            if backgroundOwner==id{endBackgroundTime()}
        }
        if let job=jobs.first(where:{$0.id==id}),job.status != .paused {await notifications?.deliver(job)}
    }
    private func countCall(_ id:UUID,kind:Int) {
        update(id){job in
            // An older resumed task has no complete historical count; retain that distinction.
            guard job.apiCounts != nil else{return}
            switch kind {
            case 0:job.apiCounts?.sellerLists+=1
            case 1:job.apiCounts?.cardVersions+=1
            default:job.apiCounts?.sellerProfiles+=1
            }
        }
        save()
    }
    private func update(_ id:UUID,_ change:(inout JHSMatchJob)->Void) {if let index=jobs.firstIndex(where:{$0.id==id}){change(&jobs[index])}}
}

#if DEBUG
struct UITestJHSMatchingClient:JHSMatchingProviding {
    func sellers(versionID:Int64,page:Int) async throws -> JHSSellerPage {
        if ProcessInfo.processInfo.arguments.contains("--uitesting-jhs-match-slow") {
            let rows=(77..<85).map{["seller_user_id":$0,"seller_username":"测试卡牌店 \($0)","min_price":10,"quantity":3] as [String:Any]}
            let bytes=try JSONSerialization.data(withJSONObject:["current_page":1,"last_page":1,"total":8,"data":rows])
            return try JHSSellerPage(data:JSONDecoder().decode(APIValue.self,from:bytes))
        }
        return try await UITestJHSMarketplaceClient().sellers(versionID:versionID,page:page,force:true)
    }
    func products(versionID:Int64,sellerID:Int64) async throws -> JHSSellerProducts {
        if ProcessInfo.processInfo.arguments.contains("--uitesting-jhs-match-slow") {try await Task.sleep(for:.seconds(6))}
        if ProcessInfo.processInfo.arguments.contains("--uitesting-jhs-match-notification") {try await Task.sleep(for:.seconds(12))}
        let productBase=ProcessInfo.processInfo.arguments.contains("--uitesting-jhs-match-slow") ? versionID*1_000_000+sellerID*10:versionID*10
        let bytes=Data("""
        {"card_id":139,"card_version_image":"https://example.test/jhs-card.jpg","products":[{"product_id":\(productBase+1),"price":10,"quantity":2,"condition":1,"remark":"日版 轻微白边"},{"product_id":\(productBase+2),"price":12,"quantity":1,"condition":1,"remark":"非日版"},{"product_id":\(productBase+3),"price":14,"quantity":1,"condition":1,"remark":"日本版 无明显瑕疵"}]}
        """.utf8)
        return try JHSSellerProducts(data:JSONDecoder().decode(APIValue.self,from:bytes),sellerID:sellerID)
    }
    func shipping(sellerID:Int64) async throws -> JHSMatchShipping {JHSMatchShipping(sellerID:sellerID,feeCents:600,freeAboveCents:2000)}
}
#endif

protocol JHSMatchCartProviding:Sendable {
    func cartItems(sellerID:Int64) async throws -> [JHSCartItem]
    func addToCart(productID:Int64,cardID:Int64,sellerID:Int64,quantity:Int) async throws
    func products(versionID:Int64,sellerID:Int64,force:Bool) async throws -> JHSSellerProducts
}
extension DirectJHSMarketplaceClient:JHSMatchCartProviding {}

@Observable @MainActor final class JHSMatchCartStore {
    static let shared:JHSMatchCartStore = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            let defaults=UserDefaults(suiteName:"com.localdevelopment.Exodia.matchcart.uitesting")!
            if ProcessInfo.processInfo.arguments.contains("--uitesting-reset") {defaults.removeObject(forKey:"exodia.jhs.matchcart.progress.v1")}
            return JHSMatchCartStore(defaults:defaults)
        }
        #endif
        return JHSMatchCartStore()
    }()
    private struct Progress:Codable {var added:Set<String>;var confirmed:[String:Set<Int64>];var uncertain:Set<String>}
    private let defaults:UserDefaults
    init(defaults:UserDefaults = .standard) {
        self.defaults=defaults
        if let data=defaults.data(forKey:"exodia.jhs.matchcart.progress.v1"),let state=try? JSONDecoder().decode(Progress.self,from:data) {
            added=state.added;confirmed=state.confirmed;uncertain=state.uncertain
        }
    }
    private func save() {
        if let data=try? JSONEncoder().encode(Progress(added:added,confirmed:confirmed,uncertain:uncertain)){defaults.set(data,forKey:"exodia.jhs.matchcart.progress.v1")}
    }
    private(set) var adding:String?
    private(set) var added:Set<String>=[]
    private(set) var confirmed:[String:Set<Int64>]=[:]
    private(set) var uncertain:Set<String>=[]
    var error:String?
    func add(_ plan:JHSMatchPlan,requests:[JHSMatchRequest],key:String,client:any JHSMatchCartProviding) async {
        guard adding==nil,!added.contains(key),!uncertain.contains(key) else{return}
        adding=key;defer{adding=nil}
        for order in plan.orders {
            for line in order.lines where !(confirmed[key] ?? []).contains(line.id) {
                do {
                    guard let request=requests.first(where:{$0.id==line.candidate.versionID}),line.quantity>0,line.quantity<=3 else{throw JHSMarketplaceError.invalidData}
                    // Read current stock and price before writing a historical result.
                    let detail=try await client.products(versionID:request.id,sellerID:order.sellerID,force:true)
                    guard let product=detail.products.first(where:{$0.id==line.id}),product.quantity>=line.quantity else{
                        throw JHSMatchingError.message("\(request.item.name)：商品已下架或库存不足")
                    }
                    guard JHSMatchShipping.money(.number(product.price))==line.candidate.unitCents else{
                        throw JHSMatchingError.message("\(request.item.name)：价格已变化，请重新匹配")
                    }
                    guard let cardID=product.cardID ?? line.candidate.cardID ?? request.item.sourceCardID else{throw JHSMarketplaceError.invalidData}
                    let before=try await client.cartItems(sellerID:order.sellerID).filter{$0.productID==line.id}.reduce(0){$0+$1.quantity}
                    uncertain.insert(key);save()
                    var writeError:Error?
                    do {try await client.addToCart(productID:line.id,cardID:cardID,sellerID:order.sellerID,quantity:line.quantity)}
                    catch {writeError=error}
                    let rows:[JHSCartItem]
                    do {rows=try await client.cartItems(sellerID:order.sellerID)}
                    catch {
                        uncertain.insert(key)
                        throw JHSMatchingError.message("加购结果读取失败，请到购物车查看后再操作")
                    }
                    let after=rows.filter{$0.productID==line.id}.reduce(0){$0+$1.quantity}
                    if after==before+line.quantity {confirmed[key,default:[]].insert(line.id);uncertain.remove(key);save()}
                    else if after==before,let writeError {
                        // A transport failure may still commit later; never retry it automatically.
                        if case JHSMarketplaceError.rejected = writeError {uncertain.remove(key)}
                        save();throw writeError
                    } else {
                        uncertain.insert(key)
                        throw JHSMatchingError.message("购物车数量与本次加购不一致，请到购物车查看")
                    }
                } catch {
                    let count=confirmed[key]?.count ?? 0
                    save()
                    self.error=(count>0 ? "已加入 \(count) 件商品。":"")+error.localizedDescription
                    return
                }
            }
        }
        added.insert(key);save()
    }
}

#if DEBUG
actor UITestJHSMatchCartClient:JHSMatchCartProviding {
    static let shared=UITestJHSMatchCartClient()
    private var quantity=0
    func products(versionID:Int64,sellerID:Int64,force:Bool) async throws -> JHSSellerProducts {
        try await UITestJHSMarketplaceClient().products(versionID:versionID,sellerID:sellerID,force:force)
    }
    func cartItems(sellerID:Int64) async throws -> [JHSCartItem] {
        guard quantity>0 else{return []}
        let value=APIValue.array([.object(["cart_id":.number(7001),"product_id":.number(7001),"quantity":.number(Double(quantity)),"product_price":.number(10),"product_quantity":.number(3)])])
        return try JHSCartItem.decode(value,sellerID:sellerID)
    }
    func addToCart(productID:Int64,cardID:Int64,sellerID:Int64,quantity:Int) async throws {
        self.quantity+=quantity
    }
}
#endif
