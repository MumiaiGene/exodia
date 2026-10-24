import SwiftUI

private enum AppLaunchPhase: Equatable {
    case loading, ready, entering, entered
}

enum AppTab: String, CaseIterable, Identifiable {
    case home="主页",decks="卡组",duel="决斗",activities="活动",search="查找"
    var id:String{rawValue}
    var icon:String {
        switch self {
        case .home:"house.fill"
        case .decks:"rectangle.stack.fill"
        case .duel:"bolt.shield.fill"
        case .activities:"square.grid.2x2.fill"
        case .search:"magnifyingglass"
        }
    }
}

struct ContentView: View {
    @State private var registrationAccessory = MatchRegistrationAccessory()
    @State private var store=AppStore()
    @State private var duel=DuelLobbyStore()
    @State private var location=LocationPermissionStore()
    @State private var selectedTab:AppTab = .home
    @State private var matchNotifications=JHSMatchNotifications.shared
    @State private var notificationResult:JHSMatchNotificationRoute?
    @State private var openingNotification=false
    @State private var launchPhase: AppLaunchPhase
    @Environment(\.scenePhase) private var scenePhase

    private let bypassLaunchAnimation: Bool

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let bypass = (arguments.contains("--uitesting") && !arguments.contains("--uitesting-splash")) || arguments.contains("--verify-saved-account")
        bypassLaunchAnimation = bypass
        _launchPhase = State(initialValue: bypass ? .entered : .loading)
    }

    var body:some View {
        launchRoot.environment(registrationAccessory)
            .safeAreaInset(edge:.bottom,spacing:0) {
                if store.catalog.isUpdating {
                    HStack(alignment:.top,spacing:12) {
                        CatalogUpdateProgress().environment(store.catalog)
                        if store.catalog.canCancelUpdate {Button("取消"){store.catalog.cancelUpdate()}.frame(minHeight:44).accessibilityIdentifier("catalog.update.cancel")}
                    }.padding(20).foregroundStyle(.primary).background(.regularMaterial)
                }
            }
            .tint(Design.accent)
            .environment(\.locale,Locale(identifier:"zh_CN"))
            .environment(store).environment(store.account).environment(store.jhs).environment(store.news)
            .environment(store.matches).environment(store.catalog)
            .environment(duel).environment(location)
            .fullScreenCover(item:$duel.previewSession) { session in
                DuelBattlePreviewScreen(session:session)
            }
            .sheet(item:$notificationResult){route in
                NavigationStack {
                    JHSMatchJobScreen(jobID:route.id)
                        .toolbar {ToolbarItem(placement:.topBarLeading){Button{notificationResult=nil}label:{Image(systemName:"xmark")}.accessibilityLabel("关闭")}}
                }.environment(store.jhs).environment(store.account).environment(store).tint(Design.accent)
            }
            .onChange(of:matchNotifications.pendingJobID,initial:true){_,_ in openMatchNotification()}
            .onChange(of:launchPhase){_,_ in openMatchNotification()}
            .task {await prepareForFirstFrame()}
            .task {await store.news.loadInitial()}
            .task(id:store.jhs.session?.token){JHSMatchJobsStore.shared.configure(session:store.jhs.session)}
            .task(id:"\(store.account.sessionVersion.uuidString)-\(launchPhase == .entered)") {
                guard launchPhase == .entered else { return }
                await store.account.refresh(force:false)
            }
            .alert("发现资料更新",isPresented:Binding(get:{store.catalog.showUpdatePrompt},set:{store.catalog.showUpdatePrompt=$0})) {
                Button("下载并更新"){Task {await store.catalog.installPending()}}
                Button("暂不更新",role:.cancel){store.catalog.skipUpdate()}
            } message:{
                Text("预估下载 \(store.catalog.pendingUpdate?.sizeLabel ?? "—")\n\n"+(store.catalog.pendingUpdate?.itemLabels.map{"• "+$0}.joined(separator:"\n") ?? ""))
            }
            .alert("资料更新未完成",isPresented:Binding(get:{store.catalog.showUpdateFailure},set:{store.catalog.showUpdateFailure=$0})) {
                Button("重试"){Task{await store.catalog.retryUpdate()}}
                Button("暂不更新",role:.cancel){store.catalog.skipUpdate()}
            } message:{Text(store.catalog.message ?? "本机资料仍可离线使用。")}
            .onChange(of:store.catalog.startupResolved){_,resolved in
                if resolved,launchPhase == .loading {revealEntryPrompt();enterApplication()}
            }
            .onChange(of:scenePhase){_,phase in
                if phase == .active, launchPhase == .entered { Task { await store.account.refresh(force:false) } }
                if phase == .active {JHSMatchJobsStore.shared.endBackgroundTime();JHSMatchJobsStore.shared.configure(session:store.jhs.session);openMatchNotification()}
                if phase == .background {duel.cancelSearch();JHSMatchJobsStore.shared.backgroundTime()}
            }
    }

    private func openMatchNotification() {
        guard launchPhase == .entered,scenePhase == .active,!openingNotification,let id=matchNotifications.pendingJobID else{return}
        openingNotification=true
        let show:@MainActor ()->Void = {
            let target=matchNotifications.pendingJobID ?? id
            matchNotifications.pendingJobID=nil
            notificationResult=JHSMatchNotificationRoute(id:target)
            openingNotification=false
        }
        let root=UIApplication.shared.connectedScenes.compactMap{$0 as? UIWindowScene}.flatMap(\.windows).first(where:{$0.isKeyWindow})?.rootViewController
        if root?.presentedViewController != nil {
            root?.dismiss(animated:false){Task{@MainActor in await Task.yield();show()}}
        } else {show()}
    }

    @ViewBuilder private var launchRoot: some View {
        if launchPhase == .entered {
            tabs
                .transition(.opacity)
        } else {
            DataStormLaunchScreen(
                isReady: launchPhase == .ready,
                isEntering: launchPhase == .entering,
                enter: enterApplication
            )
            .transition(.opacity)
        }
    }

    private func prepareForFirstFrame() async {
        let minimumDelay = Task {
            if !bypassLaunchAnimation { try? await Task.sleep(for:.milliseconds(900)) }
        }
        await store.catalog.prepare()
        if let favorites=try? await store.catalog.database.migrateFavorites(store.savedCards){store.savedCards=favorites}
        _ = await minimumDelay.value
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting-open-duel") {
            selectedTab = .duel
            duel.reconcileDecks(store.myDecks)
            duel.startSearch(decks:store.myDecks)
        }
        #endif
        guard !bypassLaunchAnimation else { return }
        await store.catalog.checkAtLaunch()
        if store.catalog.startupResolved {revealEntryPrompt();enterApplication()}
    }

    private func revealEntryPrompt() {
        guard launchPhase == .loading else { return }
        withAnimation(.easeOut(duration:0.42)) { launchPhase = .ready }
    }

    private func enterApplication() {
        guard launchPhase == .ready else { return }
        withAnimation(.easeIn(duration:0.42)) { launchPhase = .entering }
        Task { @MainActor in
            try? await Task.sleep(for:.milliseconds(460))
            guard launchPhase == .entering else { return }
            withAnimation(.easeOut(duration:0.22)) { launchPhase = .entered }
        }
    }

    @ViewBuilder private var tabs:some View {
        #if compiler(>=6.2)
        if #available(iOS 26.1,*) { modernTabs.tabBarMinimizeBehavior(.onScrollDown)
            .tabViewBottomAccessory(isEnabled: registrationAccessory.action != nil && selectedTab == .activities) {
                Button { registrationAccessory.action?() } label: {
                    Text(registrationAccessory.title).font(.headline)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .foregroundStyle(.white)
                }.primaryActionStyle().accessibilityIdentifier("match.detail.register")
            } }
        else if #available(iOS 18.0,*) { modernTabs }
        else { legacyTabs }
        #else
        legacyTabs
        #endif
    }

    @available(iOS 18.0,*)
    private var modernTabs:some View {
        TabView(selection:$selectedTab) {
            Tab(value:.home) { HomeScreen() } label: { tabLabel(.home,"tab.home") }
            Tab(value:.decks) { DecksScreen() } label: { tabLabel(.decks,"tab.decks") }
            Tab(value:.duel) { DuelLobbyScreen() } label: { tabLabel(.duel,"tab.duel") }
            Tab(value:.activities) { ActivitiesScreen() } label: { tabLabel(.activities,"tab.activities") }
            Tab(value:.search,role:.search) { SearchScreen() } label: { tabLabel(.search,"tab.search") }
        }
    }

    private var legacyTabs:some View {
        TabView(selection:$selectedTab) {
            HomeScreen().tag(AppTab.home).tabItem { tabLabel(.home,"tab.home") }
            DecksScreen().tag(AppTab.decks).tabItem { tabLabel(.decks,"tab.decks") }
            DuelLobbyScreen().tag(AppTab.duel).tabItem { tabLabel(.duel,"tab.duel") }
            ActivitiesScreen().tag(AppTab.activities).tabItem { tabLabel(.activities,"tab.activities") }
            SearchScreen().tag(AppTab.search).tabItem { tabLabel(.search,"tab.search") }
        }
    }

    private func tabLabel(_ tab:AppTab,_ identifier:String)->some View {
        Label(tab.rawValue,systemImage:tab.icon).accessibilityIdentifier(identifier)
    }
}

#Preview { ContentView() }
