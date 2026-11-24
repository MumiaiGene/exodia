import SwiftUI
import UniformTypeIdentifiers

struct DeckLibraryScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Environment(CardCatalog.self) private var catalog
    var serverDecks: [Deck]? = nil
    var deleteServerDeck: ((Deck) async throws -> Void)? = nil
    @AppStorage("exodia.decks.view") private var grid = false
    @AppStorage("exodia.decks.sort") private var sortKey = DeckLibrarySort.updated.rawValue
    @AppStorage("exodia.decks.ascending") private var ascending = false
    @State private var sharingDeck:Deck?
    @State private var uploadingDeck: Deck?
    @State private var destination: String?
    @State private var editorID: String?
    @State private var creatingDeck: Deck?
    @State private var deleting: Deck?
    @State private var deletingServer=false
    @State private var deletionError:String?
    @State private var rearranging = false
    private var sort: DeckLibrarySort {
        let value=DeckLibrarySort(rawValue:sortKey) ?? .updated
        return isServer && value == .custom ? .updated : value
    }
    private var isServer: Bool { serverDecks != nil }
    private var decks: [Deck] { sort.sorted(serverDecks ?? store.myDecks,ascending:ascending) }
    var body: some View {
        Group {
            if grid && !rearranging {
                ScrollView {
                    LazyVGrid(columns:[GridItem(.flexible(),spacing:16),GridItem(.flexible(),spacing:16)],spacing:22) {
                        ForEach(decks) { deck in
                            Button { destination = deck.id } label: {
                                VStack(alignment:.leading,spacing:10) {
                                    DeckCover(deck:deck).aspectRatio(1,contentMode:.fit)
                                        .overlay(alignment:.topTrailing) {
                                            if isLinked(deck) { DuelServiceBadge().allowsHitTesting(false) }
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius:18))
                                    Text(deck.name).font(.headline).foregroundStyle(Design.ink).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading)
                                    DeckFormatTag(format:deck.banlist.flatMap(CardFormat.init(rawValue:)) ?? catalog.selectedFormat)
                                }
                            }.buttonStyle(.plain).accessibilityIdentifier("decks.confirm.\(deck.id)")
                                .contextMenu { rowActions(deck) }
                        }
                    }.padding(20)
                }
            } else {
                List {
                    ForEach(decks) { deck in
                        HStack(spacing:12) {
                            Button { destination = deck.id } label: {
                                DeckListRow(deck:deck,format:deck.banlist.flatMap(CardFormat.init(rawValue:)) ?? catalog.selectedFormat)
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("decks.confirm.\(deck.id)")
                            if !rearranging {
                                Menu { rowActions(deck) } label: { Image(systemName:"ellipsis").frame(width:44,height:44) }
                                    .accessibilityLabel("\(deck.name)选项").accessibilityIdentifier("decks.menu.\(deck.id)")
                            }
                        }.padding(.vertical,6)
                            .listRowBackground(
                                Color(uiColor:.secondarySystemGroupedBackground)
                                    .overlay(alignment:.topTrailing) {
                                        if isLinked(deck) { DuelServiceBadge().allowsHitTesting(false) }
                                    }
                            )
                    }.onMove { if !isServer { store.moveMyDecks(from:$0,to:$1) } }
                }.listStyle(.insetGrouped).scrollContentBackground(.hidden)
                    .environment(\.editMode,.constant(rearranging ? .active : .inactive))
            }
        }.background(Design.canvas).navigationTitle(isServer ? "卡组广场" : "卡组").navigationBarTitleDisplayMode(.large)
            .overlay {
                if decks.isEmpty {
                    ContentUnavailableView(isServer ? "暂无服务端卡组" : "创建第一个卡组",systemImage:"rectangle.stack.badge.plus",
                        description:Text(isServer ? "在本地卡组中点击上传，同步到一起来决斗。" : "点击右上角 +，开始构筑。"))
                }
            }
            .toolbar {
                ToolbarItemGroup(placement:.topBarTrailing) {
                    if !isServer {
                        Button { let deck=Deck.draft(); creatingDeck=deck; editorID=deck.id } label:{ Image(systemName:"plus") }
                            .accessibilityLabel("添加卡组").accessibilityIdentifier("decks.create")
                    }
                    Menu {
                        Section {
                            Button { grid=true;rearranging=false } label:{ Label("网格",systemImage:grid ? "checkmark":"square.grid.2x2") }
                            Button { grid=false } label:{ Label("列表",systemImage:!grid ? "checkmark":"list.bullet") }
                        }
                        Section {
                            Picker("排序依据", selection: Binding(get:{sort.rawValue},set:{sortKey=$0})) {
                                Text("名称").tag(DeckLibrarySort.name.rawValue).accessibilityIdentifier("decks.sort.name")
                                Text("更新时间").tag(DeckLibrarySort.updated.rawValue).accessibilityIdentifier("decks.sort.updated")
                            }
                            Picker("顺序", selection: $ascending) {
                                Text("升序").tag(true)
                                Text("降序").tag(false)
                            }.disabled(sort == .custom)
                            if !isServer {
                                Button { sortKey=DeckLibrarySort.custom.rawValue;grid=false;rearranging=true } label:{ Label("自定义排序",systemImage:"arrow.up.arrow.down") }
                                    .accessibilityIdentifier("decks.sort.custom")
                            }
                        }
                    } label:{ Image(systemName:"ellipsis") }.accessibilityLabel("卡组显示与排序").accessibilityIdentifier("decks.options")
                }
            }
            .onChange(of: sortKey) { _, value in if value != DeckLibrarySort.custom.rawValue { rearranging=false } }
            .safeAreaInset(edge:.bottom) {
                if rearranging {
                    HStack { Text("拖动卡组右侧调整顺序").font(.subheadline); Spacer(); Button("完成") { rearranging=false }.fontWeight(.semibold) }
                        .padding(18).background(.regularMaterial).accessibilityIdentifier("decks.reorder.done")
                }
            }
            .navigationDestination(item:$destination) { id in
                if isServer, let deck=serverDecks?.first(where:{$0.id==id}) {
                    DeckConfirmationScreen(deckID:id,serverDeck:deck,serverUserID:account.session?.userID,deleteServerDeck:deleteServerDeck)
                } else { DeckConfirmationScreen(deckID:id) }
            }
            .sheet(item:Binding(get:{editorID.map{DeckEditorRoute(id:$0)}},set:{editorID=$0?.id}),onDismiss:{creatingDeck=nil}) { route in
                DeckEditorScreen(deckID:route.id,draft:creatingDeck)
            }
            .sheet(item:$sharingDeck) {DeckShareSheet(deck:$0)}
            .sheet(item: $uploadingDeck) { RemoteDeckUploadScreen(deck: $0) }
            .alert("删除卡组？",isPresented:Binding(get:{deleting != nil},set:{if !$0 {deleting=nil}})) {
                Button("删除",role:.destructive) {
                    if let deck=deleting {
                        if isServer { Task { await removeServerDeck(deck) } }
                        else { store.deleteDeck(id:deck.id) }
                    }
                    deleting=nil
                }
                Button("取消",role:.cancel) { deleting=nil }
            } message:{Text(isServer ? "从一起来决斗删除“\(deleting?.name ?? "")”？本地副本会保留，并解除关联。" : "此操作会从本机删除“\(deleting?.name ?? "")”。")}
            .disabled(deletingServer)
            .overlay { if deletingServer { ProgressView("正在删除服务端卡组").padding().background(.regularMaterial,in:RoundedRectangle(cornerRadius:14)) } }
            .alert("删除失败",isPresented:Binding(get:{deletionError != nil},set:{if !$0 {deletionError=nil}})) {
                Button("好",role:.cancel) {deletionError=nil}
            } message:{Text(deletionError ?? "")}
    }
    private func isLinked(_ deck:Deck)->Bool {
        guard !isServer,let userID=account.session?.userID else { return false }
        return deck.remoteDeckIDs?[userID] != nil
    }
    private func removeServerDeck(_ deck:Deck) async {
        guard let deleteServerDeck,!deletingServer else { return }
        deletingServer=true
        defer {deletingServer=false}
        do {try await deleteServerDeck(deck)}
        catch {if !(error is CancellationError) {deletionError=AccountStore.message(for:error)}}
    }
    @ViewBuilder private func rowActions(_ deck:Deck)->some View {
        if isServer {
            Button { destination=deck.id } label:{Label("查看卡组",systemImage:"rectangle.stack")}
            Button { sharingDeck=deck } label:{Label("分享",systemImage:"square.and.arrow.up")}
            if deleteServerDeck != nil {
                Button(role:.destructive) {deleting=deck} label:{Label("从服务端删除",systemImage:"trash")}
            }
        } else {
            Button { editorID=deck.id } label:{Label("编辑",systemImage:"pencil")}
            Button { destination=deck.id } label:{Label("确认",systemImage:"rectangle.stack")}
            Button {sharingDeck=deck} label:{Label("分享",systemImage:"square.and.arrow.up")}
            Button { uploadingDeck = deck } label: { Label("上传", systemImage: "icloud.and.arrow.up") }
            Button(role:.destructive) { deleting=deck } label:{Label("删除",systemImage:"trash")}
        }
    }
}

