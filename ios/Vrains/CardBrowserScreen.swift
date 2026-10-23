import SwiftUI
import UniformTypeIdentifiers

private struct CardSearchRequest: Hashable {
    let keyword: String
    let filter: CardFilter
    let favorites: Set<String>
    let revision: Int
}

private enum CardBrowserViewMode { case list, artwork }
private struct DeckWorkspaceHeightKey:PreferenceKey {
    static let defaultValue:CGFloat=0
    static func reduce(value:inout CGFloat,nextValue:()->CGFloat){value=max(value,nextValue())}
}
private struct DeckBrowserViewportKey:PreferenceKey {
    static let defaultValue:CGRect = .zero
    static func reduce(value:inout CGRect,nextValue:()->CGRect){value=nextValue()}
}

struct SearchScreen: View {
    var body: some View { CardBrowserScreen() }
}

struct CardBrowserScreen: View {
    @Environment(CardCatalog.self) private var catalog
    @Environment(AppStore.self) private var store
    let embedded: Bool
    let editorHeader: AnyView?
    let editorWorkspace: AnyView?
    let artworkFormat: CardFormat?
    let deckSession:DeckEditingSession?
    let deckDrag:DeckDragState?
    let favoritesMode: Bool
    let selectionTitle:String?
    let cardSelection:((CatalogCard)->Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var keyword = ""
    @State private var draftKeyword = ""
    @State private var filter: CardFilter
    @State private var results: [CatalogCard] = []
    @State private var count = 0
    @State private var loading = false
    @State private var generation = UUID()
    @State private var loadedRequest: CardSearchRequest?
    @State private var topCardID: Int64?
    @State private var errorMessage: String?
    @State private var selectedCard: CatalogCard?
    @State private var showingFilters = false
    @State private var viewMode: CardBrowserViewMode = .list
    @State private var viewportHeight:CGFloat=0
    @State private var workspaceHeight:CGFloat=0
    @State private var resetScroll=UUID()
    @FocusState private var searchFocused: Bool
    init(favoritesMode: Bool = false,selectionTitle:String?=nil,embedded:Bool=false,editorHeader:AnyView?=nil,editorWorkspace:AnyView?=nil,artworkFormat:CardFormat?=nil,deckSession:DeckEditingSession?=nil,deckDrag:DeckDragState?=nil,cardSelection:((CatalogCard)->Void)?=nil) {
        self.embedded=embedded; self.editorHeader=editorHeader;self.editorWorkspace=editorWorkspace;self.artworkFormat=artworkFormat;self.deckSession=deckSession;self.deckDrag=deckDrag
        self.favoritesMode = favoritesMode
        self.selectionTitle=selectionTitle;self.cardSelection=cardSelection
        var initial = CardFilter(); initial.favoritesOnly = favoritesMode
        if let artworkFormat {initial.format=artworkFormat}
        _filter = State(initialValue: initial)
        _viewMode = State(initialValue:embedded ? .artwork:.list)
    }
    private var request: CardSearchRequest {
        var effective = filter
        if favoritesMode { effective.favoritesOnly = true }
        return CardSearchRequest(keyword: keyword, filter: effective, favorites: effective.favoritesOnly ? store.savedCards : [], revision: catalog.revision)
    }
    @ViewBuilder var body: some View {
        if embedded { browserContents }
        else if #available(iOS 18.0, *) { searchableBody.searchFocused($searchFocused) }
        else { searchableBody }
    }
    private var browserContents: some View {
        VStack(spacing:0) {
            if !embedded {browserControls}
            ScrollViewReader { position in
            ScrollView {
                LazyVStack(spacing:24,pinnedViews:embedded ? [.sectionHeaders]:[]) {
                    if embedded {
                        editorHeader
                        Section {resultsContent} header: {embeddedWorkspace}
                    } else {resultsContent}
                }
            }.scrollDismissesKeyboard(.interactively).accessibilityIdentifier("cards.scroll")
                .automaticPagination(itemCount:results.count,canLoadMore:results.count<count && errorMessage == nil,isLoading:loading,prefetchScreens:1.5){await load(request,reset:false)}
                .scrollPosition(id:embedded ? .constant(nil):$topCardID,anchor:.top)
                .background {GeometryReader {proxy in Color.clear.preference(key:DeckBrowserViewportKey.self,value:proxy.frame(in:.global))}}
                .onPreferenceChange(DeckBrowserViewportKey.self) {rect in viewportHeight=rect.height}
                .onPreferenceChange(DeckWorkspaceHeightKey.self) {height in if height>0 {workspaceHeight=height}}
                .onChange(of:resetScroll) {_,_ in if !embedded {position.scrollTo("cards.results.top",anchor:.top)}}
            }

        }.background(Design.canvas)
            .task(id: request) {
                let preserve = loadedRequest.map { $0.keyword == request.keyword && $0.filter == request.filter && $0.revision == request.revision } ?? false
                await load(request, reset: true, preserveResults: preserve)
            }
            .sheet(item: $selectedCard) { CatalogCardDetailScreen(card: $0) }
            .sheet(isPresented: $showingFilters) { CardFilterSheet(filter: $filter, favoritesMode: favoritesMode) }
            .presentationDragIndicator(favoritesMode ? .visible : .automatic).presentationCornerRadius(32)
    }
    private var embeddedWorkspace:some View {
        VStack(spacing:14) {
            editorWorkspace
            embeddedSearchField
            browserControls.modifier(DeckSearchDropRegion(session:deckSession,drag:deckDrag))
        }.background(Design.canvas)
            .background {GeometryReader {proxy in Color.clear.preference(key:DeckWorkspaceHeightKey.self,value:proxy.size.height)}}
    }
    private var embeddedSearchField:some View {
        HStack(spacing:10) {
            Image(systemName:"magnifyingglass").foregroundStyle(Design.secondary)
            TextField("卡牌名或效果文本",text:$draftKeyword).submitLabel(.search).focused($searchFocused).autocorrectionDisabled()
                .onSubmit {submitSearch()}.accessibilityIdentifier("deck.search.field")
            if !draftKeyword.isEmpty {Button {draftKeyword="";submitSearch()} label:{Image(systemName:"xmark.circle.fill")}}
        }.padding(14).background(Design.field,in:Capsule()).padding(.horizontal,18)
            .modifier(DeckSearchDropRegion(session:deckSession,drag:deckDrag))
    }
    private var resultsContent:some View {
        VStack(alignment: .leading, spacing: 16) {
                if let errorMessage { Text(errorMessage).font(.subheadline).foregroundStyle(Design.accent) }
                if !loading, results.isEmpty, errorMessage == nil {
                    EmptyState(icon: "rectangle.on.rectangle", title: favoritesMode ? "收藏你的心动" : "没有找到匹配卡片", subtitle: "换个关键词，或调整筛选条件。")
                }
                if viewMode == .list {
                    LazyVStack(spacing: 12) {
                        ForEach(results) { card in
                            CatalogCardRow(card: card,format:artworkFormat) { open(card) }.id(card.cid)
                        }
                        InfiniteScrollFooter(itemCount: results.count, canLoadMore: results.count < count && errorMessage == nil, isLoading: loading) {
                            await load(request, reset: false)
                        }
                    }.scrollTargetLayout()
                } else {
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:62,maximum:84),spacing:8)],spacing:10) {
                        ForEach(results) { card in
                            Group {
                                if let deckDrag,let deckSession {
                                    DeckSearchDraggableTile(card:card,format:artworkFormat,drag:deckDrag,session:deckSession){open(card)}
                                } else { CatalogCardArtworkTile(card:card,format:artworkFormat){open(card)} }
                            }
                            // The attribute ring extends above the card. Keep this inset inside
                            // each scroll target so restoring a top-row anchor cannot clip it.
                            .padding(.top,4).id(card.cid)
                        }
                        InfiniteScrollFooter(itemCount: results.count, canLoadMore: results.count < count && errorMessage == nil, isLoading: loading) {
                            await load(request, reset: false)
                        }.gridCellColumns(2)
                    }
                    .scrollTargetLayout()
                }
            }.padding(.horizontal, viewMode == .list ? 22:12).padding(.bottom, 24)
                .frame(maxWidth:.infinity,minHeight:embedded ? max(120,viewportHeight-workspaceHeight-24):120,alignment:.top)
                .modifier(DeckSearchDropRegion(session:deckSession,drag:deckDrag))
                .id("cards.results.top")
    }
    private var browserControls: some View {
            VStack(alignment: .leading, spacing: 21) {
                if let selectionTitle {
                    HStack {
                        Text(selectionTitle).font(.title2.bold()).foregroundStyle(Design.ink)
                        Spacer()
                        selectionDoneButton
                    }
                }
                if favoritesMode {
                    HStack { GlassBackButton(); Text("我的收藏").font(.title2.bold()); Spacer(); filterButton }
                }
                if !favoritesMode || !keyword.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 9) {
                            if !keyword.isEmpty { keywordChip }
                            if !favoritesMode {
                            quickFilter("所有", type: 0)
                            quickFilter("怪兽", type: 1)
                            quickFilter("魔法", type: 2)
                            quickFilter("陷阱", type: 4)
                            quickFilter("收藏", type: 0, favorites: true)
                            }
                        }
                    }
                }
                HStack {
                    Text("\(count.formatted()) 张卡片").font(.system(size: 18, weight: .semibold)).foregroundStyle(Design.ink)
                        .accessibilityIdentifier("cards.result.count")
                        .accessibilityValue("已显示 \(results.count) 张")
                    Spacer()
                    viewModeButton
                    if !favoritesMode { filterButton }
                    Menu {
                        Picker("排序依据", selection: $filter.sort) {
                            ForEach(CardSort.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Divider()
                        Picker("顺序",selection:$filter.sortAscending) {
                            Text("升序").tag(true);Text("降序").tag(false)
                        }
                    } label: {
                        Label(filter.sort.rawValue, systemImage: filter.sortAscending ? "arrow.up":"arrow.down")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Design.secondary)
                    }.accessibilityLabel("卡片排序").accessibilityValue("\(filter.sort.rawValue) · \(filter.sortAscending ? "升序":"降序")").accessibilityIdentifier("cards.sort")
                }
            }.padding(.horizontal, 22).padding(.top, favoritesMode ? 24 : 0).padding(.bottom, 16)
    }
    private var searchableBody: some View {
        NavigationStack {
            browserContents
            .navigationTitle(selectionTitle == nil ? (favoritesMode ? "":"查找") : "")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text:$draftKeyword,placement:.navigationBarDrawer(displayMode:.always),prompt:"卡牌名或效果文本")
            .stableSearchToolbar()
            .onSubmit(of:.search) { submitSearch() }
            .autocorrectionDisabled()
        }
    }
    @ViewBuilder private var selectionDoneButton:some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0,*) {
            Button { dismiss() } label:{Image(systemName:"checkmark").frame(width:32,height:32)}
                .buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.small)
                .accessibilityLabel("完成选卡").accessibilityIdentifier("cards.selection.done")
        } else { legacySelectionDoneButton }
        #else
        legacySelectionDoneButton
        #endif
    }
    private var legacySelectionDoneButton:some View {
        Button { dismiss() } label:{Image(systemName:"checkmark").frame(width:44,height:44).background(Design.surface,in:Circle())}
            .buttonStyle(.plain).accessibilityLabel("完成选卡").accessibilityIdentifier("cards.selection.done")
    }
    private var keywordChip: some View {
        HStack(spacing: 0) {
            Button {
                draftKeyword=keyword;searchFocused=true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold))
                    Text(keyword).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                }.padding(.leading, 14).padding(.vertical, 11).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("编辑搜索：\(keyword)").accessibilityIdentifier("cards.keyword.edit")
            Button {
                keyword = ""; draftKeyword = ""
            } label: {
                Image(systemName:"xmark").font(.system(size:10,weight:.semibold)).frame(width:46,height:46).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("清除关键词").accessibilityIdentifier("cards.keyword.clear")
        }.foregroundStyle(Design.accent).background(Design.accent.opacity(0.09), in: Capsule())
    }
    private func submitSearch() {
        keyword=draftKeyword.trimmingCharacters(in:.whitespacesAndNewlines)
        draftKeyword=keyword;searchFocused=false
    }
    private func open(_ card:CatalogCard) {
        if let cardSelection {cardSelection(card)} else {selectedCard=card}
    }
    @ViewBuilder private var viewModeButton:some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0,*) {
            Button { viewMode = viewMode == .list ? .artwork:.list } label:{viewModeLabel}
                .buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.small)
                .accessibilityLabel("切换卡片视图").accessibilityValue(viewMode == .list ? "列表":"卡图")
                .accessibilityIdentifier("cards.view.toggle")
        } else { legacyViewModeButton }
        #else
        legacyViewModeButton
        #endif
    }
    private var viewModeLabel:some View {
        Image(systemName:viewMode == .list ? "square.grid.2x2":"list.bullet").frame(width:32,height:32)
    }
    private var legacyViewModeButton:some View {
        Button { viewMode = viewMode == .list ? .artwork:.list } label:{viewModeLabel.background(Design.surface,in:Circle())}
            .buttonStyle(.plain).accessibilityLabel("切换卡片视图").accessibilityValue(viewMode == .list ? "列表":"卡图")
            .accessibilityIdentifier("cards.view.toggle")
    }
    @ViewBuilder private var filterButton: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0,*) {
            Button { showingFilters=true } label:{filterLabel}
                .buttonStyle(.glass).buttonBorderShape(.capsule).controlSize(.small)
                .accessibilityLabel("筛选卡片").accessibilityValue(filter.activeCount>0 ? "已应用 \(filter.activeCount) 个条件":"没有附加条件").accessibilityIdentifier("cards.filters")
        } else { legacyFilterButton }
        #else
        legacyFilterButton
        #endif
    }
    private var filterLabel:some View {
        HStack(spacing:5) {
            Image(systemName:"line.3.horizontal.decrease")
            if filter.activeCount>0 { Text("\(filter.activeCount)").font(.caption.bold()) }
        }.frame(minWidth:32,minHeight:32)
    }
    private var legacyFilterButton:some View {
        Button { showingFilters=true } label:{filterLabel.padding(.horizontal,8).background(Design.surface,in:Capsule())}
            .buttonStyle(.plain).accessibilityLabel("筛选卡片").accessibilityValue(filter.activeCount>0 ? "已应用 \(filter.activeCount) 个条件":"没有附加条件").accessibilityIdentifier("cards.filters")
    }
    private func quickFilter(_ title: String, type: Int64, favorites: Bool = false) -> some View {
        let selected = filter.baseType == type && filter.favoritesOnly == favorites
        let color=categoryColor(type:type,favorites:favorites)
        return Button { applyQuickCategory(type:type,favorites:favorites) } label: {
            Text(title).font(.system(size:12,weight:.semibold)).foregroundStyle(selected ? .white:color)
                .padding(.horizontal,18).padding(.vertical,11).background(selected ? color:color.opacity(0.13),in:Capsule())
        }.buttonStyle(.plain).accessibilityIdentifier("cards.quick.\(favorites ? "favorites":String(type))").accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func categoryColor(type:Int64,favorites:Bool)->Color {
        if favorites{return Design.accent}
        switch type { case CardVocabulary.monster:return Color(hex:0xC66A38);case CardVocabulary.spell:return Color(hex:0x2E8B78);case CardVocabulary.trap:return Color(hex:0x8A5AA8);default:return Color(hex:0x60718E) }
    }
    private func applyQuickCategory(type:Int64,favorites:Bool) {
        filter.baseType=type;filter.favoritesOnly=favorites
    }
    private func load(_ request: CardSearchRequest, reset: Bool, preserveResults: Bool = false) async {
        if !reset, loading || results.count >= count || errorMessage != nil || request != self.request { return }
        let version = reset ? UUID() : generation
        let window = preserveResults ? max(40, results.count) : 40
        let currentAnchor = topCardID
        let anchorIndex = currentAnchor.flatMap { id in results.firstIndex(where: { $0.cid == id }) }
        let nearbyIDs = anchorIndex.map { Array(results.dropFirst($0).map(\.cid)) + Array(results.prefix($0).reversed().map(\.cid)) } ?? []
        if reset {
            generation = version
        }
        loading = true; errorMessage = nil
        defer { if version == generation { loading = false } }
        do {
            #if DEBUG
            if !reset, ProcessInfo.processInfo.arguments.contains("--uitesting-slow-pagination") { try await Task.sleep(for: .seconds(4)) }
            #endif
            let offset = reset ? 0 : results.count
            let response = try await catalog.database.search(keyword: request.keyword, filter: request.filter, favorites: request.favorites, offset: offset, limit: min(window, 200))
            var refreshed = response.cards
            if reset, preserveResults {
                while refreshed.count < min(window, response.count) {
                    try Task.checkCancellation()
                    let next = try await catalog.database.search(keyword: request.keyword, filter: request.filter, favorites: request.favorites, offset: refreshed.count, limit: min(window - refreshed.count, 200))
                    guard !next.cards.isEmpty else { break }
                    refreshed += next.cards
                }
            }
            try Task.checkCancellation()
            guard generation == version else { return }
            results = reset ? refreshed : results + refreshed
            count = response.count
            loadedRequest = request
            if reset, !preserveResults { topCardID=nil;resetScroll=UUID() }
            if preserveResults {
                let remaining = Set(results.map(\.cid))
                topCardID = nearbyIDs.first(where: { remaining.contains($0) }) ?? results.first?.cid
            }
        } catch is CancellationError { }
        catch { if generation == version { errorMessage = error.localizedDescription } }
    }
}

