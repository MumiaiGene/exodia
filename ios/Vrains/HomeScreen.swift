import SwiftUI

enum NewsRoute: Hashable {
    case feed
    case article(String)
}

struct HomeScreen: View {
    @Environment(NewsStore.self) private var news
    @State private var path: [NewsRoute] = []
    @State private var showingProfile=false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    Text("EXODIA ver.").font(.system(size:10,weight:.bold)).tracking(2.8).foregroundStyle(Design.secondary)
                    if !news.banners.isEmpty {
                        NewsCarousel(banners: news.banners) { path.append(.article($0)) }
                    } else if news.isLoading, !news.hasLoaded {
                        RoundedRectangle(cornerRadius: 28).fill(Design.secondary.opacity(0.08))
                            .frame(height: 240).overlay { ProgressView().tint(Design.accent) }
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        Button { path.append(.feed) } label: {
                            HStack {
                                Text("动态").font(.system(size: 23, weight: .bold)).foregroundStyle(Design.ink)
                                Spacer()
                                HStack(spacing: 5) {
                                    Text("全部").font(.system(size: 12))
                                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                                }.foregroundStyle(Design.secondary)
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("home.news.all")
                        if let message = news.errorMessage {
                            NewsLoadError(message: message) { Task { await news.refresh() } }
                        }
                        if news.hasLoaded, news.articles.isEmpty {
                            EmptyState(icon: "newspaper", title: "新的动态，敬请期待", subtitle: "下拉刷新，查看最新资讯。")
                        }
                        NewsRows(articles: news.articles) { path.append(.article($0.id)) }
                        InfiniteScrollFooter(itemCount: news.articles.count, canLoadMore: news.hasMore && news.errorMessage == nil, isLoading: news.isLoading) {
                            await news.loadMore()
                        }
                    }
                }.padding(.horizontal, 22).padding(.bottom, 24)
            }.accessibilityIdentifier("home.scroll")
            .background(Design.canvas)
            .automaticPagination(itemCount: news.articles.count, canLoadMore: news.hasMore && news.errorMessage == nil, isLoading: news.isLoading) { await news.loadMore() }
            .navigationTitle("一起来决斗").navigationBarTitleDisplayMode(.large)
            .toolbar { ToolbarItem(placement:.topBarTrailing) { HomeProfileButton { showingProfile=true } } }
            .task { await news.loadInitial() }
            .refreshable { await news.refresh() }
            .navigationDestination(for: NewsRoute.self) { route in
                switch route {
                case .feed: NewsListScreen()
                case .article(let id): NewsDetailScreen(id: id)
                }
            }
            .sheet(isPresented:$showingProfile) { NavigationStack { ProfileScreen() } }
        }
    }
}

private struct HomeProfileButton: View {
    @Environment(AccountStore.self) private var account
    var action:()->Void
    var body:some View {
        Button(action:action){avatar.frame(width:30,height:30)}
            .accessibilityLabel("打开个人页").accessibilityIdentifier("home.avatar")
    }
    private var avatar:some View {
        ZStack {
            Image(systemName:account.isLoggedIn ? "person.crop.circle.fill":"person.crop.circle")
                .resizable().scaledToFit().foregroundStyle(Design.accent)
            if account.isLoggedIn,let url=account.profile?.avatarURL {
                AsyncImage(url:url){phase in if let image=phase.image{image.resizable().scaledToFill()}}
                    .clipShape(Circle()).accessibilityIdentifier("home.avatar.image")
            }
        }.clipShape(Circle())
    }
}