private struct DeckValidationRequest:Hashable {let cards:[Int64];let revision:Int}

struct DeckActionBar<Content:View>: View {
    @ViewBuilder var content:Content
    var body:some View {
        VStack(alignment:.leading,spacing:10) {content}
            .padding(18).background(Design.canvas).overlay(alignment:.top) {Divider()}
    }
}

struct DeckListRow: View {
    let deck: Deck
    let format: CardFormat?
    var body: some View {
        HStack(spacing:14) {
            DeckCover(deck:deck).frame(width:76,height:76).clipShape(RoundedRectangle(cornerRadius:14))
            VStack(alignment:.leading,spacing:0) {
                Text(deck.name).font(.headline).foregroundStyle(Design.ink).lineLimit(2)
                Spacer(minLength:8)
                if let format {DeckFormatTag(format:format)}
            }.frame(maxWidth:.infinity,alignment:.leading).frame(minHeight:76,alignment:.top)
        }
    }
}

struct DeckFormatTag: View {
    let format: CardFormat
    private var title: String {
        switch format { case .ocg:"OCG"; case .simplified:"简中"; case .tcg:"TCG" }
    }
    private var tint: Color {
        switch format { case .ocg:.indigo; case .simplified:.teal; case .tcg:.orange }
    }
    var body: some View {
        Text(title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal,7).padding(.vertical,3)
            .background(tint.opacity(0.1),in:Capsule())
            .fixedSize()
            .accessibilityLabel("禁限卡表："+format.title)
    }
}

private struct DeckEditorRoute: Identifiable { let id:String }
private struct DeckDetailRoute: Identifiable { let card:CatalogCard;let artwork:DeckCard;var id:String {artwork.id} }

extension Deck {
    var modificationDateText: String {
        modifiedAt.formatted(Date.ISO8601FormatStyle(dateSeparator:.dash,timeZone:.current).year().month().day())
    }
    var shareText: String { String(data:(try? JSONEncoder().encode(self)) ?? Data(),encoding:.utf8) ?? name }
}

struct DeckCover:View {
    let deck:Deck
    var body:some View {
        Group {
            if let card=deck.coverCard {DeckCoverArtwork(card:card)}
            else {DeckGeneratedCover(name:deck.name,seed:deck.id)}
        }
    }
}

private struct DuelServiceBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        ZStack(alignment:.topLeading) {
            DuelServiceCornerShape()
                .fill(Color(hex:colorScheme == .dark ? 0x262E38 : 0xE7EAF0))
            Image("DuelServiceMark").renderingMode(.template).resizable().scaledToFit()
                .foregroundStyle(Color(hex:colorScheme == .dark ? 0x83A8CC : 0x507CAC))
                .frame(width:18,height:13)
                .offset(x:22,y:9)
        }.frame(width:44,height:44)
            .accessibilityElement(children:.ignore)
            .accessibilityLabel("已关联一起来决斗卡组")
    }
}

