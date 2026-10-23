import SwiftUI
import ImageIO
import Observation

struct CatalogCardDetailScreen: View {
    @Environment(CardCatalog.self) private var catalog
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let card: CatalogCard
    var deckEditor: DeckEditingSession? = nil
    init(card:CatalogCard,deckEditor:DeckEditingSession?=nil,initialArtwork:Int64=0) {
        self.card=card;self.deckEditor=deckEditor;_selection=State(initialValue:initialArtwork)
    }
    @State private var details: CardDetails?
    @State private var images: [NeuronImageVariant] = []
    @State private var printings: [CardPrintingDisplay] = []
    @State private var selection: Int64 = 0
    @State private var loadedPrintings = false
    @State private var showingAllPrintings = false
    @State private var sharingCard = false
    @State private var marketplacePrinting: CardPrintingDisplay?
    @State private var copiedName = false
    @State private var copyDismissal: Task<Void, Never>?
    private var current: CatalogCard { details?.card ?? card }
    private var saved: Bool { store.savedCards.contains(card.favoriteKey) || card.passcode.map { store.savedCards.contains(String($0)) } == true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                hero
                if !current.pendulumDescription.isEmpty { effect("灵摆效果", text: current.pendulumDescription) }
                effect("卡片详情", text: current.description.isEmpty ? "暂无公开效果文本" : current.description)
                Link(destination:URL(string:"\(PrivateConfiguration.value("officialDatabaseOrigin"))/yugiohdb/faq_search.action?ope=4&cid=\(card.cid)&request_locale=ja")!) {
                    Label("在线查询官方 Q&A",systemImage:"questionmark.circle")
                        .font(.subheadline).foregroundStyle(Design.accent)
                        .frame(minHeight:44)
                }.accessibilityIdentifier("card.detail.official.qa")
                if loadedPrintings {
                    HStack {
                        Text("卡片收录").font(.system(size: 22, weight: .bold)).accessibilityIdentifier("card.detail.printings.heading")
                        Spacer()
                        if printings.isEmpty {
                            Text("0").font(.system(size:13,weight:.medium)).foregroundStyle(Design.secondary)
                                .frame(minWidth:44,minHeight:40).accessibilityLabel("0 条 JHS 收录")
                        } else { Button { showingAllPrintings = true } label: {
                            HStack(spacing:5) { Text("\(printings.count)");Image(systemName:"chevron.right").font(.system(size:10,weight:.semibold)) }
                                .font(.system(size:13,weight:.medium)).foregroundStyle(Design.accent).frame(minWidth:44,minHeight:40).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("查看全部 \(printings.count) 条 JHS 收录").accessibilityIdentifier("card.detail.printings.all") }
                    }
                    if printings.isEmpty {
                        Text("当前离线版本暂未包含这张卡的 JHS 收录。")
                            .font(.system(size:13)).foregroundStyle(Design.secondary).lineSpacing(5)
                            .frame(maxWidth:.infinity,alignment:.leading).padding(18)
                            .background(Design.surface,in:RoundedRectangle(cornerRadius:19))
                            .accessibilityIdentifier("card.detail.printings.empty")
                    } else { LazyVStack(spacing: 10) {
                        ForEach(Array(printings.prefix(10))) { printing in
                            Button {marketplacePrinting=printing} label: {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(printing.packName).font(.system(size: 14, weight: .semibold)).foregroundStyle(Design.ink).lineLimit(2)
                                        HStack(spacing: 10) {
                                            if let date = printing.date { Text(date).font(.system(size: 10)) }
                                            Text(printing.number.isEmpty ? "无编号" : printing.number).font(.system(size: 10, design: .monospaced))
                                        }.foregroundStyle(Design.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Text(printing.rarity).font(.system(size: 11, weight: .semibold)).foregroundStyle(Design.accent)
                                        .padding(.horizontal, 10).padding(.vertical, 8).background(Design.accent.opacity(0.07), in: Capsule())
                                    Image(systemName:"chevron.right").font(.system(size:11,weight:.semibold)).foregroundStyle(Design.secondary).padding(.top,9)
                                }.padding(16).background(Design.surface,in:RoundedRectangle(cornerRadius:19))
                            }.buttonStyle(.plain)
                                .accessibilityIdentifier("card.detail.printing.\(printing.id)")
                        }
                    } }
                }
            }.padding(.horizontal, 22).padding(.vertical, 20)
        }.background(Design.canvas).accessibilityIdentifier("card.detail.scroll").safeAreaInset(edge: .top) {
            HStack(spacing: 10) {
                detailHeaderButton("chevron.left",label:"返回") {dismiss()}
                    .accessibilityIdentifier("navigation.back")
                Text(current.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Design.ink)
                    .multilineTextAlignment(.center).lineLimit(2).frame(maxWidth: .infinity)
                    .accessibilityIdentifier("card.detail.name").accessibilityHint("长按复制卡名")
                    .contentShape(Rectangle()).onLongPressGesture(minimumDuration:0.5) { copyName() }
                detailHeaderButton("square.and.arrow.up",label:"分享") { sharingCard=true }.accessibilityIdentifier("card.detail.share")
            }.padding(.horizontal, 18).padding(.vertical, 12).background(Design.canvas)
        }.safeAreaInset(edge:.bottom) {
            if let deckEditor { DeckCardQuantityControls(session:deckEditor,card:current,ciid:selection > 0 ? selection : 1) }
        }.task(id: "\(catalog.revision)-\(catalog.artworkRevision)") {
            await readLocal()
        }.overlay(alignment:.bottom) {
            if copiedName {
                Text("已复制卡名").font(.system(size:13,weight:.medium)).foregroundStyle(.white)
                    .padding(.horizontal,18).padding(.vertical,11).background(Design.ink.opacity(0.9),in:Capsule())
                    .padding(.bottom,24).transition(.opacity).accessibilityIdentifier("card.detail.copied")
            }
        }.sheet(isPresented:$sharingCard) { CardShareSheet(card:current,ciid:selection > 0 ? selection:1) }
        .sheet(isPresented:$showingAllPrintings) { AllCardPrintingsScreen(name:current.name,rows:printings,cardCID:current.cid,artworkID:selection > 0 ? selection:nil) }
            .sheet(item:$marketplacePrinting) { JHSMarketplaceScreen(cardName:current.name,printing:$0,cardCID:current.cid,artworkID:selection > 0 ? selection:nil) }
            .onDisappear { copyDismissal?.cancel();copiedName=false }
            .presentationDragIndicator(.visible).presentationCornerRadius(32)
    }

    private func detailHeaderButton(_ symbol:String,label:String,action:@escaping ()->Void)->some View {
        Button(action:action) {
            Image(systemName:symbol).font(.system(size:16,weight:.medium)).foregroundStyle(Design.ink)
                .frame(width:44,height:44).prototypeGlass(cornerRadius:22)
        }.buttonStyle(.plain).accessibilityLabel(label)
    }

    private var selectedLimitCopies: Int? {
        details?.limitCopies(in:deckEditor?.format ?? catalog.selectedFormat).flatMap { $0 < 3 ? $0 : nil }
    }
    private var selectedImageIndex:Int { images.firstIndex(where:{$0.ciid==selection}) ?? 0 }
    private var canShowPrevious:Bool { !images.isEmpty && selectedImageIndex>0 }
    private var canShowNext:Bool { !images.isEmpty && selectedImageIndex<images.count-1 }
    private var artworkButtonY:CGFloat {92.5}
    private var hero: some View {
        HStack(alignment:.top,spacing:10) {
            ZStack {
                VStack(spacing:0) {
                    ZStack {
                        Group {
                            if images.isEmpty {
                                CardArtwork(cid: current.cid)
                            } else {
                                TabView(selection: $selection) {
                                    ForEach(images) { image in
                                        CardArtwork(cid: current.cid, ciid: image.ciid, load: nearby(image.ciid)).tag(image.ciid)
                                    }
                                }.tabViewStyle(.page(indexDisplayMode: .never))
                                    .accessibilityElement(children:.contain)
                                    .accessibilityIdentifier("card.detail.gallery")
                                    .accessibilityValue("\((images.firstIndex(where: { $0.ciid == selection }) ?? 0) + 1)/\(images.count)")
                            }
                        }
                    }.frame(height:selectedLimitCopies == nil ? 185:128*304.5946/210)
                    .padding(.top,selectedLimitCopies == nil ? 0:128*4/210)
                    if let copies=selectedLimitCopies {
                        NeuronSprite(name:"03_deck_frame_"+NeuronCardLayout.limitName(copies)+"_3")
                            .frame(width:128*40/210,height:128*40/210).padding(.top,128*3.4054/210)
                            .accessibilityElement(children:.ignore).accessibilityLabel(["禁止","限制","准限制"][copies])
                            .accessibilityIdentifier("card.detail.limit.\(copies)")
                    }
                }.frame(width:128)
                    .padding(.horizontal,selectedLimitCopies == nil ? 0:128*4/210)
                    .frame(height:selectedLimitCopies == nil ? 185:128*354/210,alignment:.top)
                    .background {
                        if let copies=selectedLimitCopies {
                            NeuronSprite(name:"03_deck_frame_"+NeuronCardLayout.limitName(copies)+"_2",caps:.init(top:4.5,left:4.5,bottom:46,right:4.5))
                        }
                    }.accessibilityElement(children:.contain)
                    .accessibilityIdentifier("card.detail.artwork.frame")
                    .accessibilityValue(selectedLimitCopies.map { ["禁止","限制","准限制"][$0] } ?? "无限制")
                    .frame(width:176,height:220,alignment:.top)
                if images.count > 1 {
                    artworkButton("chevron.left",label:"上一张异画",enabled:canShowPrevious,delta:-1)
                        .position(x:10,y:artworkButtonY).accessibilityIdentifier("card.detail.art.previous")
                    artworkButton("chevron.right",label:"下一张异画",enabled:canShowNext,delta:1)
                        .position(x:166,y:artworkButtonY).accessibilityIdentifier("card.detail.art.next")
                }
            }.frame(width:176,height:220)
                .highPriorityGesture(DragGesture(minimumDistance:20).onEnded { value in
                    guard abs(value.translation.width)>30 else{return}
                    moveArtwork(value.translation.width<0 ? 1:-1)
                })
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    CardInterfaceIcon(name: current.isMonster ? current.attributeIcon : current.spellTrapIcon, fallback: "circle.fill").frame(width: 24, height: 24)
                    Text(current.isMonster ? current.attributeTitle : current.spellTrapTitle).font(.system(size: 12, weight: .semibold))
                    if current.isMonster {
                        Spacer(minLength:0)
                        if current.levelKind == "link" {
                            NeuronLinkMarkers(markers: current.linkMarkers ?? 0).frame(width: 23, height: 23)
                                .accessibilityLabel("连接标记 \(current.arrows)").accessibilityIdentifier("card.detail.links")
                        } else {
                            CardInterfaceIcon(name: current.levelKind == "rank" ? "rank" : "level", fallback: "star.fill").frame(width: 17, height: 17)
                        }
                        Text(String(current.level ?? 0)).font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                }
                if current.isMonster {
                Text(current.compactTypeLine).font(.system(size: 12, weight: .medium)).foregroundStyle(Design.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                if current.isMonster {
                    HStack(spacing: 13) {
                        stat("ATK", value: current.attack)
                        if current.levelKind != "link" { stat("DEF", value: current.defense) }
                    }
                    if let left = current.leftScale, let right = current.rightScale {
                        HStack(spacing: 7) {
                            CardInterfaceIcon(name: "pendulum", fallback: "diamond").frame(width: 18, height: 18)
                            Text("\(left) / \(right)").font(.system(size: 12, weight: .semibold))
                        }.accessibilityLabel("灵摆刻度 \(left) / \(right)")
                    }
                }
                Spacer(minLength:0)
                HStack {
                    Spacer()
                    Button { toggleFavorite() } label: {
                        Image(systemName: saved ? "heart.fill" : "heart").font(.system(size: 19))
                            .foregroundStyle(saved ? Design.accent : Design.secondary)
                            .frame(width: 42, height: 42).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(saved ? "取消收藏\(current.name)" : "收藏\(current.name)")
                        .accessibilityIdentifier("card.detail.favorite")
                }
            }.frame(maxWidth: .infinity,maxHeight:.infinity, alignment: .leading)
                .accessibilityElement(children:.contain).accessibilityIdentifier("card.detail.info")
        }.frame(height:220,alignment:.top).padding(16).background(Design.surface,in:RoundedRectangle(cornerRadius:26))
    }
    private func artworkButton(_ symbol:String,label:String,enabled:Bool,delta:Int)->some View {
        Button { moveArtwork(delta) } label: {
            Image(systemName:symbol).font(.system(size:15,weight:.semibold)).frame(width:44,height:44).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(enabled ? Design.ink:Design.secondary.opacity(0.25))
            .disabled(!enabled).accessibilityLabel(label)
    }
    private func moveArtwork(_ delta:Int) {
        guard !images.isEmpty else{return}
        let target=max(0,min(images.count-1,selectedImageIndex+delta))
        withAnimation(.easeInOut(duration:0.2)){selection=images[target].ciid}
    }
    private func stat(_ label: String, value: Int64?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(Design.secondary)
            Text(value.map { $0 < 0 ? "?" : String($0) } ?? "—").font(.system(size: 16, weight: .semibold, design: .rounded))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func nearby(_ ciid: Int64) -> Bool {
        guard let index=images.firstIndex(where:{$0.ciid==ciid}),let selected=images.firstIndex(where:{$0.ciid==selection}) else{return false}
        return abs(index-selected)<=1
    }
    private func effect(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 21, weight: .bold)).foregroundStyle(Design.ink)
            Text(text).font(.system(size: 15)).foregroundStyle(Design.ink.opacity(0.86)).lineSpacing(7).textSelection(.enabled)
                .frame(maxWidth:.infinity,alignment:.leading).padding(20).background(Design.surface,in:RoundedRectangle(cornerRadius:24))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func copyName() {
        UIPasteboard.general.string=current.name
        copyDismissal?.cancel()
        withAnimation(.easeInOut(duration:0.16)) { copiedName=true }
        copyDismissal=Task { @MainActor in
            do { try await Task.sleep(for:.seconds(2.5));withAnimation(.easeInOut(duration:0.16)) { copiedName=false } }
            catch { }
        }
    }
    private func toggleFavorite() {
        if saved {
            store.savedCards.remove(card.favoriteKey)
            if let password = card.passcode { store.savedCards.remove(String(password)) }
        } else { store.savedCards.insert(card.favoriteKey) }
    }
    private func readLocal() async {
        do {
            details = try await catalog.database.details(cid: card.cid)
            images = (try? await NeuronArtworkStore.shared.variants(cid: card.cid)) ?? []
            if !images.contains(where: { $0.ciid == selection }) { selection = images.first?.ciid ?? 1 }
            printings = try await catalog.database.displayPrintings(cid:card.cid)
            loadedPrintings = true
        } catch { }
    }
}

struct AllCardPrintingsScreen: View {
    let name: String
    let rows: [CardPrintingDisplay]
    let cardCID:Int64
    var artworkID:Int64?=nil
    @State private var marketplacePrinting: CardPrintingDisplay?
    var body: some View {
        ScrollView {
            LazyVStack(spacing:10) {
                ForEach(rows) { printing in
                    Button {marketplacePrinting=printing} label: {
                        HStack(alignment:.top,spacing:12) {
                            VStack(alignment:.leading,spacing:8) {
                                Text(printing.packName).font(.system(size:14,weight:.semibold)).foregroundStyle(Design.ink).lineLimit(2)
                                HStack(spacing:10) {
                                    if let date=printing.date { Text(date).font(.system(size:10)) }
                                    Text(printing.number.isEmpty ? "无编号" : printing.number).font(.system(size:10,design:.monospaced))
                                }.foregroundStyle(Design.secondary)
                            }.frame(maxWidth:.infinity,alignment:.leading)
                            Text(printing.rarity).font(.system(size:11,weight:.semibold)).foregroundStyle(Design.accent)
                                .padding(.horizontal,10).padding(.vertical,8).background(Design.accent.opacity(0.07),in:Capsule())
                            Image(systemName:"chevron.right").font(.system(size:11,weight:.semibold)).foregroundStyle(Design.secondary).padding(.top,9)
                        }.padding(16).background(Design.surface,in:RoundedRectangle(cornerRadius:19))
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("card.all.printing.\(printing.id)")
                }
            }.padding(22)
        }.background(Design.canvas).accessibilityIdentifier("card.all.printings.scroll")
            .safeAreaInset(edge:.top) {
                HStack(spacing:12) { GlassBackButton();Text(name).font(.system(size:21,weight:.bold)).lineLimit(2).accessibilityIdentifier("card.all.printings.name");Spacer() }
                    .padding(.horizontal,22).padding(.vertical,14).background(Design.canvas)
            }.presentationDragIndicator(.visible).presentationCornerRadius(32)
            .sheet(item:$marketplacePrinting) { JHSMarketplaceScreen(cardName:name,printing:$0,cardCID:cardCID,artworkID:artworkID) }
    }
}

enum JHSSellerLoadingPhase: Sendable, Equatable { case idle, loading, loaded, failed }

struct JHSSellerListingGroup: Identifiable, Sendable, Equatable {
    let summary: JHSSellerSummary
    var details: JHSSellerProducts?
    var phase: JHSSellerLoadingPhase = .idle
    var errorMessage: String?
    var id: Int64 { summary.id }
    var products: [JHSMarketProduct] { details?.products ?? [] }
}

@Observable @MainActor
final class JHSMarketplaceStore {
    private(set) var groups: [JHSSellerListingGroup] = []
    private(set) var currentPage = 0
    private(set) var lastPage = 0
    private(set) var total = 0
    private(set) var hasLoaded = false
    private(set) var isLoadingPage = false
    private(set) var needsConfiguration = false
    private(set) var errorMessage: String?
    private(set) var cartAddedQuantities: [Int64:Int] = [:]
    private(set) var cartLoading: Set<Int64> = []
    private var client:(any JHSMarketplaceProviding)?
    var hasMore: Bool { currentPage > 0 && currentPage < lastPage }

    func loadInitial(versionID:Int64,session:JHSSavedSession?) async {
        guard !hasLoaded,!isLoadingPage else{return}
        await load(versionID:versionID,page:1,reset:true,force:false,session:session)
    }
    func loadMore(versionID:Int64,session:JHSSavedSession?) async {
        guard hasMore,!isLoadingPage else{return}
        await load(versionID:versionID,page:currentPage+1,reset:false,force:false,session:session)
    }
    func refresh(versionID:Int64,session:JHSSavedSession?) async {
        if let client { await client.invalidate(versionID:versionID) }
        client=nil;hasLoaded=false;needsConfiguration=false;errorMessage=nil
        await load(versionID:versionID,page:1,reset:true,force:true,session:session)
    }
    func configured(versionID:Int64,session:JHSSavedSession?) async { await refresh(versionID:versionID,session:session) }
    private func configuredClient(session:JHSSavedSession?) throws -> any JHSMarketplaceProviding {
        if let client{return client}
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting-jhs-market") { let value=UITestJHSMarketplaceClient();client=value;return value }
        #endif
        if ProcessInfo.processInfo.arguments.contains("--uitesting-jhs-unconfigured") { throw JHSMarketplaceError.configuration }
        if let profile=try JHSProtocolProfile.resolved() {
            let value=DirectJHSMarketplaceClient(profile:profile,session:session);client=value;return value
        }
        if let config=try PrintingSourceStorage().load() {
            let value=JHSMarketplaceClient(config:config);client=value;return value
        }
        throw JHSMarketplaceError.configuration
    }
    private func load(versionID:Int64,page:Int,reset:Bool,force:Bool,session:JHSSavedSession?) async {
        guard !isLoadingPage else{return};isLoadingPage=true;errorMessage=nil
        defer{isLoadingPage=false}
        do {
            let client=try configuredClient(session:session),response=try await client.sellers(versionID:versionID,page:page,force:force)
            if reset { groups=[] }
            var known=Set(groups.map(\.id))
            groups.append(contentsOf:response.sellers.filter{known.insert($0.id).inserted}.map{JHSSellerListingGroup(summary:$0)})
            currentPage=response.currentPage;lastPage=response.lastPage;total=response.total;hasLoaded=true;needsConfiguration=false
        } catch JHSMarketplaceError.configuration {
            needsConfiguration=true;hasLoaded=true;errorMessage=JHSMarketplaceError.configuration.localizedDescription
        } catch is CancellationError { }
        catch { hasLoaded=true;errorMessage=error.localizedDescription }
    }
    func hydrate(versionID:Int64,sellerID:Int64,session:JHSSavedSession?) async {
        guard let position=groups.firstIndex(where:{$0.id == sellerID}),
              groups[position].phase == .idle || groups[position].phase == .failed else{return}
        groups[position].phase = .loading;groups[position].errorMessage=nil
        do {
            let client=try configuredClient(session:session),details=try await client.products(versionID:versionID,sellerID:sellerID,force:false)
            guard let updated=groups.firstIndex(where:{$0.id==sellerID}) else{return}
            groups[updated].details=details;groups[updated].phase = .loaded
        } catch JHSMarketplaceError.loginRequired {
            guard let failed=groups.firstIndex(where:{$0.id==sellerID}) else{return}
            groups[failed].phase = .failed
            groups[failed].errorMessage=JHSMarketplaceError.loginRequired.localizedDescription
        } catch is CancellationError {
            if let cancelled=groups.firstIndex(where:{$0.id == sellerID}),groups[cancelled].phase == .loading {
                groups[cancelled].phase = .idle
            }
        }
        catch {
            guard let failed=groups.firstIndex(where:{$0.id==sellerID}) else{return}
            groups[failed].phase = .failed;groups[failed].errorMessage=error.localizedDescription
        }
    }
    func addToCart(product:JHSMarketProduct,quantity:Int,session:JHSSavedSession?) async -> String? {
        guard session != nil else{return JHSMarketplaceError.loginRequired.localizedDescription}
        guard let cardID=product.cardID,cardID>0 else{return JHSMarketplaceError.invalidData.localizedDescription}
        guard quantity>0,quantity<=min(3,product.quantity) else{return JHSMarketplaceError.invalidData.localizedDescription}
        guard !cartLoading.contains(product.id) else{return nil}
        cartLoading.insert(product.id)
        defer{cartLoading.remove(product.id)}
        do {
            let client=try configuredClient(session:session)
            try await client.addToCart(productID:product.id,cardID:cardID,sellerID:product.sellerID,quantity:quantity)
            cartAddedQuantities[product.id,default:0]+=quantity;return nil
        } catch { return error.localizedDescription }
    }
}

struct JHSMarketplaceScreen: View {
    @Environment(JHSAccountStore.self) private var jhs
    @Environment(\.dismiss) private var dismiss
    let cardName: String
    let printing: CardPrintingDisplay
    let cardCID:Int64
    var artworkID:Int64?=nil
    @State private var preorders=JHSPreorderStore.shared
    @State private var preorderError:String?
    @State private var store=JHSMarketplaceStore()
    @State private var expandedSellerID:Int64?
    @State private var previewImage:JHSArtworkPreviewItem?
    @State private var cartError:String?
    @State private var cartQuantities:[Int64:Int]=[:]
    @State private var loginRequired=false
    var body: some View {
        NavigationStack {
        ScrollView {
            LazyVStack(alignment:.leading,spacing:16) {
                HStack(spacing:8) {
                    Text(printing.number.isEmpty ? "无编号":printing.number)
                        .font(.subheadline.monospaced()).foregroundStyle(Design.secondary).accessibilityIdentifier("jhs.market.number")
                    Text(printing.rarity).font(.caption.weight(.bold)).foregroundStyle(Design.accent)
                        .padding(.horizontal,8).padding(.vertical,4).background(Design.accent.opacity(0.1),in:Capsule())
                        .accessibilityIdentifier("jhs.market.rarity")
                }.padding(.bottom,4)
                if store.needsConfiguration { configurationState }
                else if store.isLoadingPage && !store.hasLoaded { loadingState }
                else if let message=store.errorMessage,store.groups.isEmpty { errorState(message) }
                else if store.hasLoaded && store.total==0 { emptyState }
                ForEach(store.groups) { group in
                    if group.phase != .loaded || !group.products.isEmpty { sellerGroup(group) }
                }
                if !store.groups.isEmpty {
                    InfiniteScrollFooter(itemCount:store.groups.count,canLoadMore:store.hasMore,isLoading:store.isLoadingPage) {
                        await store.loadMore(versionID:printing.versionID,session:jhs.session)
                    }
                }
            }.padding(.horizontal,20).padding(.vertical,18)
        }.background(Design.canvas).accessibilityIdentifier("jhs.market.scroll")
            .automaticPagination(itemCount:store.groups.count,canLoadMore:store.hasMore,isLoading:store.isLoadingPage) {
                await store.loadMore(versionID:printing.versionID,session:jhs.session)
            }
            .refreshable { await store.refresh(versionID:printing.versionID,session:jhs.session) }
            .navigationTitle(cardName).navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement:.topBarLeading) {
                    Button {dismiss()} label:{Image(systemName:"chevron.left").fontWeight(.semibold)}
                        .accessibilityLabel("返回").accessibilityIdentifier("jhs.market.back")
                }
                ToolbarItem(placement:.topBarTrailing) {
                    Button {
                        do {try preorders.toggle(JHSPreorderItem(versionID:printing.versionID,cardCID:cardCID,artworkID:artworkID,sourceCardID:printing.sourceCardID,name:cardName,number:printing.number,rarity:printing.rarity,packName:printing.packName,imageURL:store.groups.compactMap{$0.details?.imageURL}.first))}
                        catch{preorderError=error.localizedDescription}
                    } label:{Image(systemName:preorders.contains(printing.versionID) ? "bookmark.fill":"bookmark")}
                        .accessibilityLabel(preorders.contains(printing.versionID) ? "从预购清单移除":"添加到预购清单")
                        .accessibilityIdentifier("jhs.market.preorder")
                }
            }
            .task(id:printing.versionID) { await store.loadInitial(versionID:printing.versionID,session:jhs.session) }
            .onChange(of:jhs.session?.token){_,_ in expandedSellerID=nil;Task{await store.refresh(versionID:printing.versionID,session:jhs.session)}}
            .fullScreenCover(item:$previewImage) { JHSArtworkPreview(url:$0.url) }
            .alert("未能加入购物车",isPresented:Binding(get:{cartError != nil},set:{if !$0{cartError=nil}})) {
                Button("好",role:.cancel){}
            } message:{Text(cartError ?? "")}
            .alert("需要绑定集换社",isPresented:$loginRequired) {
                Button("知道了",role:.cancel){}
            } message:{Text("请先前往主页右上角个人页，在设置中绑定集换社账号。绑定后即可查看卖家商品并加入购物车。")}
            .alert("未能加入预购清单",isPresented:Binding(get:{preorderError != nil},set:{if !$0{preorderError=nil}})) {Button("好",role:.cancel){}} message:{Text(preorderError ?? "")}
        }.presentationDragIndicator(.visible).presentationCornerRadius(32)
    }
    private var configurationState: some View {
        VStack(spacing:14) {
            Image(systemName:"network.slash").font(.system(size:28)).foregroundStyle(Design.secondary)
            Text("当前构建缺少 JHS 协议组件").font(.headline)
            Text("离线收录仍可查看；请由开发者使用私有 JHS 构建配置重新编译 App。")
                .font(.subheadline).foregroundStyle(Design.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth:.infinity).padding(24).background(Design.surface,in:RoundedRectangle(cornerRadius:22))
            .accessibilityIdentifier("jhs.market.configuration")
    }
    private var loadingState: some View {
        ProgressView().tint(Design.accent).frame(maxWidth:.infinity).frame(height:160)
            .accessibilityLabel("正在加载在售商品").accessibilityIdentifier("jhs.market.loading")
    }
    private var emptyState: some View {
        VStack(spacing:12) {
            Image(systemName:"shippingbox").font(.system(size:30)).foregroundStyle(Design.secondary)
            Text("暂无流通品相商品").font(.headline)
            Text("JHS 当前没有这个收录版本的在售商品。").font(.subheadline).foregroundStyle(Design.secondary)
        }.frame(maxWidth:.infinity).padding(.vertical,52).accessibilityIdentifier("jhs.market.empty")
    }
    private func errorState(_ message:String)->some View {
        VStack(spacing:14) {
            Image(systemName:"exclamationmark.arrow.triangle.2.circlepath").font(.system(size:28)).foregroundStyle(Design.secondary)
            Text(message).font(.subheadline).foregroundStyle(Design.secondary).multilineTextAlignment(.center)
            Button("重新加载") { Task{await store.refresh(versionID:printing.versionID,session:jhs.session)} }.buttonStyle(.bordered).tint(Design.accent)
        }.frame(maxWidth:.infinity).padding(24).background(Design.surface,in:RoundedRectangle(cornerRadius:22))
            .accessibilityIdentifier("jhs.market.error")
    }
    private func sellerGroup(_ group:JHSSellerListingGroup)->some View {
        VStack(alignment:.leading,spacing:0) {
            Button { toggleSeller(group) } label:{sellerHeader(group)}
                .buttonStyle(.plain)
                .accessibilityIdentifier("jhs.market.seller.header.\(group.id)")
                .accessibilityLabel("\(group.summary.username)，最低价 \(money(group.summary.minimumPrice))，库存 \(group.summary.quantity)，\(group.summary.location ?? "所在地未提供")")
                .accessibilityValue(expandedSellerID==group.id ? "已展开":"已折叠")
            if expandedSellerID==group.id {
                Divider().padding(.horizontal,16)
                switch group.phase {
                case .idle,.loading:
                    ProgressView().tint(Design.accent).frame(maxWidth:.infinity).frame(height:86).accessibilityLabel("正在读取卖家商品")
                case .failed:
                    VStack(spacing:9) {
                        Text(group.errorMessage ?? "商品读取失败").font(.caption).foregroundStyle(Design.secondary).multilineTextAlignment(.center)
                        Button("重新读取") { Task{await store.hydrate(versionID:printing.versionID,sellerID:group.id,session:jhs.session)} }.font(.subheadline.weight(.semibold)).tint(Design.accent)
                    }.frame(maxWidth:.infinity).padding(18)
                case .loaded:
                    ForEach(Array(group.products.enumerated()),id:\.element.id) { index,product in
                        if index>0 { Divider().padding(.leading,86) }
                        productRow(product,imageURL:group.details?.imageURL)
                    }
                }
            }
        }.background(Design.surface,in:RoundedRectangle(cornerRadius:22,style:.continuous))
            .clipShape(RoundedRectangle(cornerRadius:22,style:.continuous))
    }
    private func sellerHeader(_ group:JHSSellerListingGroup)->some View {
        HStack(alignment:.top,spacing:12) {
            VStack(alignment:.leading,spacing:6) {
                Text(group.summary.username).font(.headline).foregroundStyle(Design.ink)
                Label(group.summary.location ?? "所在地未提供",systemImage:"mappin.and.ellipse")
                    .font(.caption).foregroundStyle(Design.secondary)
            }.frame(maxWidth:.infinity,alignment:.leading)
            HStack(spacing:10) {
                VStack(alignment:.trailing,spacing:5) {
                    Text(money(group.summary.minimumPrice)).font(.system(size:17,weight:.bold,design:.rounded)).foregroundStyle(Design.accent)
                    Text("库存 \(group.summary.quantity)").font(.caption).foregroundStyle(Design.secondary)
                }
                if jhs.session != nil {
                    Image(systemName:"chevron.down").font(.caption.bold()).foregroundStyle(Design.secondary)
                        .rotationEffect(.degrees(expandedSellerID==group.id ? 180:0))
                }
            }
        }.padding(16).contentShape(Rectangle())
    }
    private func toggleSeller(_ group:JHSSellerListingGroup) {
        guard jhs.session != nil else{loginRequired=true;return}
        withAnimation(.snappy(duration:0.25)){expandedSellerID = expandedSellerID==group.id ? nil:group.id}
        guard expandedSellerID==group.id,group.phase == .idle || group.phase == .failed else{return}
        Task{await store.hydrate(versionID:printing.versionID,sellerID:group.id,session:jhs.session)}
    }
    private func productRow(_ product:JHSMarketProduct,imageURL:URL?)->some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(alignment:.top,spacing:13) {
                Button {
                    if let imageURL{previewImage=JHSArtworkPreviewItem(url:imageURL)}
                } label:{
                    AsyncImage(url:imageURL) { phase in
                        if let image=phase.image { image.resizable().scaledToFit() }
                        else { ZStack { Color(uiColor:.tertiarySystemFill);Image(systemName:"photo").foregroundStyle(Design.secondary) } }
                    }.frame(width:56,height:82).clipped()
                }.buttonStyle(.plain).disabled(imageURL==nil).accessibilityLabel("放大查看JHS卡图")
                    .accessibilityIdentifier("jhs.market.image.\(product.id)")
                VStack(alignment:.leading,spacing:7) {
                    HStack(alignment:.firstTextBaseline) {
                        Text(money(product.price)).font(.title3.weight(.semibold)).foregroundStyle(Design.accent)
                        Spacer(minLength:8)
                        Text("库存 \(product.quantity)").font(.caption).foregroundStyle(Design.secondary)
                    }
                    Text(product.remark ?? "无备注").font(.subheadline).foregroundStyle(Design.ink).lineLimit(3)
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            cartControl(product)
        }.padding(16).accessibilityElement(children:.contain)
            .accessibilityIdentifier("jhs.market.product.\(product.id)")
    }
    private func cartControl(_ product:JHSMarketProduct)->some View {
        let quantity=selectedQuantity(product)
        let loading=store.cartLoading.contains(product.id)
        let maximum=max(1,min(3,product.quantity))
        return VStack(alignment:.leading,spacing:7) {
            HStack(spacing:12) {
                HStack(spacing:0) {
                    Button { cartQuantities[product.id]=quantity-1 } label:{
                        Image(systemName:"minus").font(.system(size:13,weight:.semibold)).frame(width:44,height:44).contentShape(Rectangle())
                    }.disabled(quantity<=1 || loading)
                        .accessibilityLabel("减少数量").accessibilityIdentifier("jhs.market.cart.minus.\(product.id)")
                    Text("\(quantity)").font(.subheadline.weight(.semibold)).monospacedDigit().frame(minWidth:24)
                        .accessibilityLabel("添加数量").accessibilityValue("\(quantity) 张")
                        .accessibilityIdentifier("jhs.market.cart.quantity.\(product.id)")
                    Button { cartQuantities[product.id]=quantity+1 } label:{
                        Image(systemName:"plus").font(.system(size:13,weight:.semibold)).frame(width:44,height:44).contentShape(Rectangle())
                    }.disabled(quantity>=maximum || loading)
                        .accessibilityLabel("增加数量").accessibilityIdentifier("jhs.market.cart.plus.\(product.id)")
                }.buttonStyle(.plain).background(Color(uiColor:.tertiarySystemFill),in:RoundedRectangle(cornerRadius:12))
                Button { add(product,quantity:quantity) } label:{
                    HStack(spacing:8) {
                        if loading { ProgressView().controlSize(.small).tint(.white) }
                        Text(loading ? "正在加入":"加入购物车").font(.subheadline.weight(.semibold))
                    }.frame(maxWidth:.infinity).frame(height:44)
                        .background(Design.accent,in:RoundedRectangle(cornerRadius:12))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(.white)
                    .disabled(loading)
                    .accessibilityLabel(loading ? "正在加入购物车":"加入购物车")
                    .accessibilityIdentifier("jhs.market.cart.\(product.id)")
            }
            if let added=store.cartAddedQuantities[product.id],added>0 {
                Label("本次已添加 \(added) 张",systemImage:"checkmark")
                    .font(.caption).foregroundStyle(Design.secondary)
                    .accessibilityIdentifier("jhs.market.cart.added.\(product.id)")
            }
        }
    }
    private func selectedQuantity(_ product:JHSMarketProduct)->Int {
        min(max(1,cartQuantities[product.id] ?? 1),max(1,min(3,product.quantity)))
    }
    private func add(_ product:JHSMarketProduct,quantity:Int) {
        Task { if let message=await store.addToCart(product:product,quantity:quantity,session:jhs.session){cartError=message} }
    }
    private func money(_ value:Double)->String {
        let integer=value.rounded()==value
        return String(format:integer ? "¥%.0f":"¥%.2f",value)
    }
}

struct JHSArtworkPreviewItem:Identifiable {
    let url:URL
    var id:String{url.absoluteString}
}

struct JHSArtworkPreview:View {
    let url:URL
    @Environment(\.dismiss) private var dismiss
    @State private var scale:CGFloat=1
    @GestureState private var gestureScale:CGFloat=1
    var body:some View {
        ZStack(alignment:.topTrailing) {
            Color.black.ignoresSafeArea()
            AsyncImage(url:url) { phase in
                if let image=phase.image {
                    image.resizable().scaledToFit()
                        .scaleEffect(scale*gestureScale)
                        .gesture(MagnifyGesture().updating($gestureScale){value,state,_ in state=value.magnification}
                            .onEnded{value in scale=min(5,max(1,scale*value.magnification))})
                        .onTapGesture(count:2){withAnimation(.snappy){scale = scale>1 ? 1:2.5}}
                } else if phase.error != nil {
                    ContentUnavailableView("卡图加载失败",systemImage:"photo.badge.exclamationmark")
                        .foregroundStyle(.white)
                } else { ProgressView().tint(.white) }
            }.padding(.horizontal,24).padding(.vertical,80).frame(maxWidth:.infinity,maxHeight:.infinity)
            RoundIconButton(icon:"xmark",label:"关闭卡图"){dismiss()}
                .padding(.top,18).padding(.trailing,18).accessibilityIdentifier("jhs.market.image.close")
        }
    }
}

struct CardInterfaceIcon: View {
    let name: String
    let fallback: String
    var body: some View {
        if let image=CardUIImages.image(name,in:"InterfaceIcons") {
            Image(uiImage: image).resizable().scaledToFit().accessibilityHidden(true)
        } else { Image(systemName: fallback).resizable().scaledToFit().foregroundStyle(Design.accent).accessibilityHidden(true) }
    }
}

struct CardDataScreen: View {
    @Environment(CardCatalog.self) private var catalog
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        NavigationStack {
            List {
                Section {
                    if let metadata=catalog.metadata {
                        LabeledContent("本机卡片",value:"\(metadata.count.formatted()) 张").monospacedDigit()
                        LabeledContent("资料更新",value:metadata.updatedAt.isEmpty ? "—":String(metadata.updatedAt.prefix(10)))
                        LabeledContent("最近检查",value:metadata.checkedAt.isEmpty ? "尚未检查":String(metadata.checkedAt.prefix(10)))
                    } else {Text("正在读取本机资料…").foregroundStyle(.secondary)}
                } header:{Text("本机资料")} footer:{Text("卡片资料与日文卡图均保存在本机；无法映射的卡片显示卡背。")}
                if let plan=catalog.pendingUpdate {
                    Section {
                        LabeledContent("预估下载",value:plan.sizeLabel)
                        ForEach(plan.itemLabels,id:\.self) {Text($0).font(.subheadline).fixedSize(horizontal:false,vertical:true)}
                        Button("查看并更新"){catalog.showUpdatePrompt=true}.frame(minHeight:44)
                    } header:{Text("本次待更新")} footer:{Text("卡片数量会在读取变更目录后确定，卡图不全量下载。")}
                }
                Section {
                    ForEach(CatalogSource.allCases) {source in CatalogSourceRow(source:source)}
                } header:{Text("数据来源与状态")} footer:{Text("“无更新”仅表示本次检查范围没有发现变更。JHS 与 NW 随变更卡片更新；JHS 暂无版本时保留任务，后续继续补齐。")}
                if let message=catalog.message {
                    Section {Text(message).font(.subheadline).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("cards.update.message")}
                }
                Section {
                    Text("日文卡图和异画已完整内置，离线可用。后续新增与替换图片随资料更新下载，持久保存，不会被缓存清理删除。").font(.subheadline)
                } header:{Text("卡图资料")}
            }.listStyle(.insetGrouped).navigationTitle("卡片数据").navigationBarTitleDisplayMode(.inline)
                .toolbar {ToolbarItem(placement:.topBarLeading) {Button {dismiss()} label:{Image(systemName:"xmark")}.accessibilityLabel("关闭").accessibilityIdentifier("cards.update.close")}}
                .safeAreaInset(edge:.bottom,spacing:0) {
                    VStack(spacing:12) {
                        if catalog.isUpdating {CatalogUpdateProgress()}
                        if catalog.canCancelUpdate {
                            Button("取消更新"){catalog.cancelUpdate()}.font(.headline).frame(maxWidth:.infinity,minHeight:54).buttonStyle(.bordered)
                        } else {
                            Button {Task {await catalog.update()}} label: {
                                ZStack {Label("检查资料更新",systemImage:"arrow.clockwise").opacity(catalog.isUpdating ? 0:1);if catalog.isUpdating {ProgressView()}}
                                    .font(.headline).frame(maxWidth:.infinity,minHeight:54)
                            }.buttonStyle(.borderedProminent).disabled(catalog.isUpdating).accessibilityLabel(catalog.isUpdating ? "正在检查资料更新":"检查资料更新").accessibilityIdentifier("cards.update.check")
                        }
                    }.padding(20).background(.bar)
                }
        }.task {await catalog.prepare()}
    }

}

struct CatalogSourceRow:View {
    @Environment(CardCatalog.self) private var catalog
    let source:CatalogSource
    private var status:CatalogSourceStatus {
        catalog.sourceStatuses[source] ?? .init(phase:[CatalogSource.cards,.translations,.jhs].contains(source) ? .dependent:.waiting,detail:source == .jhs ? "随变更卡片更新；尚无版本的卡片会持续补齐":"")
    }
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            ViewThatFits(in:.horizontal) {
                HStack(alignment:.top,spacing:12) {Text(source.title).font(.headline);Spacer(minLength:8);badge}
                VStack(alignment:.leading,spacing:8) {Text(source.title).font(.headline);badge}
            }
            Text(source.origin).font(.caption).foregroundStyle(.secondary)
            Text(catalog.localSources[source] ?? "正在读取本机状态…").font(.subheadline).fixedSize(horizontal:false,vertical:true)
            if !status.detail.isEmpty {Text(status.detail).font(.footnote).foregroundStyle(status.phase == .failed ? Color.red:.secondary).fixedSize(horizontal:false,vertical:true)}
        }.padding(.vertical,8).accessibilityElement(children:.combine).accessibilityIdentifier("cards.update.source."+source.rawValue)
    }
    private var badge:some View {
        HStack(spacing:4) {
            if status.phase == .checking || status.phase == .updating {ProgressView().controlSize(.small)}
            else {Image(systemName:status.phase == .failed ? "exclamationmark.circle":(status.phase == .available ? "arrow.down.circle":(status.phase == .current || status.phase == .complete ? "checkmark.circle":"info.circle")))}
            Text(status.phase.rawValue).fixedSize()
        }.font(.subheadline).foregroundStyle(status.phase == .failed ? Color.red:Design.secondary)
    }
}

struct CatalogUpdateProgress:View {
    @Environment(CardCatalog.self) private var catalog
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            HStack(alignment:.top,spacing:12) {
                ProgressView()
                VStack(alignment:.leading,spacing:4) {
                    Text(catalog.progress).font(.subheadline).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("catalog.update.current-step")
                    if let source=catalog.activeSource,let status=catalog.sourceStatuses[source] {
                        Text(status.detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    }
                }
                Spacer(minLength:0)
            }
            if catalog.isChecking {
                let sources:[CatalogSource]=[.packs,.ocg,.tcg,.chinese,.neuron]
                let finished=sources.filter {let phase=catalog.sourceStatuses[$0]?.phase;return phase == .current || phase == .available}.count
                Text("已检查 \(finished) / \(sources.count) 项").font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}