struct CatalogCardRow: View {
    @Environment(CardCatalog.self) private var catalog
    @Environment(AppStore.self) private var store
    let card: CatalogCard
    var format:CardFormat? = nil
    var open: () -> Void
    @State private var allowedCopies:Int?
    @ScaledMetric(relativeTo:.body) private var scaledRowHeight:CGFloat=178
    @ScaledMetric(relativeTo:.body) private var scaledArtworkWidth:CGFloat=78
    @ScaledMetric(relativeTo:.body) private var scaledArtworkHeight:CGFloat=113
    @ScaledMetric(relativeTo:.body) private var scaledStatsHeight:CGFloat=25
    @ScaledMetric(relativeTo:.body) private var scaledColumnSpacing:CGFloat=14
    @ScaledMetric(relativeTo:.body) private var scaledPadding:CGFloat=14
    @ScaledMetric(relativeTo:.body) private var scaledNameSize:CGFloat=15
    @ScaledMetric(relativeTo:.body) private var scaledTypeSize:CGFloat=11
    @ScaledMetric(relativeTo:.body) private var scaledEffectSize:CGFloat=12
    @ScaledMetric(relativeTo:.body) private var scaledStatsSize:CGFloat=10
    @ScaledMetric(relativeTo:.body) private var scaledAttributeIconSize:CGFloat=22
    private var saved: Bool { store.savedCards.contains(card.favoriteKey) || card.passcode.map { store.savedCards.contains(String($0)) } == true }
    private var limitCopies: Int? { allowedCopies.flatMap { $0 < 3 ? $0 : nil } }
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: open) {
                HStack(alignment:.top,spacing:scaledColumnSpacing) {
                    VStack(spacing: 5) {
                        NeuronCardThumbnail(card:card,copies:limitCopies)
                            .frame(width:scaledArtworkWidth,height:scaledArtworkHeight)
                            .accessibilityElement(children:.contain)
                            .accessibilityIdentifier("cards.artwork.frame.\(card.cid)")
                            .accessibilityValue(limitCopies.map { ["禁止","限制","准限制"][$0] } ?? "无限制")
                        VStack(spacing: 1) {
                            if card.isMonster {
                                HStack(spacing: 3) { Text("ATK").foregroundStyle(Design.secondary);Spacer(minLength:0);Text(stat(card.attack)).foregroundStyle(Design.ink) }
                                if card.levelKind != "link" {
                                    HStack(spacing: 3) { Text("DEF").foregroundStyle(Design.secondary);Spacer(minLength:0);Text(stat(card.defense)).foregroundStyle(Design.ink) }
                                } else { Color.clear.frame(height:scaledStatsHeight/2) }
                            } else { Color.clear.frame(height:scaledStatsHeight) }
                        }.font(.system(size:scaledStatsSize,weight:.medium,design:.monospaced)).frame(height:scaledStatsHeight)
                    }.frame(width:scaledArtworkWidth)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(card.name).font(.system(size:scaledNameSize,weight:.semibold)).foregroundStyle(Design.ink)
                            .multilineTextAlignment(.leading).lineLimit(2).padding(.trailing, 28)
                        Text(card.compactTypeLine).font(.system(size:scaledTypeSize,weight:.medium)).foregroundStyle(Design.secondary).lineLimit(2)
                        Text(previewText).font(.system(size:scaledEffectSize)).lineSpacing(2).foregroundStyle(Design.ink.opacity(0.82))
                            .multilineTextAlignment(.leading).lineLimit(5)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }.padding(scaledPadding).frame(height:scaledRowHeight,alignment:.top).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("cards.row.\(card.cid)")
            Button { toggleFavorite() } label: {
                Image(systemName: saved ? "heart.fill" : "heart").font(.system(size: 18))
                    .foregroundStyle(saved ? Design.accent : Design.secondary.opacity(0.7)).frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(saved ? "取消收藏\(card.name)" : "收藏\(card.name)")
                .accessibilityIdentifier("cards.favorite.\(card.cid)").padding(.top, 5).padding(.trailing, 6)
        }.background(Design.surface,in:RoundedRectangle(cornerRadius:20))
            .task(id:"\(card.cid)-\((format ?? catalog.selectedFormat).rawValue)-\(catalog.revision)") {
                allowedCopies=try? await catalog.database.artworkLimit(cid:card.cid,format:format ?? catalog.selectedFormat)
            }
    }
    private var previewText: String {
        let text = card.description.isEmpty ? "暂无公开效果文本" : card.description
        return card.pendulumDescription.isEmpty ? text : "【灵摆】" + card.pendulumDescription + "\n【怪兽】" + text
    }
    private func stat(_ value: Int64?) -> String { value.map { $0 < 0 ? "?" : String($0) } ?? "—" }
    private func toggleFavorite() {
        if saved {
            store.savedCards.remove(card.favoriteKey)
            if let password = card.passcode { store.savedCards.remove(String(password)) }
        } else { store.savedCards.insert(card.favoriteKey) }
    }
}