private struct DuelServiceCornerShape: Shape {
    func path(in rect:CGRect)->Path {
        Path { path in
            path.move(to:CGPoint(x:rect.minX,y:rect.minY))
            path.addLine(to:CGPoint(x:rect.maxX,y:rect.minY))
            path.addLine(to:CGPoint(x:rect.maxX,y:rect.maxY))
            path.closeSubpath()
        }
    }
}

struct DeckGeneratedCover:View {
    let name:String
    let seed:String
    private var colors:[Color] {
        let hash=seed.utf8.reduce(UInt64(14695981039346656037)){($0 ^ UInt64($1)) &* 1099511628211}
        let palettes:[[UInt32]]=[[0x222C4B,0x717FA0,0xDDE0EE],[0x263A35,0x819E8D,0xD8E1CC],[0x462E41,0xAB8297,0xE5D5D2],[0x36303D,0x998FAD,0xE2DFEA],[0x3A3029,0xB49D7F,0xEDE2CE]]
        let palette=palettes[Int(hash % UInt64(palettes.count))]
        return [palette[0],palette[0],palette[1],palette[0],palette[1],palette[2],palette[1],palette[2],palette[2]].map{Color(hex:$0)}
    }
    var body:some View {
        GeometryReader { proxy in
            coverBackground
                .overlay(alignment:.topLeading) {
                    Text(name).font(.system(size:min(32,proxy.size.width*0.13),weight:.bold)).foregroundStyle(.white)
                        .lineLimit(3).multilineTextAlignment(.leading).padding(proxy.size.width*0.075)
                }
        }.accessibilityLabel("默认封面：\(name)")
    }
    @ViewBuilder private var coverBackground:some View {
        if #available(iOS 18.0,*) {
            MeshGradient(width:3,height:3,points:[.init(0,0),.init(0.5,0),.init(1,0),.init(0,0.5),.init(0.42,0.58),.init(1,0.5),.init(0,1),.init(0.5,1),.init(1,1)],colors:colors)
        } else {LinearGradient(colors:[colors[0],colors[4],colors[8]],startPoint:.topLeading,endPoint:.bottomTrailing)}
    }
}

struct DeckCoverArtwork: View {
    @Environment(CardCatalog.self) private var catalog
    @State private var pendulum=false
    let card:DeckCard
    var body:some View {
        GeometryReader { proxy in
            let size=proxy.size.width, width=size/(pendulum ? 0.52:0.65), height=width*372/256
            CardArtwork(cid:card.cid,ciid:card.ciid).frame(width:width,height:height)
                .position(x:size/2,y:proxy.size.height/2+height*(pendulum ? 0.12:0.06))
        }.clipped().background(Design.surface).accessibilityHidden(true)
            .task(id:card.cid) {pendulum=(try? await catalog.database.details(cid:card.cid).card.isPendulum) ?? false}
    }
}

private struct DeckAsset: View {
    let name:String
    var body:some View {
        if let url=Bundle.main.url(forResource:name,withExtension:"png",subdirectory:"CardData/DeckAssets"),let image=UIImage(contentsOfFile:url.path) {
            Image(uiImage:image).resizable(capInsets:EdgeInsets(top:14,leading:14,bottom:14,trailing:14)).renderingMode(.template).foregroundStyle(Design.secondary)
        }
    }
}
private struct DeckPanel: ViewModifier {
    func body(content:Content)->some View {
        content.padding(14).background(Design.surface,in:RoundedRectangle(cornerRadius:17))
            .overlay { DeckAsset(name:"section-frame").opacity(0.25).allowsHitTesting(false) }
    }
}

struct DeckCardArtwork: View {
    @Environment(CardCatalog.self) private var catalog
    let artwork:DeckCard
    var quantity:Int? = nil
    var indicators = true
    var format:CardFormat? = nil
    @State private var card:CatalogCard?
    var body:some View {
        Group {
            if let card { CardGridArtwork(card:card,ciid:artwork.ciid,showsIndicators:indicators,format:format) }
            else { CardArtwork(cid:artwork.cid,ciid:artwork.ciid).aspectRatio(NeuronCardLayout.aspect,contentMode:.fit) }
        }
        .overlay(alignment:.bottomTrailing) {
            if let quantity {
                GeometryReader { proxy in
                    let size=proxy.size.width*0.50
                    ZStack {
                        if let url=Bundle.main.url(forResource:"quantity",withExtension:"png",subdirectory:"CardData/DeckAssets"),let image=UIImage(contentsOfFile:url.path) { Image(uiImage:image).resizable() }
                        else { Circle().fill(Color(hex:0x073A65)).overlay(Circle().stroke(Color(hex:0x17A8DE),lineWidth:2)) }
                        Text("\(quantity)").font(.system(size:size*0.72,weight:.regular)).foregroundStyle(.white)
                    }.frame(width:size,height:size).shadow(color:.black.opacity(0.25),radius:1)
                        .position(x:proxy.size.width-size/2,y:proxy.size.height-size/2)
                }.allowsHitTesting(false)
            }
        }
        .task(id:artwork.cid) { card=try? await catalog.database.details(cid:artwork.cid).card }
        .accessibilityLabel("\(card?.name ?? String(artwork.cid))，异画 \(artwork.ciid)\(quantity.map{"，投入 \($0) 张"} ?? "")")
    }
}