struct NewsCarousel: View {
    let banners: [NewsBanner]
    var openNews: (String) -> Void
    @State private var selection = 0
    @State private var visiblePage:Int? = 0
    var body: some View {
        VStack(spacing: 13) {
            GeometryReader { geometry in
                ScrollView(.horizontal,showsIndicators:false) {
                    LazyHStack(spacing:0) {
                        ForEach(Array(banners.enumerated()),id:\.element.id) { index,banner in
                            Group {
                                if let id=banner.newsID { Button { openNews(id) } label:{bannerContent(banner)}.buttonStyle(.plain) }
                                else { bannerContent(banner) }
                            }.frame(width:geometry.size.width).id(index)
                        }
                    }.scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging).scrollPosition(id:$visiblePage)
                .onChange(of:visiblePage){_,page in if let page { selection=page }}
                .clipShape(RoundedRectangle(cornerRadius:28)).accessibilityIdentifier("home.banner.carousel")
            }.frame(height:235)
            if banners.count > 1 {
                HStack(spacing: 6) {
                    ForEach(banners.indices, id: \.self) { index in
                        Button { withAnimation { selection=index;visiblePage=index } } label: {
                            Capsule().fill(selection == index ? Design.accent : Design.secondary.opacity(0.24))
                                .frame(width:selection == index ? 20:6,height:6).frame(width:46,height:46).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("第 \(index + 1) 张精选")
                            .accessibilityIdentifier("home.banner.page.\(index)")
                            .accessibilityAddTraits(selection == index ? .isSelected : [])
                    }
                }
            }
        }.onChange(of:banners.count){_,count in if selection>=count { selection=0;visiblePage=0 }}
    }
    private func bannerContent(_ banner: NewsBanner) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                Color(hex: 0x192548)
                AsyncImage(url: banner.imageURL) { image in image.resizable().scaledToFill() } placeholder: {
                    LinearGradient(colors: [Color(hex: 0x142349), Color(hex: 0x4869A4)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
            HStack(alignment: .bottom, spacing: 12) {
                Text(banner.title).font(.system(size: 20, weight: .bold)).lineLimit(2).foregroundStyle(.white)
                Spacer(minLength: 0)
                if banner.newsID != nil {
                    Image(systemName: "arrow.up.right").font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white).frame(width: 39, height: 39).prototypeGlass(cornerRadius: 20)
                }
            }.padding(20)
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.accessibilityLabel(banner.title)
    }
}

struct NewsRows: View {
    @Environment(NewsStore.self) private var news
    let articles: [NewsArticle]
    var open: (NewsArticle) -> Void
    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(articles) { article in
                Button { open(article) } label: {
                    NewsRow(article: article)
                }.buttonStyle(.plain).accessibilityIdentifier("news.row.\(article.id)")
                    .onAppear {
                        if article.id == articles.last?.id, news.hasMore, news.errorMessage == nil {
                            Task { await news.loadMore() }
                        }
                    }
                if article.id != articles.last?.id { Divider().overlay(Design.secondary.opacity(0.05)) }
            }
        }
    }
}

struct NewsRow: View {
    let article: NewsArticle
    var body: some View {
        HStack(alignment: .center, spacing: 15) {
            VStack(alignment: .leading, spacing: 10) {
                Text(article.title).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                    .foregroundStyle(Design.ink).multilineTextAlignment(.leading)
                HStack(spacing: 7) {
                    if let author = article.author { Text(author).lineLimit(1) }
                    if let time = article.timeDescription { Text(time).fixedSize() }
                }.font(.system(size: 10)).foregroundStyle(Design.secondary)
                if let views = article.views {
                    Label(String(views), systemImage: "eye").font(.system(size: 9)).foregroundStyle(Design.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let url = article.coverURL {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: {
                    RoundedRectangle(cornerRadius: 15).fill(Design.secondary.opacity(0.08))
                        .overlay { Image(systemName: "photo").foregroundStyle(Design.secondary.opacity(0.5)) }
                }.frame(width: 96, height: 82).clipShape(RoundedRectangle(cornerRadius: 15))
            }
        }.padding(.vertical, 17).contentShape(Rectangle())
    }
}

struct NewsListScreen: View {
    @Environment(NewsStore.self) private var news
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                Text("来自决斗世界的最新消息").font(.system(size: 12)).foregroundStyle(Design.secondary).padding(.top, 12)
                if let message = news.errorMessage { NewsLoadError(message: message) { Task { await news.refresh() } } }
                if news.hasLoaded, news.articles.isEmpty { EmptyState(icon: "newspaper", title: "暂无动态", subtitle: "下拉刷新，查看最新消息。") }
                LazyVStack(spacing: 0) {
                    ForEach(news.articles) { article in
                        NavigationLink(value: NewsRoute.article(article.id)) {
                            NewsRow(article: article)
                        }.buttonStyle(.plain).accessibilityIdentifier("news.list.row.\(article.id)")
                            .onAppear {
                                if article.id == news.articles.last?.id, news.hasMore, news.errorMessage == nil {
                                    Task { await news.loadMore() }
                                }
                            }
                        Divider()
                    }
                    InfiniteScrollFooter(itemCount: news.articles.count, canLoadMore: news.hasMore && news.errorMessage == nil, isLoading: news.isLoading) {
                        await news.loadMore()
                    }
                }
            }.padding(.horizontal, 22).padding(.bottom, 25)
        }.background(Design.canvas).navigationTitle("动态").navigationBarTitleDisplayMode(.large)
            .automaticPagination(itemCount: news.articles.count, canLoadMore: news.hasMore && news.errorMessage == nil, isLoading: news.isLoading) { await news.loadMore() }
            .toolbar(.visible, for: .navigationBar).glassNavigationBack()
            .task { await news.loadInitial() }.refreshable { await news.refresh() }
    }
}

struct NewsLoadError: View {
    let message: String
    var retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(message).font(.system(size: 12)).foregroundStyle(Design.secondary)
            Button("重新加载", action: retry).font(.system(size: 13, weight: .semibold)).tint(Design.accent)
        }.frame(maxWidth:.infinity,alignment:.leading).padding(18).background(Design.surface,in:RoundedRectangle(cornerRadius:20))
    }
}