private struct CatalogCardArtworkTile:View {
    let card:CatalogCard
    var format:CardFormat? = nil
    var open:()->Void
    var body:some View {
        Button(action:open) { CardGridArtwork(card:card,format:format) }
            .buttonStyle(.plain).accessibilityLabel(card.name).accessibilityIdentifier("cards.grid.\(card.cid)")
    }
}

struct CardGridArtwork:View {
    @Environment(CardCatalog.self) private var catalog
    let card:CatalogCard
    var ciid:Int64? = nil
    var showsIndicators = true
    var format:CardFormat? = nil
    @State private var allowedCopies:Int?
    private var limitCopies:Int? {allowedCopies.flatMap{$0<3 ? $0:nil}}
    var body:some View {
        NeuronCardThumbnail(card:card,ciid:ciid,copies:limitCopies,indicators:showsIndicators)
            .task(id:"\(card.cid)-\((format ?? catalog.selectedFormat).rawValue)-\(catalog.revision)") {allowedCopies=try? await catalog.database.artworkLimit(cid:card.cid,format:format ?? catalog.selectedFormat)}
    }
}

struct CardFilterSheet: View {
    @Binding var filter: CardFilter
    let favoritesMode: Bool
    @State private var draft: CardFilter
    @State private var error: String?
    @State private var availableRarities: [String] = []
    @Environment(CardCatalog.self) private var catalog
    @Environment(\.dismiss) private var dismiss
    init(filter: Binding<CardFilter>, favoritesMode: Bool = false) {
        _filter = filter; self.favoritesMode = favoritesMode; _draft = State(initialValue: filter.wrappedValue)
    }
    var body: some View {
        NavigationStack {
            Form {
                banlistSection
                attributeSection
                spellSection
                trapSection
                raceSection
                monsterTypeSection
                valueSection("等级 / 阶级", values: 0...13, selection: $draft.selectedLevels, color: Design.accent, prefix: "level")
                valueSection("灵摆刻度", values: 0...13, selection: $draft.selectedScales, color: Design.accent, prefix: "scale")
                linkSection
                statSection
                raritySection
                releaseDateSection
            }.navigationTitle("筛选").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) {
                        Button { dismiss() } label: { Image(systemName:"xmark") }
                            .accessibilityLabel("取消").accessibilityIdentifier("cards.filters.cancel")
                    }
                    ToolbarItemGroup(placement:.confirmationAction) {
                        Button(role:.destructive) { reset() } label: { Image(systemName:"arrow.counterclockwise") }
                            .accessibilityLabel("重置所有条件").accessibilityIdentifier("cards.filters.reset")
                        Button { apply() } label: { Image(systemName:"checkmark") }
                            .accessibilityLabel("应用筛选").accessibilityIdentifier("cards.filters.apply")
                    }
                }
        }.background(Design.canvas).presentationDragIndicator(.visible).presentationCornerRadius(32)
            .alert("筛选条件有误",isPresented:Binding(get:{error != nil},set:{if !$0{error=nil}})) { Button("好",role:.cancel){} } message:{Text(error ?? "")}
            .task { availableRarities = (try? await catalog.database.availableRarities()) ?? [] }
    }
    private var banlistSection:some View {
        Section("禁限规则") {
            Picker("禁卡表",selection:$draft.format) {
                ForEach(CardFormat.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.menu).accessibilityIdentifier("cards.filter.banlist.format")
            LazyVGrid(columns:[GridItem(.adaptive(minimum:82),spacing:8)],spacing:8) {
                ForEach(Array(["禁止","限制","准限制","无限制"].enumerated()),id:\.offset) { copies,title in
                    flagChoice(title,flag:Int64(1)<<copies,selection:$draft.limitStatuses,color:Design.accent,identifier:"cards.filter.banlist.status.\(copies)")
                }
            }.padding(.vertical,4)
        }
    }
    private var attributeSection:some View {
        Section("属性") { chipGrid(CardVocabulary.attributes, selection:$draft.attribute, prefix:"attribute") }
    }
    private var spellSection:some View {
        Section("魔法") {
            LazyVGrid(columns:[GridItem(.adaptive(minimum:76),spacing:8)],spacing:8) {
                ForEach(CardVocabulary.spellKinds) { option in
                    if option.id == 0 {
                        choice(option.title,selected:draft.includesNormalSpell,color:Design.accent,identifier:"cards.filter.spell.normal") { draft.includesNormalSpell.toggle() }
                    } else {
                        flagChoice(option.title,flag:option.id,selection:$draft.spellKinds,color:Design.accent,identifier:"cards.filter.spell.\(option.id)")
                    }
                }
            }.padding(.vertical,4)
        }
    }
    private var trapSection:some View {
        Section("陷阱") {
            LazyVGrid(columns:[GridItem(.adaptive(minimum:76),spacing:8)],spacing:8) {
                ForEach(CardVocabulary.trapKinds) { option in
                    if option.id == 0 {
                        choice(option.title,selected:draft.includesNormalTrap,color:Design.accent,identifier:"cards.filter.trap.normal") { draft.includesNormalTrap.toggle() }
                    } else {
                        flagChoice(option.title,flag:option.id,selection:$draft.trapKinds,color:Design.accent,identifier:"cards.filter.trap.\(option.id)")
                    }
                }
            }.padding(.vertical,4)
        }
    }
    private var raceSection:some View {
        Section("种族") { chipGrid(CardVocabulary.races,selection:$draft.race,prefix:"race") }
    }
    private var monsterTypeSection:some View {
        Section {
            Picker("组内关系",selection:$draft.monsterTypeMatchAll) { Text("或").tag(false);Text("与").tag(true) }
                .pickerStyle(.segmented).accessibilityIdentifier("cards.filter.monster.relation")
            LazyVGrid(columns:[GridItem(.adaptive(minimum:88),spacing:8)],spacing:8) {
                ForEach(CardVocabulary.monsterTypes) { option in
                    triStateChoice(option)
                }
            }.padding(.vertical,4)
        } header: { Text("怪兽种类") }
    }
    private func valueSection(_ title:String,values:ClosedRange<Int>,selection:Binding<Int64>,color:Color,prefix:String)->some View {
        Section(title) {
            LazyVGrid(columns:[GridItem(.adaptive(minimum:48),spacing:8)],spacing:8) {
                ForEach(Array(values),id:\.self) { value in
                    flagChoice(String(value),flag:Int64(1)<<value,selection:selection,color:color,identifier:"cards.filter.\(prefix).\(value)")
                }
            }.padding(.vertical,4)
        }
    }
    private var linkSection:some View {
        Section("连接") {
            LazyVGrid(columns:[GridItem(.adaptive(minimum:48),spacing:8)],spacing:8) {
                ForEach(1...6,id:\.self) { value in
                    flagChoice(String(value),flag:Int64(1)<<value,selection:$draft.selectedLinkRatings,color:Design.accent,identifier:"cards.filter.link.value.\(value)")
                }
            }.padding(.vertical,4)
            HStack {
                Text("连接箭头").font(.subheadline.weight(.semibold)).foregroundStyle(Design.secondary)
                Spacer()
                Picker("箭头关系",selection:$draft.linkMarkerMatchAll) { Text("或").tag(false);Text("与").tag(true) }
                    .pickerStyle(.segmented).frame(width:130).accessibilityIdentifier("cards.filter.link.relation")
            }
            NeuronLinkMarkers(markers:draft.linkMarkers,selection:$draft.linkMarkers)
                .frame(width:176,height:176).frame(maxWidth:.infinity).padding(.vertical,4)
        }
    }
    private var statSection:some View {
        Section("ATK / DEF") {
            NumericRangeFilter(title:"ATK",minimum:$draft.minAttack,maximum:$draft.maxAttack,includeUnknown:$draft.unknownAttack,bounds:0...5000,step:50,identifier:"atk",color:Design.accent)
            NumericRangeFilter(title:"DEF",minimum:$draft.minDefense,maximum:$draft.maxDefense,includeUnknown:$draft.unknownDefense,bounds:0...5000,step:50,identifier:"def",color:Design.accent)
        }
    }
    private var raritySection:some View {
        Section("罕贵度") {
            Menu {
                ForEach(availableRarities,id:\.self) { rarity in
                    Toggle(OfficialRarityCatalog.rarity(rarity)?.displayLabel ?? rarity,isOn:Binding(get:{draft.rarities.contains(rarity)},set:{selected in if selected {draft.rarities.insert(rarity)} else {draft.rarities.remove(rarity)}}))
                }
                if !draft.rarities.isEmpty { Divider();Button(role:.destructive){draft.rarities.removeAll()}label:{Label("清除罕贵度",systemImage:"xmark.circle")} }
            } label: {
                HStack {
                    Text(raritySummary).foregroundStyle(Design.ink).lineLimit(1)
                    Spacer();Image(systemName:"chevron.up.chevron.down").font(.caption.bold()).foregroundStyle(Design.secondary)
                }.frame(minHeight:44).contentShape(Rectangle())
            }.accessibilityIdentifier("cards.filter.rarity")
        }
    }
    private var releaseDateSection:some View {
        Section("首次发售日") {
            DatePicker("起始日期",selection:dateBinding(\.releaseDateFrom,fallback:Self.earliestDate),in:Self.earliestDate...Date.now,displayedComponents:.date)
                .environment(\.locale,Locale(identifier:"zh_CN")).accessibilityIdentifier("cards.filter.release.start")
            DatePicker("结束日期",selection:dateBinding(\.releaseDateTo,fallback:Date.now),in:Self.earliestDate...Date.now,displayedComponents:.date)
                .environment(\.locale,Locale(identifier:"zh_CN")).accessibilityIdentifier("cards.filter.release.end")
        }
    }
    private var raritySummary:String {
        if draft.rarities.isEmpty { return availableRarities.isEmpty ? "载入中…":"选择罕贵度" }
        if draft.rarities.count <= 3 { return availableRarities.filter{draft.rarities.contains($0)}.map{OfficialRarityCatalog.rarity($0)?.displayLabel ?? $0}.joined(separator:"、") }
        return "已选择 \(draft.rarities.count) 种"
    }
    private func chipGrid(_ options:[CardOption],selection:Binding<Int64>,prefix:String)->some View {
        LazyVGrid(columns:[GridItem(.adaptive(minimum:76),spacing:8)],spacing:8) {
            ForEach(options) { option in
                flagChoice(option.title,flag:option.id,selection:selection,color:Design.accent,identifier:"cards.filter.\(prefix).\(option.id)")
            }
        }.padding(.vertical,4)
    }
    private func flagChoice(_ title:String,flag:Int64,selection:Binding<Int64>,color:Color,identifier:String)->some View {
        choice(title,selected:selection.wrappedValue & flag != 0,color:color,identifier:identifier) {
            if selection.wrappedValue & flag != 0 { selection.wrappedValue &= ~flag } else { selection.wrappedValue |= flag }
        }
    }
    private func triStateChoice(_ option:CardOption)->some View {
        let included=draft.subtype & option.id != 0,excluded=draft.excludedSubtype & option.id != 0
        return Button {
            if included { draft.subtype &= ~option.id;draft.excludedSubtype |= option.id }
            else if excluded { draft.excludedSubtype &= ~option.id }
            else { draft.subtype |= option.id }
        } label: {
            HStack(spacing:5) {
                if included { Image(systemName:"checkmark").font(.caption.bold()) }
                else if excluded { Image(systemName:"xmark").font(.caption.bold()) }
                Text(option.title).font(.caption.weight(.semibold))
            }.foregroundStyle(included ? .white:excluded ? Color.red:Design.secondary).frame(maxWidth:.infinity,minHeight:44)
                .background(included ? Design.accent:excluded ? Color.red.opacity(0.12):Color(uiColor:.tertiarySystemFill),in:Capsule())
                .overlay(Capsule().strokeBorder(excluded ? Color.red:Color.clear,lineWidth:1))
        }.buttonStyle(.plain).accessibilityIdentifier("cards.filter.type.\(option.id)")
            .accessibilityValue(included ? "包含":excluded ? "排除":"未选择").accessibilityAddTraits(included || excluded ? .isSelected:[])
    }
    private func choice(_ title:String,selected:Bool,color:Color,identifier:String,action:@escaping()->Void)->some View {
        Button(action:action){Text(title).font(.caption.weight(.semibold)).foregroundStyle(selected ? .white:Design.secondary).frame(maxWidth:.infinity,minHeight:44).background(selected ? color:Color(uiColor:.tertiarySystemFill),in:Capsule())}
            .buttonStyle(.plain).accessibilityIdentifier(identifier).accessibilityAddTraits(selected ? .isSelected:[])
    }
    private func reset(){let type=draft.baseType,sort=draft.sort,ascending=draft.sortAscending,format=draft.format,favorites=draft.favoritesOnly;draft=CardFilter();draft.baseType=type;draft.sort=sort;draft.sortAscending=ascending;draft.format=format;draft.favoritesOnly=favoritesMode || favorites}
    private func apply(){do{try draft.validate();filter=draft;dismiss()}catch{self.error=error.localizedDescription}}
    private func dateBinding(_ keyPath:WritableKeyPath<CardFilter,String>,fallback:Date)->Binding<Date> {
        Binding(get:{Self.dayFormatter.date(from:draft[keyPath:keyPath]) ?? fallback},set:{draft[keyPath:keyPath]=Self.dayFormatter.string(from:$0)})
    }
    private static let dayFormatter:DateFormatter = {
        let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.timeZone=TimeZone(secondsFromGMT:0);formatter.dateFormat="yyyy-MM-dd";return formatter
    }()
    private static let earliestDate:Date = dayFormatter.date(from:"1999-01-01")!

}