struct DeckConfirmationScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Environment(CardCatalog.self) private var catalog
    @Environment(\.dismiss) private var dismiss
    let deckID:String
    var serverDeck: Deck? = nil
    var serverUserID: String? = nil
    var deleteServerDeck: ((Deck) async throws -> Void)? = nil
    var isSelectionPreview = false
    @State private var localDestination: String?
    @State private var sharing=false
    @State private var uploading=false
    @State private var editing=false
    @State private var deleting=false
    @State private var deletingServer=false
    @State private var deletionError:String?
    @State private var selectingBanlist=false
    @State private var exporting=false
    @State private var draw=DeckDrawState()
    @State private var selected:DeckDetailRoute?
    @State private var exportMessage:String?
    private var deck:Deck? { serverDeck ?? store.decks.first{$0.id==deckID} }
    private var format:CardFormat { deck?.banlist.flatMap(CardFormat.init(rawValue:)) ?? catalog.selectedFormat }
    var body:some View {
        ScrollView {
            if let deck {
                VStack(alignment:.leading,spacing:22) {
                    HStack(spacing:16) {
                        DeckCover(deck:deck).frame(width:84,height:84).clipShape(RoundedRectangle(cornerRadius:16))
                        VStack(alignment:.leading,spacing:8) {
                            Text(deck.name).font(.title2.bold()).foregroundStyle(Design.ink)
                            if let description=deck.deckDescription,!description.isEmpty {Text(description).font(.subheadline).foregroundStyle(Design.secondary)}
                            VStack(alignment:.leading,spacing:6) {
                                HStack(spacing:6) {
                                    Text("禁限卡表：")
                                    DeckFormatTag(format:format)
                                }
                                Text("更新日期：\(deck.modificationDateText)")
                            }.font(.caption).foregroundStyle(Design.secondary)
                        }
                    }
                    section("主卡组",cards:deck.mainArtworks,legacy:deck.mainCardCIDs == nil && deck.mainCardArtworks == nil ? deck.cards:nil)
                    section("额外卡组",cards:deck.extraArtworks)
                    section("副卡组",cards:deck.sideArtworks)
                    HStack(spacing:12) {
                        Button { draw.start(cards:deck.mainArtworks) } label:{Label("模拟起手",systemImage:"hand.draw.fill").frame(maxWidth:.infinity,minHeight:50)}
                            .primaryActionStyle().disabled(deck.mainArtworks.isEmpty)
                            .accessibilityIdentifier("deck.draw.start")
                        Button { draw.drawOne() } label:{Text("+1").font(.title3.weight(.semibold)).frame(width:72,height:50)}
                            .buttonStyle(.bordered).buttonBorderShape(.capsule).disabled(draw.remaining.isEmpty).accessibilityLabel("再抽一张")
                            .accessibilityIdentifier("deck.draw.one")
                    }
                    if !draw.result.isEmpty { section("抽牌结果",cards:draw.result).accessibilityElement(children:.contain).accessibilityIdentifier("deck.draw.result").accessibilityValue("\(draw.result.count)") }
                    if let exportMessage {Text(exportMessage).font(.caption).foregroundStyle(Design.secondary)}
                }.padding(18)
            }
        }.background(Design.canvas).navigationTitle(isSelectionPreview ? "确认比赛卡组" : "").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let deck, !isSelectionPreview {
                    ToolbarItemGroup(placement:.topBarTrailing) {
                        Button {sharing=true} label:{Image(systemName:"square.and.arrow.up")}.accessibilityLabel("分享卡组")
                        Menu {
                            ControlGroup {
                                Button {
                                    if serverDeck != nil {
                                        if let userID=serverUserID, userID==account.session?.userID {
                                            localDestination=store.importRemoteDeck(deck,remoteID:deckID,userID:userID).id
                                        }
                                    } else { exporting=true }
                                } label:{Label("下载",systemImage:"arrow.down.to.line")}
                                    .disabled(serverDeck != nil && serverUserID != account.session?.userID)
                                    .accessibilityIdentifier("deck.confirm.download")
                                if serverDeck == nil {
                                    Button { store.toggleDeckFavorite(id:deck.id) } label:{Label(deck.isFavorite == true ? "取消收藏":"收藏",systemImage:deck.isFavorite == true ? "star.fill":"star")}
                                }
                                Button {sharing=true} label:{Label("分享",systemImage:"square.and.arrow.up")}
                            }
                            Divider()
                            if serverDeck == nil {
                                Button { uploading = true } label: { Label("上传", systemImage: "icloud.and.arrow.up") }
                                Button { editing=true } label:{Label("编辑",systemImage:"pencil")}.accessibilityIdentifier("deck.confirm.edit")
                                Button { let copy=store.duplicateDeck(deck);exportMessage="已复制为“\(copy.name)”。" } label:{Label("复制",systemImage:"doc.on.doc")}
                                Button { selectingBanlist=true } label:{Label("禁限卡表",systemImage:"exclamationmark.shield")}
                                Button(role:.destructive) { deleting=true } label:{Label("删除",systemImage:"trash")}
                            } else if deleteServerDeck != nil {
                                Button(role:.destructive) {deleting=true} label:{Label("从服务端删除",systemImage:"trash")}
                            }
                        } label:{Image(systemName:"ellipsis")}.accessibilityLabel("卡组选项").accessibilityIdentifier("deck.confirm.options")
                    }
                }
            }
            .sheet(isPresented:$sharing) {if let deck {DeckShareSheet(deck:deck)}}
            .sheet(isPresented: $uploading) { if let deck { RemoteDeckUploadScreen(deck: deck) } }
            .sheet(isPresented:$editing) { DeckEditorScreen(deckID:deckID) }
            .sheet(item:$selected) { CatalogCardDetailScreen(card:$0.card,initialArtwork:$0.artwork.ciid) }
            .sheet(isPresented:$selectingBanlist) {
                NavigationStack {
                    List(CardFormat.allCases) { option in
                        Button { if var value=deck { value.banlist=option.rawValue;store.saveDeck(value) };selectingBanlist=false } label:{HStack{Text(option.title);Spacer();if option==format{Image(systemName:"checkmark")}}}
                    }.navigationTitle("禁限卡表").navigationBarTitleDisplayMode(.inline)
                }.presentationDetents([.medium])
            }
            .fileExporter(isPresented:$exporting,document:deck.map(DeckExportDocument.init),contentType:.json,defaultFilename:deck?.name ?? "卡组") { result in
                if case .failure = result {exportMessage="未能导出卡组，请重试。"}
            }
            .alert("删除这个卡组？",isPresented:$deleting) {
                Button("删除",role:.destructive) {
                    if let deck,let deleteServerDeck,serverDeck != nil {
                        deletingServer=true
                        Task {
                            defer {deletingServer=false}
                            do {try await deleteServerDeck(deck);dismiss()}
                            catch {if !(error is CancellationError) {deletionError=AccountStore.message(for:error)}}
                        }
                    } else {store.deleteDeck(id:deckID);dismiss()}
                }
                Button("取消",role:.cancel){}
            } message:{Text(serverDeck != nil ? "从一起来决斗删除此卡组？本地副本会保留，并解除关联。" : "删除后无法恢复。")}
            .disabled(deletingServer)
            .overlay {if deletingServer {ProgressView("正在删除服务端卡组").padding().background(.regularMaterial,in:RoundedRectangle(cornerRadius:14))}}
            .alert("删除失败",isPresented:Binding(get:{deletionError != nil},set:{if !$0 {deletionError=nil}})) {
                Button("好",role:.cancel) {deletionError=nil}
            } message:{Text(deletionError ?? "")}
            .onChange(of:deck?.mainArtworks) {_,_ in draw=DeckDrawState()}
            .navigationDestination(item:$localDestination) { DeckConfirmationScreen(deckID:$0) }
    }
    private func section(_ title: String, cards: [DeckCard], legacy: Int? = nil) -> some View {
        DeckCardPanel(title: title, format: format, cards: cards, legacyCount: legacy) { selected = $0 }
    }
}

