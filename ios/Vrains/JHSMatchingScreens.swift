import SwiftUI

func jhsMatchMoney(_ cents:Int64)->String {(Double(cents)/100).formatted(.currency(code:"CNY"))}
struct JHSMatchPriceDraft:Equatable {
    var lower:Double=0
    var upper:Double=1
    var unrestricted:Bool {lower==0 && upper==1}
    mutating func move(lower isLower:Bool,to position:Double,ceiling:Double) {
        let snapped=(min(1,max(0,position))*ceiling).rounded()/ceiling
        if isLower {lower=min(snapped,upper)}
        else {upper=max(lower,1/ceiling,snapped)}
    }
    func minimumCents(ceiling:Double)->Int64? {lower==0 ? nil:Int64((lower*ceiling).rounded())*100}
    func maximumCents(ceiling:Double)->Int64? {upper==1 ? nil:Int64((upper*ceiling).rounded())*100}
}
private struct JHSMatchDraft:Identifiable {
    var id:Int64 {item.id}
    let item:JHSPreorderItem
    var selected=false
    var quantity=1
    var price=JHSMatchPriceDraft()
}

struct JHSMatchBuilderScreen:View {
    @Environment(JHSAccountStore.self) private var jhs
    @State private var jobs=JHSMatchJobsStore.shared
    @State private var submitting=false
    @State private var submitError:String?
    @Environment(\.dismiss) private var dismiss
    @State private var drafts:[JHSMatchDraft]
    @State private var japaneseOnly=true
    @State private var totalPrice=JHSMatchPriceDraft()
    @State private var confirmingDiscard=false
    let submitted:(UUID)->Void
    init(items:[JHSPreorderItem],submitted:@escaping (UUID)->Void) {
        _drafts=State(initialValue:items.map{JHSMatchDraft(item:$0)});self.submitted=submitted
    }
    private var selectedCount:Int {drafts.filter(\.selected).count}
    private var hasChanges:Bool {!japaneseOnly || !totalPrice.unrestricted || drafts.contains{$0.selected || $0.quantity != 1 || !$0.price.unrestricted}}
    var body:some View {
        NavigationStack {
            Form {
                Section("匹配条件") {
                    Toggle("日版",isOn:$japaneseOnly).accessibilityIdentifier("jhs.match.japanese")
                    JHSMatchPriceRangeView(title:"总价（含运费）",draft:$totalPrice,ceiling:5000,identifier:"total")
                }
                ForEach($drafts) {$draft in
                    Section {
                        Toggle(isOn:$draft.selected) {
                            HStack(alignment:.top,spacing:12) {
                                JHSVersionArtwork(item:draft.item)
                                    .frame(width:48,height:70).accessibilityHidden(true)
                                VStack(alignment:.leading,spacing:4) {
                                    Text(draft.item.name).font(.headline)
                                    Text(draft.item.rarity).font(.subheadline).foregroundStyle(Design.accent)
                                    if !draft.item.number.isEmpty {Text(draft.item.number).font(.caption).monospacedDigit().foregroundStyle(.secondary)}
                                }.padding(.vertical,4)
                            }
                        }.accessibilityIdentifier("jhs.match.select.\(draft.id)")
                        if draft.selected {
                            ViewThatFits(in:.horizontal) {
                                HStack(spacing:16) {Text("数量（张）");Spacer(minLength:0);quantityPicker($draft.quantity,id:draft.id).frame(width:180)}
                                VStack(alignment:.leading,spacing:8) {Text("数量（张）");quantityPicker($draft.quantity,id:draft.id)}
                            }.padding(.vertical,4)
                            JHSMatchPriceRangeView(title:"单张价格",draft:$draft.price,ceiling:1000,identifier:String(draft.id))
                        }
                    } header:{
                        if draft.id==drafts.first?.id {Text("卡片 · 已选 \(selectedCount)/\(drafts.count)")}
                    }
                }
            }.navigationTitle("设置匹配").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) {
                        Button {if hasChanges{confirmingDiscard=true}else{dismiss()}} label:{Image(systemName:"xmark")}
                            .accessibilityLabel("取消").accessibilityIdentifier("jhs.match.cancel")
                    }
                    ToolbarItem(placement:.topBarTrailing) {
                        Button {reset()} label:{Image(systemName:"arrow.counterclockwise")}
                            .accessibilityLabel("重置").accessibilityIdentifier("jhs.match.reset")
                    }
                }
                .safeAreaInset(edge:.bottom,spacing:0) {
                    VStack(spacing:8) {
                        Button {submit()} label:{
                            Text("开始匹配").font(.headline).frame(maxWidth:.infinity,minHeight:54)
                        }.buttonStyle(.borderedProminent).tint(Design.accent)
                            .disabled(selectedCount==0 || submitting).accessibilityIdentifier("jhs.match.submit")
                    }.padding(.horizontal,20).padding(.top,12).padding(.bottom,8).background(.bar)
                }
                .confirmationDialog("放弃本次设置？",isPresented:$confirmingDiscard,titleVisibility:.visible) {
                    Button("放弃设置",role:.destructive){dismiss()}
                    Button("继续设置",role:.cancel){}
                }
                .interactiveDismissDisabled(hasChanges)
                .alert("未能开始匹配",isPresented:Binding(get:{submitError != nil},set:{if !$0{submitError=nil}})){Button("好",role:.cancel){}}message:{Text(submitError ?? "")}
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }
    private func quantityPicker(_ quantity:Binding<Int>,id:Int64)->some View {
        Picker("数量",selection:quantity) {ForEach(1...3,id:\.self){Text("\($0)").accessibilityLabel("\($0) 张").tag($0)}}
            .pickerStyle(.segmented).accessibilityIdentifier("jhs.match.quantity.\(id)")
    }
    private func submit() {
        guard !submitting,selectedCount>0 else{return}
        guard let session=jhs.session else{submitError="请先绑定集换社";return}
        submitting=true
        do {
            let requests=drafts.filter(\.selected).map{draft in
                JHSMatchRequest(item:draft.item,quantity:draft.quantity,minimumCents:draft.price.minimumCents(ceiling:1000) ?? 0,maximumCents:draft.price.maximumCents(ceiling:1000) ?? 100_000_000_000)
            }
            let criteria=JHSMatchCriteria(japaneseOnly:japaneseOnly,minimumTotalCents:totalPrice.minimumCents(ceiling:5000),maximumTotalCents:totalPrice.maximumCents(ceiling:5000))
            JHSMatchNotifications.shared.requestPermission()
            let id=try jobs.submit(requests,session:session,criteria:criteria)
            submitted(id)
        } catch {submitting=false;submitError=error.localizedDescription}
    }
    private func reset() {japaneseOnly=true;totalPrice=JHSMatchPriceDraft();drafts=drafts.map{JHSMatchDraft(item:$0.item)}}
}