private struct NumericRangeFilter:View {
    let title:String
    @Binding var minimum:String
    @Binding var maximum:String
    @Binding var includeUnknown:Bool
    let bounds:ClosedRange<Int>
    let step:Int
    let identifier:String
    let color:Color
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                TextField("最小",text:$minimum).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain).padding(.horizontal,10).frame(width:82,height:44)
                    .background(Design.field,in:RoundedRectangle(cornerRadius:10,style:.continuous))
                    .overlay(RoundedRectangle(cornerRadius:10,style:.continuous).strokeBorder(Color(uiColor:.separator).opacity(0.45)))
                    .accessibilityIdentifier("cards.filter.\(identifier).minimum")
                Text("～").foregroundStyle(Design.secondary)
                TextField("最大",text:$maximum).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain).padding(.horizontal,10).frame(width:82,height:44)
                    .background(Design.field,in:RoundedRectangle(cornerRadius:10,style:.continuous))
                    .overlay(RoundedRectangle(cornerRadius:10,style:.continuous).strokeBorder(Color(uiColor:.separator).opacity(0.45)))
                    .accessibilityIdentifier("cards.filter.\(identifier).maximum")
            }
            DualRangeSlider(minimum:$minimum,maximum:$maximum,bounds:bounds,step:step,color:color,identifier:identifier)
            Toggle("\(title) 包含「?」",isOn:$includeUnknown).accessibilityIdentifier("cards.filter.\(identifier).unknown")
        }.padding(.vertical,4)
    }
}