private struct DeckCardPanel: View {
    @Environment(CardCatalog.self) private var catalog
    let title: String
    let format: CardFormat
    let cards: [DeckCard]
    var legacyCount: Int? = nil
    let select: (DeckDetailRoute) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text("\(legacyCount ?? cards.count)").font(.subheadline.monospacedDigit()).foregroundStyle(Design.secondary)
            }
            if cards.isEmpty {
                Text(legacyCount == nil ? "暂无卡牌" : "旧版卡组尚未录入逐张清单")
                    .font(.caption).foregroundStyle(Design.secondary).frame(maxWidth: .infinity, minHeight: 42)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 5), spacing: 11) {
                    ForEach(Array(cards.enumerated()), id: \.offset) { _, artwork in
                        Button {
                            Task {
                                if let card = try? await catalog.database.details(cid: artwork.cid).card {
                                    select(DeckDetailRoute(card: card, artwork: artwork))
                                }
                            }
                        } label: {
                            DeckCardArtwork(artwork: artwork, format: format)
                        }.buttonStyle(.plain).accessibilityIdentifier("deck.card.\(artwork.id)")
                    }
                }.accessibilityIdentifier("deck.zone.\(title)")
            }
        }.modifier(DeckPanel())
    }
}

struct DeckEditorScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(CardCatalog.self) private var catalog
    @Environment(\.dismiss) private var dismiss
    let deckID:String
    var draft:Deck? = nil
    @State private var original:Deck?
    @State private var session:DeckEditingSession?
    @State private var selected:DeckDetailRoute?
    @State private var drag=DeckDragState()
    @State private var coverPosition:String?
    @State private var confirmingDiscard = false
    var body:some View {
        NavigationStack {
        Group {
            if let session {
                CardBrowserScreen(embedded:true,editorHeader:AnyView(editorHeader(session)),editorWorkspace:AnyView(editorWorkspace(session)),artworkFormat:session.format,deckSession:session,deckDrag:drag) { card in
                    selected=DeckDetailRoute(card:card,artwork:DeckCard(cid:card.cid))
                }
            } else { ProgressView() }
        }.background(Design.canvas)
            .navigationTitle(draft == nil ? "编辑卡组" : "创建卡组").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ModalCloseButton(action: requestDismiss).accessibilityLabel("取消编辑").accessibilityIdentifier("deck.edit.cancel")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let session, session.canUndo || session.canRedo {
                        Button { session.undo() } label: { Image(systemName:"arrow.uturn.backward").frame(minWidth:44,minHeight:44) }
                            .disabled(!session.canUndo).accessibilityLabel("撤销").accessibilityIdentifier("deck.edit.undo")
                        Button { session.redo() } label: { Image(systemName:"arrow.uturn.forward").frame(minWidth:44,minHeight:44) }
                            .disabled(!session.canRedo).accessibilityLabel("重做").accessibilityIdentifier("deck.edit.redo")
                    }
                    Button {
                        if let original, let session {store.saveDeck(session.state.applying(to:original))};dismiss()
                    } label: {Text(draft == nil ? "保存" : "创建").foregroundStyle(.white)}.primaryActionStyle()
                        .disabled(session?.state.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty != false)
                        .accessibilityLabel(draft == nil ? "保存卡组" : "确认创建").accessibilityIdentifier("deck.edit.save")
                }
            }
            .task(id:deckID) { if session == nil, let deck=draft ?? store.decks.first(where:{$0.id == deckID}) {original=deck;session=DeckEditingSession(deck:deck,format:catalog.selectedFormat)} }
            .task(id:DeckValidationRequest(cards:Array(Set(session?.state.all.map(\.cid) ?? [])).sorted(),revision:catalog.revision)) {
                await session?.refreshLegality(database:catalog.database,revision:catalog.revision)
            }
            .sheet(item:$selected) { item in CatalogCardDetailScreen(card:item.card,deckEditor:session,initialArtwork:item.artwork.ciid) }
            .alert("无法添加卡牌",isPresented:Binding(get:{session?.error != nil},set:{if !$0{session?.error=nil}})) {Button("好",role:.cancel){session?.error=nil}} message:{Text(session?.error ?? "")}
            .interactiveDismissDisabled(session?.hasChanges == true)
            .alert("放弃本次修改？",isPresented:$confirmingDiscard) {
                Button("放弃修改",role:.destructive) {dismiss()}
                Button("继续编辑",role:.cancel) {}
            } message: {Text("本次修改尚未保存。")}
            .presentationDragIndicator(.visible).presentationDetents([.large])
        }
    }
    private func requestDismiss() {
        if session?.hasChanges == true {confirmingDiscard=true} else {dismiss()}
    }
    private func editorHeader(_ session:DeckEditingSession)->some View {
        VStack(spacing:24) {
            coverPicker(session)
            VStack(spacing:12) {
                TextField("卡组名称",text:Binding(get:{session.state.name},set:{value in session.change{$0.name=String(value.prefix(80))}}))
                    .font(.title2.bold()).multilineTextAlignment(.center).accessibilityIdentifier("deck.edit.name")
                Divider()
                TextField("描述",text:Binding(get:{session.state.description},set:{value in session.change{$0.description=String(value.prefix(2000))}}),axis:.vertical)
                    .font(.subheadline).lineLimit(2...5).accessibilityIdentifier("deck.edit.description")
            }.padding(.horizontal,22)
        }.padding(.top,8).padding(.bottom,8)
    }
    private func editorWorkspace(_ session:DeckEditingSession)->some View {
        VStack(spacing:8) {
            VStack(spacing:16) {
                Picker("卡组区域",selection:Binding(get:{session.zone},set:{session.zone=$0})) {
                    ForEach(DeckZone.allCases) {zone in Text("\(zone.rawValue) \(session.state[zone].count)").tag(zone)}
                }.pickerStyle(.segmented).accessibilityIdentifier("deck.edit.zones")
                if session.state[session.zone].isEmpty {
                    Text("从下方查找卡牌，点击卡牌后使用 + 加入卡组。").font(.subheadline).foregroundStyle(Design.secondary).frame(maxWidth:.infinity,minHeight:120)
                } else {
                    ScrollView(.horizontal,showsIndicators:false) {
                        HStack(spacing:12) {
                            ForEach(session.groups(in:session.zone)) { artwork in
                                DeckDraggableCard(content:AnyView(DeckCardArtwork(artwork:artwork,quantity:session.state[session.zone].filter{$0==artwork}.count,indicators:true,format:session.format).environment(catalog).environment(store)),source:.deck(artwork,session.zone),drag:drag,identifier:"deck.edit.card.\(artwork.id)",label:"卡牌 \(artwork.cid)，异画 \(artwork.ciid)，投入 \(session.state[session.zone].filter{$0==artwork}.count) 张",insertSearch:{target in if let target {session.move(artwork,before:target,in:session.zone)} else {session.moveToEnd(artwork,in:session.zone)}},removeDeck:{_ = session.removeArtwork(artwork,in:session.zone)},open:{open(artwork)})
                                    .frame(width:76,height:76/NeuronCardLayout.aspect)

                            }
                            Color.clear.frame(width:30,height:112).contentShape(Rectangle())

                        }.padding(.vertical,6).padding(.horizontal,3).background {DeckCardStripReporter(drag:drag)}
                    }.accessibilityIdentifier("deck.edit.strip")
                }
            }.padding(.horizontal,18).contentShape(Rectangle())

            if !session.legalityIssues.isEmpty { legalityNotice(session).padding(.horizontal,18) }
        }.padding(.top,8).padding(.bottom,10).background(Design.canvas)
            .background {DeckDropAreaReporter(drag:drag)}
    }
    private func legalityNotice(_ session:DeckEditingSession)->some View {
        Label(session.legalityIssues.first?.summary ?? "",systemImage:"exclamationmark.triangle.fill")
            .font(.caption).foregroundStyle(Design.accent).lineLimit(1)
            .frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,2)
            .accessibilityElement(children:.ignore).accessibilityLabel(session.legalityIssues.first?.summary ?? "")
            .accessibilityIdentifier("deck.edit.legality")
    }
    private func coverPicker(_ session:DeckEditingSession)->some View {
        VStack(spacing:12) {
            GeometryReader { proxy in
                ScrollView(.horizontal,showsIndicators:false) {
                    LazyHStack(spacing:16) {
                        Button {session.change{$0.cover=nil};coverPosition="default"} label:{
                            DeckGeneratedCover(name:session.state.name,seed:deckID).frame(width:220,height:220).clipShape(RoundedRectangle(cornerRadius:22))
                                .overlay(RoundedRectangle(cornerRadius:22).stroke(session.state.cover == nil ? Design.accent:.clear,lineWidth:3))
                        }.buttonStyle(.plain).id("default").accessibilityLabel("使用默认封面").accessibilityIdentifier("deck.edit.cover.default")
                        ForEach(session.state.covers) { artwork in
                            Button {session.change{$0.cover=artwork};coverPosition=artwork.id} label: {
                                DeckCoverArtwork(card:artwork).frame(width:220,height:220).clipShape(RoundedRectangle(cornerRadius:22))
                                    .overlay(RoundedRectangle(cornerRadius:22).stroke(session.state.cover==artwork ? Design.accent:.clear,lineWidth:3))
                            }.buttonStyle(.plain).id(artwork.id)
                                .accessibilityLabel("封面 \(artwork.cid)，异画 \(artwork.ciid)").accessibilityIdentifier("deck.edit.cover.\(artwork.id)")
                        }
                    }.scrollTargetLayout().padding(.vertical,4)
                }.contentMargins(.horizontal,max(18,(proxy.size.width-220)/2),for:.scrollContent).scrollTargetBehavior(.viewAligned)
                    .scrollPosition(id:$coverPosition)
                    .onAppear {if coverPosition == nil {coverPosition=session.state.cover?.id ?? "default"}}

            }.frame(height:228)
            Text(session.state.cover == nil ? "默认封面":"\((session.state.covers.firstIndex(where:{$0==session.state.cover}) ?? 0)+1) / \(session.state.covers.count)")
                .font(.caption.monospacedDigit()).foregroundStyle(Design.secondary).frame(height:12)
        }
    }
    private func open(_ artwork:DeckCard) { Task { if let card=try? await catalog.database.details(cid:artwork.cid).card {selected=DeckDetailRoute(card:card,artwork:artwork)} } }
}