private struct JHSMatchPriceRangeView:View {
    let title:String
    @Binding var draft:JHSMatchPriceDraft
    let ceiling:Double
    let identifier:String
    @State private var draggingLower:Bool?
    @State private var ignoringDrag=false
    private func value(_ position:Double)->String {
        let amount=(position*ceiling).rounded()
        return amount.formatted(.currency(code:"CNY").precision(.fractionLength(0)))
    }
    private var label:String {draft.unrestricted ? "不限":"\(draft.lower==0 ? "不限":value(draft.lower)) – \(draft.upper==1 ? "不限":value(draft.upper))"}
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            HStack(spacing:8) {
                ViewThatFits(in:.horizontal) {
                    HStack(spacing:12) {Text(title);Spacer();Text(label).monospacedDigit().foregroundStyle(.secondary).fixedSize()}
                    VStack(alignment:.leading,spacing:4) {Text(title);Text(label).monospacedDigit().foregroundStyle(.secondary)}
                }
                Button{draft=JHSMatchPriceDraft()}label:{Image(systemName:"arrow.counterclockwise").frame(width:44,height:44)}
                    .buttonStyle(.borderless).disabled(draft.unrestricted)
                    .accessibilityLabel("重置\(title)为不限").accessibilityIdentifier("jhs.match.range.reset.\(identifier)")
            }
            GeometryReader {proxy in
                let inset:CGFloat=22,width=max(1,proxy.size.width-inset*2)
                let low=inset+width*draft.lower,high=inset+width*draft.upper
                ZStack(alignment:.leading) {
                    Capsule().fill(Color(uiColor:.tertiarySystemFill)).frame(height:4).padding(.horizontal,inset)
                    Capsule().fill(draft.unrestricted ? Color.secondary.opacity(0.35):Design.accent)
                        .frame(width:max(0,high-low),height:4).offset(x:low)
                    thumb(lower:true).position(x:low,y:22)
                    thumb(lower:false).position(x:high,y:22)
                }.frame(maxWidth:.infinity,maxHeight:.infinity).contentShape(Rectangle())
                    .simultaneousGesture(DragGesture(minimumDistance:8).onChanged {drag in
                        guard !ignoringDrag else{return}
                        if draggingLower==nil {
                            guard abs(drag.translation.width)>abs(drag.translation.height) else{ignoringDrag=true;return}
                            draggingLower=low==high ? drag.startLocation.x<=low:abs(drag.startLocation.x-low)<abs(drag.startLocation.x-high)
                        }
                        let position=min(1,max(0,Double((drag.location.x-inset)/width)))
                        draft.move(lower:draggingLower==true,to:position,ceiling:ceiling)
                    }.onEnded{_ in draggingLower=nil;ignoringDrag=false})
            }.frame(height:44).accessibilityElement(children:.contain)
        }.padding(.vertical,8)
    }
    private func thumb(lower:Bool)->some View {
        Circle().fill(.white)
            .overlay(Circle().strokeBorder(Color(uiColor:.separator),lineWidth:1))
            .shadow(color:.black.opacity(0.12),radius:2,y:1)
            .frame(width:26,height:26).frame(width:44,height:44).allowsHitTesting(false)
            .accessibilityIdentifier("jhs.match.range.\(identifier).\(lower ? "lower":"upper")")
            .accessibilityLabel("\(title)\(lower ? "下限":"上限")")
            .accessibilityValue((lower ? draft.lower==0:draft.upper==1) ? "不限":value(lower ? draft.lower:draft.upper))
            .accessibilityAdjustableAction {direction in
                let change=direction == .increment ? 0.01:-0.01
                draft.move(lower:lower,to:(lower ? draft.lower:draft.upper)+change,ceiling:ceiling)
            }
    }
}
private struct JHSMatchElapsedLabel:View {
    let job:JHSMatchJob
    let identifier:String
    var body:some View {
        Group {
            if job.status.active || job.status == .paused {
                TimelineView(.periodic(from:.now,by:1)){context in Text(job.elapsedLabel(at:context.date))}
            } else {Text(job.elapsedLabel(at:.now))}
        }.monospacedDigit().accessibilityIdentifier(identifier)
    }
}
struct JHSMatchJobsScreen:View {
    @State private var jobs=JHSMatchJobsStore.shared
    var body:some View {
        List {
            if jobs.jobs.isEmpty {ContentUnavailableView("还没有匹配任务",systemImage:"list.bullet.rectangle",description:Text("在预购清单中选择卡片并开始匹配。"))}
            ForEach(jobs.jobs){job in
                NavigationLink {JHSMatchJobScreen(jobID:job.id)} label:{
                    VStack(alignment:.leading,spacing:7) {
                        HStack{Text(job.title).font(.headline);Spacer();Text(job.status.title).font(.caption).foregroundStyle(.secondary)}
                        Text(job.status.active ? "已查询 \(job.snapshots.count)/\(job.requests.count) 张卡":job.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        JHSMatchElapsedLabel(job:job,identifier:"jhs.match.elapsed.list.\(job.id)").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical,4)
                }.accessibilityIdentifier("jhs.match.job.\(job.id)")
            }
        }.navigationTitle("匹配任务").navigationBarTitleDisplayMode(.inline)
    }
}
// Version images always come from JHS. A missing image never switches to Neuron.
struct JHSVersionArtwork:View {
    @Environment(JHSAccountStore.self) private var jhs
    @State private var store=JHSPreorderStore.shared
    @State private var preview:JHSArtworkPreviewItem?
    let item:JHSPreorderItem
    var imageURL:URL?=nil
    private var url:URL? {imageURL ?? store.imageURLs[item.id] ?? store.items.first(where:{$0.id==item.id})?.imageURL ?? item.imageURL}
    var body:some View {
        Button {if let url{preview=JHSArtworkPreviewItem(url:url)}} label:{
            AsyncImage(url:url) {phase in
                if let image=phase.image {image.resizable().scaledToFit()}
                else {Image(systemName:"photo").foregroundStyle(.secondary).frame(maxWidth:.infinity,maxHeight:.infinity)}
            }.contentShape(Rectangle())
        }.buttonStyle(.borderless).disabled(url==nil).accessibilityLabel("查看\(item.name)卡图")
            .accessibilityIdentifier("jhs.version.image.\(item.id)")
            .task(id:jhs.session?.token){if url==nil{await store.resolveImage(item,session:jhs.session)}}
            .fullScreenCover(item:$preview){JHSArtworkPreview(url:$0.url)}
    }
}

struct JHSMatchJobScreen:View {
    @Environment(JHSAccountStore.self) private var jhs
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var jobs=JHSMatchJobsStore.shared
    @State private var cart=JHSMatchCartStore.shared
    @State private var showingCart=false
    @State private var notifications=JHSMatchNotifications.shared
    @State private var retryError:String?
    @State private var retriedID:UUID?
    @State private var conditionsExpanded=false
    @State private var expandedOrders:Set<String>=[]
    let jobID:UUID
    private var job:JHSMatchJob? {jobs.jobs.first{$0.id==jobID}}
    var body:some View {
        List {
            if let job {
                conditions(job)
                ForEach(Array(job.plans.enumerated()),id:\.element.id){index,plan in
                    Section {
                        VStack(alignment:.leading,spacing:12) {
                            if dynamicTypeSize.isAccessibilitySize {
                                VStack(alignment:.leading,spacing:8) {
                                    Text("方案 \(index+1)").font(.headline)
                                    Text(jhsMatchMoney(plan.total)).font(.title3.bold()).monospacedDigit().foregroundStyle(Design.accent).fixedSize(horizontal:false,vertical:true)
                                }
                            } else {
                                HStack(alignment:.firstTextBaseline) {
                                    Text("方案 \(index+1)").font(.headline)
                                    Spacer()
                                    Text(jhsMatchMoney(plan.total)).font(.title3.bold()).monospacedDigit().foregroundStyle(Design.accent)
                                }
                            }
                            ViewThatFits(in:.horizontal) {
                                HStack{Text("商品 \(jhsMatchMoney(plan.goodsCents))");Spacer();Text("运费 \(jhsMatchMoney(plan.shippingCents))")}
                                VStack(alignment:.leading,spacing:4){Text("商品 \(jhsMatchMoney(plan.goodsCents))");Text("运费 \(jhsMatchMoney(plan.shippingCents))")}
                            }.font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                        }.padding(.vertical,4)
                        ForEach(plan.orders){order in orderView(order,plan:plan,job:job)}
                        let key=cartKey(plan)
                        Button {if cart.uncertain.contains(key){showingCart=true}else{add(plan,job:job)}} label:{
                            HStack(spacing:8) {
                                if cart.adding==key {ProgressView()}
                                Image(systemName:cart.added.contains(key) ? "checkmark":"cart.badge.plus")
                                Text(cart.uncertain.contains(key) ? "查看购物车":cart.added.contains(key) ? "已加入购物车":(cart.confirmed[key]?.isEmpty==false ? "继续加入购物车":"加入购物车"))
                            }.font(.headline).frame(maxWidth:.infinity,minHeight:54)
                        }.buttonStyle(.borderedProminent).tint(Design.accent)
                            .disabled(cart.adding != nil || cart.added.contains(key))
                            .accessibilityIdentifier("jhs.match.plan.add.\(index)")
                    }
                }
                if (job.status == .completed || job.status == .partial),job.plans.isEmpty {
                    ContentUnavailableView(job.hasGaps ? "查询失败，暂无方案":"没有符合条件的方案",systemImage:job.hasGaps ? "exclamationmark.triangle":"magnifyingglass")
                        .accessibilityIdentifier("jhs.match.empty")
                }
                if job.hasGaps {
                    Section {
                        DisclosureGroup("查询失败") {
                            ForEach(job.snapshots){snapshot in
                                ForEach(Array(snapshot.issues.enumerated()),id:\.offset){_,issue in Text(issue).font(.subheadline).foregroundStyle(.secondary)}
                            }
                            if job.unknownShipping.count>0,job.snapshots.allSatisfy({$0.issues.isEmpty}) {
                                Text("\(job.unknownShipping.count) 家店铺运费读取失败").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {ContentUnavailableView("未找到任务",systemImage:"questionmark.folder")}
        }.navigationTitle("匹配结果").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let job,!job.status.active,job.status != .paused {
                    ToolbarItem(placement:.topBarTrailing) {
                        Button {retry(job)}label:{Image(systemName:"arrow.clockwise")}.accessibilityLabel("重新匹配")
                            .disabled(cart.adding != nil).accessibilityIdentifier("jhs.match.retry")
                    }
                }
            }
            .sheet(isPresented:$showingCart){JHSCartScreen()}
            .navigationDestination(item:$retriedID){id in JHSMatchJobScreen(jobID:id)}
            .alert("未能重新匹配",isPresented:Binding(get:{retryError != nil},set:{if !$0{retryError=nil}})){Button("好",role:.cancel){}}message:{Text(retryError ?? "")}
            .alert("未能加入购物车",isPresented:Binding(get:{cart.error != nil},set:{if !$0{cart.error=nil}})){Button("好",role:.cancel){}}message:{Text(cart.error ?? "")}
    }
    private func conditions(_ job:JHSMatchJob)->some View {
        Section {
            VStack(alignment:.leading,spacing:12) {
                Text("匹配条件").font(.headline)
                ViewThatFits(in:.horizontal) {
                    HStack(spacing:12) {
                        Text(job.status.title).accessibilityIdentifier("jhs.match.status").accessibilityValue(jobs.hasBackgroundProtection(job.id) ? "持续后台处理":"前台处理")
                        Spacer(minLength:0)
                        JHSMatchElapsedLabel(job:job,identifier:"jhs.match.elapsed.result").fixedSize()
                    }
                    VStack(alignment:.leading,spacing:4) {
                        Text(job.status.title)
                        JHSMatchElapsedLabel(job:job,identifier:"jhs.match.elapsed.result")
                    }
                }.font(.caption).foregroundStyle(.secondary)
                if job.status.active {
                    ProgressView(value:Double(job.snapshots.count),total:Double(max(1,job.requests.count)))
                    Text(job.message).font(.caption).foregroundStyle(.secondary)
                }
                if job.status == .failed {Text(job.message).foregroundStyle(.red)}
                if let message=job.backgroundMessage,job.status.active || job.status == .paused {Text(message).font(.caption).foregroundStyle(.secondary)}
                if notifications.permissionDenied {
                    Button("开启完成通知") {if let url=URL(string:UIApplication.openSettingsURLString){UIApplication.shared.open(url)}}.font(.caption)
                }
                LabeledContent("总价（含运费）",value:totalRange(job.criteria))
                if let criteria=job.criteria {LabeledContent("日版",value:criteria.japaneseOnly ? "开启":"关闭")}
                else {LabeledContent("版本",value:"所选版本")}
                Divider()
                VStack(alignment:.leading,spacing:4) {
                    if let counts=job.apiCounts {
                        Text("查询 \(counts.sellerLists) 次卖家列表").accessibilityIdentifier("jhs.match.calls.sellers")
                        Text("查询 \(counts.cardVersions) 次卡片版本").accessibilityIdentifier("jhs.match.calls.versions")
                        Text("查询 \(counts.sellerProfiles) 次卖家资料").accessibilityIdentifier("jhs.match.calls.profiles")
                    } else {Text("接口次数未记录")}
                }.font(.caption).monospacedDigit().foregroundStyle(.secondary)
                if job.status.active || job.status == .paused {Button("取消任务",role:.destructive){jobs.cancel(job.id)}}
                if job.status == .paused {Button("继续匹配"){JHSMatchNotifications.shared.requestPermission();jobs.resume(job.id,session:jhs.session)}.disabled(jhs.session.map(JHSMatchJobsStore.key) != job.accountKey)}
                Divider()
                Button {conditionsExpanded.toggle()}label:{
                    HStack {
                        Text("\(job.requests.count) 种卡片 · \(job.requests.reduce(0){$0+$1.quantity}) 张").foregroundStyle(.primary)
                        Spacer()
                        Image(systemName:conditionsExpanded ? "chevron.up":"chevron.down").foregroundStyle(.secondary)
                    }.frame(minHeight:44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("jhs.match.conditions")
                if conditionsExpanded {
                    ForEach(job.requests){request in
                        Divider()
                        cardRow(request.item,imageURL:nil) {
                            Text(priceRange(request)).font(.subheadline).monospacedDigit()
                            Text("\(request.quantity) 张").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }.padding(.vertical,4)
        }
    }
    private func orderView(_ order:JHSMatchOrder,plan:JHSMatchPlan,job:JHSMatchJob)->some View {
        let key=plan.id+"/\(order.id)"
        return VStack(alignment:.leading,spacing:12) {
            Button {if !expandedOrders.insert(key).inserted{expandedOrders.remove(key)}}label:{
                HStack(alignment:.top,spacing:12) {
                    VStack(alignment:.leading,spacing:6) {
                        Text(order.sellerName).font(.headline).foregroundStyle(.primary)
                        Text("\(order.lines.count) 件商品 · \(order.lines.reduce(0){$0+$1.quantity}) 张").font(.caption).foregroundStyle(.secondary)
                        Text(jhsMatchMoney(order.subtotal)).font(.subheadline).monospacedDigit().foregroundStyle(.primary)
                        Text(order.shippingCents==0 ? "包邮":"运费 \(jhsMatchMoney(order.shippingCents))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName:expandedOrders.contains(key) ? "chevron.up":"chevron.down").foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("jhs.match.order.\(order.id)")
            if expandedOrders.contains(key) {
                ForEach(order.lines){line in
                    if let request=job.requests.first(where:{$0.id==line.candidate.versionID}) {
                        Divider()
                        cardRow(request.item,imageURL:line.candidate.imageURL) {
                            Text(jhsMatchMoney(line.candidate.unitCents)).font(.body).monospacedDigit()
                            if let remark=line.candidate.remark,!PlainHTML.text(remark).isEmpty {
                                Text(PlainHTML.text(remark)).font(.caption).foregroundStyle(.secondary)
                            }
                            Text("\(line.quantity) 张").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.padding(.vertical,4)
    }
    @ViewBuilder private func cardRow<Details:View>(_ item:JHSPreorderItem,imageURL:URL?,@ViewBuilder details:()->Details)->some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment:.leading,spacing:12) {
                JHSVersionArtwork(item:item,imageURL:imageURL).frame(width:54,height:78)
                cardDetails(item,details:details)
            }
        } else {
            HStack(alignment:.top,spacing:12) {
                JHSVersionArtwork(item:item,imageURL:imageURL).frame(width:54,height:78)
                cardDetails(item,details:details)
            }
        }
    }
    private func cardDetails<Details:View>(_ item:JHSPreorderItem,@ViewBuilder details:()->Details)->some View {
        VStack(alignment:.leading,spacing:6) {
            Text(item.name).font(.headline).fixedSize(horizontal:false,vertical:true)
            Text([item.number,item.rarity].filter{!$0.isEmpty}.joined(separator:" · "))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            details().fixedSize(horizontal:false,vertical:true)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func totalRange(_ criteria:JHSMatchCriteria?)->String {
        guard let criteria,criteria.minimumTotalCents != nil || criteria.maximumTotalCents != nil else{return "不限"}
        return "\(criteria.minimumTotalCents.map(jhsMatchMoney) ?? "不限") – \(criteria.maximumTotalCents.map(jhsMatchMoney) ?? "不限")"
    }
    private func priceRange(_ request:JHSMatchRequest)->String {
        if request.minimumCents==0,request.maximumCents>=100_000_000_000{return "单张价格不限"}
        return "\(jhsMatchMoney(request.minimumCents)) – \(jhsMatchMoney(request.maximumCents)) / 张"
    }
    private func cartKey(_ plan:JHSMatchPlan)->String {jobID.uuidString+"/"+plan.id}
    private func retry(_ job:JHSMatchJob) {
        guard let session=jhs.session else{retryError="请先绑定集换社";return}
        do{JHSMatchNotifications.shared.requestPermission();retriedID=try jobs.submit(job.requests,session:session,criteria:job.criteria ?? JHSMatchCriteria())}catch{retryError=error.localizedDescription}
    }
    private func add(_ plan:JHSMatchPlan,job:JHSMatchJob) {
        guard let session=jhs.session else{cart.error="请先绑定集换社";return}
        guard JHSMatchJobsStore.key(session)==job.accountKey else{cart.error="请绑定创建此任务的集换社账号";return}
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--uitesting-jhs-results") {
                Task{await cart.add(plan,requests:job.requests,key:cartKey(plan),client:UITestJHSMatchCartClient.shared)}
                return
            }
            #endif
            guard let profile=try JHSProtocolProfile.resolved() else{throw JHSMarketplaceError.configuration}
            let client=DirectJHSMarketplaceClient(profile:profile,session:session)
            Task{await cart.add(plan,requests:job.requests,key:cartKey(plan),client:client)}
        } catch {cart.error=error.localizedDescription}
    }
}