private struct DualRangeSlider:View {
    @Binding var minimum:String
    @Binding var maximum:String
    let bounds:ClosedRange<Int>
    let step:Int
    let color:Color
    let identifier:String
    private let inset:CGFloat=14
    private var rawLow:Int { min(max(Int(minimum) ?? bounds.lowerBound,bounds.lowerBound),bounds.upperBound) }
    private var rawHigh:Int { min(max(Int(maximum) ?? bounds.upperBound,bounds.lowerBound),bounds.upperBound) }
    private var low:Int { min(rawLow,rawHigh) }
    private var high:Int { max(rawLow,rawHigh) }
    var body:some View {
        GeometryReader { proxy in
            let width=max(1,proxy.size.width-inset*2)
            let lowX=inset+width*ratio(low),highX=inset+width*ratio(high)
            ZStack(alignment:.leading) {
                Capsule().fill(Color(uiColor:.tertiarySystemFill)).frame(height:5).padding(.horizontal,inset)
                Capsule().fill(color).frame(width:max(0,highX-lowX),height:5).offset(x:lowX)
                handle(value:low,isLower:true,width:width).position(x:lowX,y:22)
                handle(value:high,isLower:false,width:width).position(x:highX,y:22)
            }.coordinateSpace(name:"range-\(identifier)")
        }.frame(height:44)
    }
    private func handle(value:Int,isLower:Bool,width:CGFloat)->some View {
        Circle().fill(.background).overlay(Circle().strokeBorder(color,lineWidth:3)).shadow(color:.black.opacity(0.12),radius:3,y:1)
            .frame(width:28,height:28).frame(width:44,height:44).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance:0,coordinateSpace:.named("range-\(identifier)")).onChanged { drag in
                let candidate=quantized(drag.location.x,width:width)
                if isLower { minimum=String(min(candidate,high)) } else { maximum=String(max(candidate,low)) }
            })
            .accessibilityLabel("\(identifier.uppercased()) \(isLower ? "下限":"上限")")
            .accessibilityValue(String(value)).accessibilityIdentifier("cards.filter.\(identifier).\(isLower ? "lower":"upper")")
            .accessibilityAdjustableAction { direction in
                let delta=direction == .increment ? step:-step
                if isLower { minimum=String(min(max(bounds.lowerBound,value+delta),high)) }
                else { maximum=String(max(min(bounds.upperBound,value+delta),low)) }
            }
    }
    private func ratio(_ value:Int)->CGFloat { CGFloat(value-bounds.lowerBound)/CGFloat(bounds.upperBound-bounds.lowerBound) }
    private func quantized(_ x:CGFloat,width:CGFloat)->Int {
        let fraction=min(max((x-inset)/width,0),1)
        let raw=Double(bounds.lowerBound)+Double(fraction)*Double(bounds.upperBound-bounds.lowerBound)
        return min(max(Int((raw/Double(step)).rounded())*step,bounds.lowerBound),bounds.upperBound)
    }
}