struct DeckCardQuantityControls:View {
    let session:DeckEditingSession
    let card:CatalogCard
    let ciid:Int64
    @State private var side:Bool
    init(session:DeckEditingSession,card:CatalogCard,ciid:Int64) {self.session=session;self.card=card;self.ciid=ciid;_side=State(initialValue:session.zone == .side)}
    private var copies:Int {session.count(cid:card.cid,side:side)}
    private var canAdd:Bool {session.total(cid:card.cid)<3 && session.state[session.destination(for:card,side:side)].count<session.destination(for:card,side:side).capacity}
    private var primaryZone:DeckZone {session.destination(for:card,side:false)}
    private var destination:DeckZone {session.destination(for:card,side:side)}
    private var summary:String {
        "\(primaryZone == .extra ? "额外" : "主") \(session.count(cid:card.cid,side:false)) · 副 \(session.count(cid:card.cid,side:true))"
    }
    private var limitSummary:String {
        let total=session.total(cid:card.cid)
        if total>=3 {return "合计 3/3 · 已达上限"}
        if session.state[destination].count>=destination.capacity {return "\(destination.rawValue)已满"}
        return "合计 \(total)/3"
    }
    var body:some View {
        VStack(spacing:8) {
            ViewThatFits(in:.horizontal) {
                HStack(spacing:12) {
                    destinationControl
                    quantityControl
                }.frame(maxWidth:.infinity)
                VStack(spacing:10) {
                    destinationControl
                    quantityControl.frame(maxWidth:.infinity)
                }
            }
            HStack(alignment:.firstTextBaseline,spacing:12) {
                Text(summary)
                Spacer(minLength:0)
                Text(limitSummary)
            }.font(.caption.monospacedDigit()).foregroundStyle(Design.secondary)
        }.padding(.horizontal,18).padding(.vertical,12)
            .frame(maxWidth:.infinity).background(Design.canvas)
            .overlay(alignment:.top) {Divider()}
    }
    private var destinationControl:some View {
        HStack(spacing:4) {
            destinationButton(primaryZone,side:false)
            destinationButton(.side,side:true)
        }.padding(4).frame(minWidth:184)
            .background(Design.field,in:RoundedRectangle(cornerRadius:14))
            .overlay {RoundedRectangle(cornerRadius:14).strokeBorder(Color(uiColor:.separator),lineWidth:0.5)}
            .accessibilityElement(children:.contain).accessibilityLabel("投入区域")
            .accessibilityIdentifier("deck.card.destination")
    }
    private func destinationButton(_ zone:DeckZone,side value:Bool)->some View {
        Button {side=value;session.zone=zone} label:{
            Text(zone.rawValue).font(.subheadline.weight(side == value ? .semibold:.regular))
                .foregroundStyle(side == value ? Design.ink:Design.secondary)
                .padding(.horizontal,12).frame(maxWidth:.infinity,minHeight:44)
                .background(side == value ? Color(uiColor:.tertiarySystemBackground):.clear,in:RoundedRectangle(cornerRadius:10))
                .contentShape(RoundedRectangle(cornerRadius:10))
        }.buttonStyle(.plain).accessibilityAddTraits(side == value ? .isSelected:[])
            .accessibilityHint("选择增减卡牌的区域")
            .accessibilityIdentifier("deck.card.destination."+zone.id)
    }
    private var quantityControl:some View {
        HStack(spacing:0) {
            quantityButton("minus",enabled:copies>0,label:"减少投入",identifier:"deck.card.minus") {
                session.remove(card,ciid:ciid,side:side)
            }
            Text("\(copies)").font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(Design.ink)
                .frame(minWidth:40,minHeight:44)
                .accessibilityLabel("\(destination.rawValue)投入 \(copies) 张")
                .accessibilityIdentifier("deck.card.quantity")
            quantityButton("plus",enabled:canAdd,label:"增加投入",identifier:"deck.card.plus") {
                session.add(card,ciid:ciid,side:side)
            }
        }.padding(4).background(Design.field,in:RoundedRectangle(cornerRadius:14))
            .overlay {RoundedRectangle(cornerRadius:14).strokeBorder(Color(uiColor:.separator),lineWidth:0.5)}
            .fixedSize(horizontal:true,vertical:false)
    }
    private func quantityButton(_ symbol:String,enabled:Bool,label:String,identifier:String,action:@escaping ()->Void)->some View {
        Button(action:action) {
            Image(systemName:symbol).font(.system(size:17,weight:.semibold))
                .foregroundStyle(enabled ? Design.accent:Design.secondary)
                .frame(width:44,height:44).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!enabled).accessibilityLabel(label).accessibilityIdentifier(identifier)
    }

}

