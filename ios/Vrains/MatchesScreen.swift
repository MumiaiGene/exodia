import SwiftUI

struct MatchesScreen: View {
    @Environment(AccountStore.self) private var account
    @State private var browser: MatchBrowserStore?
    @State private var allowsPagination = false
    @Environment(LocationPermissionStore.self) private var location
    @State private var query = MatchQuery()
    @State private var search = ""
    private var effectiveQuery: MatchQuery { MatchBrowserStore.fullQuery(query.inRegion(location.selectedRegion)) }
    private var matches: MatchStore? { browser?.store(for: query.environment) }
    private var visibleItems: [MatchItem] { (matches?.items ?? []).filter { query.typeID == 0 || $0.typeID == query.typeID } }

    var body: some View {
        ActivityBrowseLayout(identity: query.inRegion(location.selectedRegion), scrollIdentifier: "matches.scroll",
            itemCount: matches?.items.count ?? 0, canLoadMore: (matches?.hasMore ?? false) && matches?.errorMessage == nil && allowsPagination,
            isLoading: matches?.isLoading ?? false,
            refresh: { await browser?.refresh(query: effectiveQuery) }, loadMore: { await matches?.loadMore() },
            onScroll: { allowsPagination = true }) {
                Picker("比赛环境", selection: $query.environment) {
                    ForEach(MatchEnvironment.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("matches.environment")
                CityLocationBar()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(matches?.kinds ?? MatchKind.catalog) { kind in
                            Button { allowsPagination = false; query.typeID = kind.id } label: {
                                MatchCategoryPill(kind: kind, selected: query.typeID == kind.id)
                                    .frame(minHeight: 44).contentShape(Capsule())
                            }.buttonStyle(.plain).accessibilityIdentifier("matches.type.\(kind.id)")
                                .accessibilityAddTraits(query.typeID == kind.id ? .isSelected : [])
                        }
                    }.padding(.vertical, 3).padding(.horizontal, 2)
                }.accessibilityIdentifier("matches.types")
                MatchStatusMenu(status: $query.status, count: query.typeID == 0 ? (matches?.total ?? 0) : visibleItems.count, identifier: "matches.status")
        } rows: {
            if let matches {
                if let message = matches.errorMessage {
                    NewsLoadError(message: message) { Task { await browser?.refresh(query: effectiveQuery) } }
                }
                ForEach(visibleItems) { match in
                    NavigationLink { MatchSummaryScreen(match: match, kind: kindName(match)) } label: {
                        LiveMatchRow(match: match, kind: kindName(match))
                    }.buttonStyle(.plain).accessibilityIdentifier("matches.row.\(match.id)")
                }
                if !matches.isLoading, matches.hasLoaded, visibleItems.isEmpty {
                    if matches.hasMore {
                        VStack(spacing: 16) {
                            Text("已加载比赛中暂无此分类").foregroundStyle(Design.secondary)
                            Button("继续加载比赛") { Task { await matches.loadMore() } }
                                .accessibilityIdentifier("matches.loadMore")
                        }.frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else { EmptyState(icon: "flag.checkered", title: "暂时没有这类比赛", subtitle: "") }
                }
                InfiniteScrollFooter(itemCount: matches.items.count, canLoadMore: matches.hasMore && matches.errorMessage == nil && allowsPagination, isLoading: matches.isLoading) { await matches.loadMore() }
            }
        }
        .task {
            if browser == nil { browser = MatchBrowserStore(api: account.api) }
            location.locate()
            await browser?.loadInitial(query: effectiveQuery)
        }
        .task(id: effectiveQuery) { await browser?.loadInitial(query: effectiveQuery) }
        .onChange(of: query.environment) { _, _ in allowsPagination = false }
        .onChange(of: effectiveQuery) { _, _ in allowsPagination = false }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索比赛名称或地点")
        .stableSearchToolbar()
        .onSubmit(of: .search) { query.keywords = search.trimmingCharacters(in: .whitespacesAndNewlines) }
        .onChange(of: search) { _, value in if value.isEmpty { query.keywords = "" } }
        .navigationTitle("比赛").navigationBarTitleDisplayMode(.inline)
    }
    private func kindName(_ match: MatchItem) -> String {
        (matches?.kinds ?? MatchKind.catalog).first(where: { $0.id == match.typeID })?.title ?? "赛事"
    }
}

struct LiveMatchRow: View {
    let match: MatchItem
    let kind: String
    var showsDisclosure = true
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 8) {
                VStack(spacing: 3) {
                    if let date = match.startsAt {
                        Text(date.formatted(.dateTime.month(.twoDigits))).font(.caption2)
                        Text(date.formatted(.dateTime.day())).font(.system(size: 27, weight: .semibold, design: .rounded))
                    } else { Image(systemName: "calendar").font(.title2) }
                }.foregroundStyle(Design.accent).frame(width: 62, height: 66)
                    .background(Design.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                CardTypeLabel(kind: MatchKind(id: match.typeID ?? 0, title: match.typeID == 20 ? "YCSC" : kind))
            }.frame(width: 76)
            VStack(alignment: .leading, spacing: 10) {
                Text(match.name).font(.headline).foregroundStyle(Design.ink).lineLimit(3).padding(.trailing, showsDisclosure ? 12 : 0)
                if let address = match.address {
                    Label(address, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(Design.secondary).lineLimit(2)
                }
                HStack(spacing: 8) {
                    if let time = match.timeText { Label(time, systemImage: "clock").font(.caption).foregroundStyle(Design.secondary).fixedSize() }
                    Spacer(minLength: 0)
                    MatchStatusLabel(match: match)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.labelStyle(.titleAndIcon)
            .padding(14).background(Design.surface, in: RoundedRectangle(cornerRadius: 25))
            .overlay(alignment: .topTrailing) {
                if showsDisclosure { Image(systemName: "chevron.right").font(.caption).foregroundStyle(Design.secondary).padding(14) }
            }
    }
}

struct MatchStatusLabel: View {
    let match: MatchItem
    private var state: Int { match.statusID ?? (match.status == "已结束" ? 8 : match.status == "进行中" || match.status == "比赛中" ? 3 : 2) }
    var body: some View {
        let full = match.registered.map { count in match.capacity.map { $0 > 0 && count >= $0 } ?? false } ?? false
        let color: Color = state == 2 ? (full ? .orange : .green) : state == 3 ? .orange : .secondary
        let title = state == 2 ? match.isSignedUp ? "已报名" : match.registered.map { count in match.capacity.map { "\(count) / \($0) 人" } ?? "\(count) 人已报名" } ?? "报名人数待公布" : state == 3 ? "进行中" : "已结束"
        Label(title, systemImage: state == 2 ? match.isSignedUp ? "checkmark.circle.fill" : "person.2.fill" : state == 3 ? "play.circle.fill" : "checkmark.circle.fill")
            .labelStyle(.titleAndIcon)
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(color).lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8).padding(.vertical, 6).background(color.opacity(0.1), in: Capsule())
            .accessibilityIdentifier("matches.state.\(match.id)")
    }
}

struct MatchStatusMenu: View {
    @Binding var status: MatchStatus
    let count: Int
    let identifier: String
    var body: some View {
        HStack {
            Text("\(status.title)·\(count) 场比赛").font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Menu {
                Picker("比赛状态", selection: $status) {
                    ForEach(MatchStatus.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
            }.accessibilityLabel("切换比赛状态").accessibilityIdentifier(identifier)
        }
    }
}