// Geometry transcribed from Neuron 4.13.0 CardImageArea RectTransforms.
struct NeuronSprite: View {
    let name:String
    var caps:UIEdgeInsets = .zero
    var body:some View {
        if let image=CardUIImages.image(name,in:"NeuronUI") {
            Image(uiImage:caps == .zero ? image : UIImage(cgImage:image.cgImage!,scale:2,orientation:.up)).resizable(capInsets:EdgeInsets(top:caps.top,leading:caps.left,bottom:caps.bottom,trailing:caps.right),resizingMode:.stretch)
                .accessibilityHidden(true)
        }
    }
}

enum NeuronCardLayout {
    static let aspect:CGFloat = 132/188
    static func limitName(_ copies:Int)->String { copies == 0 ? "forbidden" : copies == 1 ? "limited" : "semilimited" }
}

struct NeuronCardThumbnail:View {
    let card:CatalogCard
    var ciid:Int64? = nil
    var copies:Int? = nil
    var indicators=true
    var body:some View {
        GeometryReader { geometry in
            let scale=geometry.size.width/132
            ZStack(alignment:.topLeading) {
                CardArtwork(cid:card.cid,ciid:ciid).frame(width:124,height:180).offset(x:4,y:4)
                if indicators {
                    if card.levelKind == "link" {
                        NeuronLinkMarkers(markers:card.linkMarkers ?? 0).frame(width:123.08,height:123.174).offset(x:4.46,y:22.573)
                    }
                    if card.isPendulum,let left=card.leftScale,let right=card.rightScale {
                        NeuronSprite(name:"03_deck_icon_pen_l").frame(width:24.816,height:26.32).offset(x:3.96,y:114.68)
                        NeuronSprite(name:"03_deck_icon_pen_r").frame(width:24.816,height:26.32).offset(x:103.224,y:114.68)
                        NeuronNumber(left == right ? "\(left)" : "\(left)/\(right)").position(x:66,y:127.84)
                            .accessibilityLabel("灵摆刻度 \(left) / \(right)").accessibilityIdentifier("cards.pendulum.\(card.cid)")
                    }
                    if card.isMonster,card.levelKind != "link",let level=card.level {
                        CardInterfaceIcon(name:card.levelKind == "rank" ? "rank":"level",fallback:"star.fill")
                            .frame(width:25.225,height:25.225).background { NeuronSprite(name:"03_deck_icon_Circle").frame(width:29.225,height:29.225) }.position(x:35.152,y:157.92)
                        NeuronSprite(name:"00_cardicon_x").frame(width:24.064,height:24.064).position(x:66,y:157.92)
                        NeuronNumber("\(level)").position(x:96.848,y:157.92)
                            .accessibilityLabel("\(card.levelLabel) \(level)").accessibilityIdentifier("cards.level.\(card.cid)")
                    } else if !card.isMonster {
                        CardInterfaceIcon(name:card.spellTrapIcon,fallback:"circle.fill").frame(width:25.225,height:25.225)
                            .background { NeuronSprite(name:"03_deck_icon_Circle").frame(width:29.225,height:29.225) }.position(x:35.152,y:157.92)
                    }
                }
                NeuronSprite(name:"03_deck_frame_default",caps:.init(top:6,left:6,bottom:6,right:6)).frame(width:132,height:188)
                if let copies {
                    NeuronSprite(name:"03_deck_frame_"+NeuronCardLayout.limitName(copies),caps:.init(top:52,left:52,bottom:6,right:6)).frame(width:132,height:188)
                        .accessibilityElement(children:.ignore).accessibilityLabel(["禁止","限制","准限制"][copies]).accessibilityIdentifier("cards.limit.\(card.cid).\(copies)")
                    NeuronSprite(name:"03_deck_frame_"+NeuronCardLayout.limitName(copies)+"_3")
                        .frame(width:32,height:32).offset(x:0,y:0)
                        .accessibilityHidden(true)
                }
                if indicators {
                    NeuronSprite(name:"03_deck_icon_Circle").frame(width:39.6,height:39.36).offset(x:95.04,y:-4.64)
                    CardInterfaceIcon(name:card.attributeIcon,fallback:"circle.fill").frame(width:35.6,height:35.36).offset(x:97.04,y:-2.64)
                }
            }.frame(width:132,height:188,alignment:.topLeading).scaleEffect(scale,anchor:.topLeading)
        }.aspectRatio(NeuronCardLayout.aspect,contentMode:.fit)
    }
}