struct RemoteDeckPlazaScreen: View {
    @Environment(AccountStore.self) private var account

    var body: some View {
        RemoteDeckListScreen().id(account.sessionVersion)
            .navigationTitle("卡组广场").navigationBarTitleDisplayMode(.large)
    }
}

private struct RemoteDeckListScreen: View {
    @Environment(AccountStore.self) private var account
    @Environment(AppStore.self) private var store
    @State private var decks: [Deck]?
    @State private var loadedUserID:String?
    @State private var failure: String?
    @State private var loading = false
    @State private var showingLogin = false

    var body: some View {
        Group {
            if !account.isLoggedIn {
                ContentUnavailableView {
                    Label("一起来决斗 · 我的牌组", systemImage: "person.crop.circle")
                } description: {
                    Text("登录一起来决斗账号后查看。")
                } actions: {
                    Button("登录") { showingLogin = true }.buttonStyle(.borderedProminent)
                }
            } else if let decks {
                DeckLibraryScreen(serverDecks:decks,deleteServerDeck:remove)
                    .refreshable { await reload() }
                    .safeAreaInset(edge:.bottom) {
                        if let failure { Text(failure).font(.footnote).padding().foregroundStyle(.secondary) }
                    }
            } else if let failure {
                ContentUnavailableView {
                    Label("无法加载牌组", systemImage: "icloud.slash")
                } description: {
                    Text(failure)
                } actions: {
                    Button("重试") { Task { await reload() } }.buttonStyle(.bordered)
                }
            } else {
                ProgressView("正在读取牌组")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Design.canvas)
        .task { if decks == nil { await reload() } }
        .sheet(isPresented: $showingLogin) { LoginSheet() }
    }

    private func reload() async {
        guard account.isLoggedIn, !loading else { return }
        loading = true
        failure = nil
        defer { loading = false }
        do {
            let session = try await RemoteDeckSession(account: account)
            let summaries = try await session.list()
            var snapshots:[Deck]=[]
            for summary in summaries {
                let detail=try await session.detail(summary)
                snapshots.append(try detail.deckSnapshot())
            }
            loadedUserID=session.userID
            decks=snapshots
        } catch {
            if !(error is CancellationError) { failure = AccountStore.message(for: error) }
        }
    }
    private func remove(_ deck:Deck) async throws {
        guard let loadedUserID,loadedUserID==account.session?.userID else {throw CancellationError()}
        let session=try await RemoteDeckSession(account:account)
        try await session.delete(id:deck.id)
        store.forgetRemoteDeck(deck.id,userID:session.userID)
        decks?.removeAll {$0.id==deck.id}
    }
}

struct RemoteDeckUploadScreen: View {
    @Environment(AccountStore.self) private var account
    @Environment(AppStore.self) private var store
    @Environment(CardCatalog.self) private var catalog
    @Environment(\.dismiss) private var dismiss
    let deck: Deck
    var onSaved: ((String) -> Void)? = nil
    @State private var saving = false
    @State private var showingLogin = false
    @State private var failure: String?
    @State private var completed = false
    @State private var missingRemoteID:String?
    @State private var confirmingReupload=false

    private var local: Deck { store.myDecks.first { $0.id == deck.id } ?? deck }
    private var linked: Bool {
        guard let userID = account.session?.userID else { return false }
        return local.remoteDeckIDs?[userID] != nil
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DeckListRow(deck:local,format:local.banlist.flatMap(CardFormat.init(rawValue:)) ?? catalog.selectedFormat)
                        .padding(.vertical,6)
                } footer: {
                    if account.isLoggedIn && !completed {
                        Text(linked ? "更新一起来决斗中已关联的卡组。" : "上传为非公开卡组，并与本地卡组关联。之后可在本地修改，再次上传。")
                    }
                }
                if let failure {Section {Text(failure).font(.footnote).foregroundStyle(Design.secondary)}}
                if completed {Section {Label("已上传到一起来决斗",systemImage:"checkmark.circle.fill").foregroundStyle(.green)}}
            }.listStyle(.insetGrouped).scrollContentBackground(.hidden).background(Design.canvas)
            .navigationTitle("上传卡组").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ModalCloseButton().disabled(saving)
                }
            }
            .safeAreaInset(edge:.bottom) {
                DeckActionBar {
                    if !account.isLoggedIn {
                        AccentButton(title:"登录一起来决斗") {showingLogin=true}
                    } else if completed {
                        AccentButton(title:"完成") {dismiss()}
                    } else if missingRemoteID != nil {
                        AccentButton(title:"重新上传为新卡组",isLoading:saving) {confirmingReupload=true}
                    } else {
                        AccentButton(title:saving ? "正在上传" : "上传卡组",isLoading:saving) {
                            saving=true
                            Task {await upload()}
                        }
                    }
                }
            }
            .sheet(isPresented: $showingLogin) { LoginSheet() }
            .confirmationDialog("重新上传为新卡组？",isPresented:$confirmingReupload,titleVisibility:.visible) {
                Button("新建非公开卡组并关联") {
                    missingRemoteID=nil
                    saving=true
                    Task {await upload()}
                }
            } message:{Text("原服务端卡组已删除，此操作会将当前本地卡组上传为一份新的非公开卡组。")}
            .onChange(of: account.sessionVersion) { _, _ in
                completed = false
                failure = nil
                missingRemoteID=nil
            }
            .interactiveDismissDisabled(saving)
        }
    }

    private func upload() async {
        failure = nil
        defer { saving = false }
        do {
            let local = self.local
            let format = local.banlist.flatMap(CardFormat.init(rawValue:)) ?? catalog.selectedFormat
            let session = try await RemoteDeckSession(account: account)
            let list = try await session.list()
            let draftName = "Vrains-\(local.id)"
            let detail: RemoteDeckDetail
            let cards: [RemoteDeckCard]
            if let id = local.remoteDeckIDs?[session.userID] {
                guard let linked = list.first(where: { $0.id == id }) else {
                    store.forgetRemoteDeck(id,userID:session.userID)
                    missingRemoteID=id
                    failure="关联的服务端卡组已删除。本地卡组已保留，可以重新上传为新卡组。"
                    return
                }
                detail = try await session.detail(linked)
                let existingCards = detail.summary.format == format ? detail.cards : []
                cards = try await RemoteDeckCard.payload(for: local, format: format, keeping: existingCards, database: catalog.database)
            } else {
                cards = try await RemoteDeckCard.payload(for: local, format: format, keeping: [], database: catalog.database)
                let summary: RemoteDeckSummary
                if let draft = list.first(where: { $0.name == draftName && $0.status == "非公开" }) {
                    summary = draft
                } else {
                    try await session.createDraft(name: draftName)
                    guard let draft = try await session.list().first(where: { $0.name == draftName && $0.status == "非公开" }) else {
                        throw RemoteDeckError.ambiguousCreate
                    }
                    summary = draft
                }
                store.rememberRemoteDeck(summary.id, for: local.id, userID: session.userID)
                detail = try await session.detail(summary)
            }
            var write = local
            write.banlist = format.rawValue
            try await session.save(deck: write, replacing: detail, cards: cards)
            completed = true
            onSaved?(detail.summary.id)
        } catch {
            if !(error is CancellationError) { failure = AccountStore.message(for: error) }
        }
    }
}