private struct NeuronNumber:View {
    let text:String
    init(_ text:String){self.text=text}
    var body:some View {
        Text(text).font(.system(size:26,weight:.bold)).foregroundStyle(.white)
            .shadow(color:.black,radius:0,x:1,y:1).shadow(color:.black,radius:0,x:-1,y:-1)
            .fixedSize().accessibilityElement(children:.ignore)
    }
}

struct NeuronLinkMarkers:View {
    let markers:Int64
    var selection:Binding<Int64>? = nil
    private let directions:[(Int64,String,CGRect)] = [
        (1,"01",CGRect(x:7,y:85,width:28,height:29)),(2,"02",CGRect(x:42,y:101,width:36,height:21)),
        (4,"03",CGRect(x:86,y:85,width:28,height:29)),(8,"04",CGRect(x:1,y:44,width:21,height:36)),
        (32,"06",CGRect(x:99,y:44,width:21,height:36)),(64,"07",CGRect(x:7,y:8,width:28,height:29)),
        (128,"08",CGRect(x:42,y:0,width:36,height:21)),(256,"09",CGRect(x:86,y:8,width:28,height:29))]
    var body:some View {
        GeometryReader { geo in
            let inset=selection == nil ? CGFloat.zero:geo.size.width/16
            let width=geo.size.width-2*inset
            let height=geo.size.height-2*inset
            ZStack {
                if selection != nil {NeuronSprite(name:"00_flame_decksearch",caps:.init(top:7,left:10,bottom:4,right:10))}
                ForEach(directions.indices,id:\.self) { i in
                    let d=directions[i]
                    let active=(selection?.wrappedValue ?? markers)&d.0 != 0
                    let size=CGSize(width:width*d.2.width/122,height:height*d.2.height/122)
                    let center=CGPoint(x:inset+width*d.2.midX/122,y:inset+height*d.2.midY/122)
                    if let selection {
                        Button { selection.wrappedValue ^= d.0 } label: {
                            NeuronSprite(name:"link-"+(active ? "on-":"off-")+d.1).frame(width:size.width,height:size.height)
                                .frame(width:44,height:44).contentShape(Rectangle())
                        }.buttonStyle(.plain).position(center)
                            .accessibilityLabel(["左下","下","右下","左","右","左上","上","右上"][i])
                            .accessibilityIdentifier("cards.filter.link.marker.\(d.0)").accessibilityAddTraits(active ? .isSelected:[])
                    } else {
                        NeuronSprite(name:"link-"+(active ? "on-":"off-")+d.1).frame(width:size.width,height:size.height).position(center)
                    }
                }
            }
        }
    }
}
