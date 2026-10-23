import SwiftUI

private enum DeckHubRoute:String,Hashable { case library,plaza,collection,banlist }
private enum ActivityHubRoute:String,Hashable { case matches,stores,ranking,events }
struct DecksScreen: View {
    var body:some View {
        NavigationStack {
            HubGrid(items:[
                HubItem(id:DeckHubRoute.library.rawValue,title:"卡组",subtitle:"管理自己的构筑",symbol:"rectangle.stack.fill",colors:[0x3657B7,0x182449]),
                HubItem(id:DeckHubRoute.plaza.rawValue,title:"卡组广场",subtitle:"发现新的构筑灵感",symbol:"square.grid.2x2.fill",colors:[0x7956A8,0x35234F]),
                HubItem(id:DeckHubRoute.collection.rawValue,title:"收录",subtitle:"浏览卡包与版本",symbol:"shippingbox.fill",colors:[0xC06A3C,0x63331F]),
                HubItem(id:DeckHubRoute.banlist.rawValue,title:"禁卡表",subtitle:"查看和切换规则环境",symbol:"exclamationmark.shield.fill",colors:[0xC74E5B,0x6A2530])
            ]) { item in NavigationLink(value:DeckHubRoute(rawValue:item.id)!) { HubTile(item:item) } }
            .navigationTitle("卡组").navigationBarTitleDisplayMode(.large)
            .navigationDestination(for:DeckHubRoute.self) { route in
                switch route {
                case .library: DeckLibraryScreen()
                case .plaza: HubPlaceholderScreen(title:"卡组广场",symbol:"square.grid.2x2.fill",subtitle:"后续将在这里展示公开构筑与精选卡组。")
                case .collection: CollectionScreen()
                case .banlist: BanlistHubScreen()
                }
            }
        }
    }
}

struct ActivitiesScreen: View {
    var body:some View {
        NavigationStack {
            HubGrid(items:[
                HubItem(id:ActivityHubRoute.matches.rawValue,title:"比赛",subtitle:"报名并追踪赛事",symbol:"trophy.fill",colors:[0xD84C63,0x762536]),
                HubItem(id:ActivityHubRoute.stores.rawValue,title:"店铺",subtitle:"寻找附近卡店",symbol:"storefront.fill",colors:[0x2E8B78,0x17463E]),
                HubItem(id:ActivityHubRoute.ranking.rawValue,title:"排名",subtitle:"查看积分与榜单",symbol:"chart.bar.fill",colors:[0xCB8B35,0x69471C]),
                HubItem(id:ActivityHubRoute.events.rawValue,title:"活动",subtitle:"发现线下与主题活动",symbol:"sparkles",colors:[0x4F73B7,0x243862])
            ]) { item in NavigationLink(value:ActivityHubRoute(rawValue:item.id)!) { HubTile(item:item) } }
            .navigationTitle("活动").navigationBarTitleDisplayMode(.large)
            .navigationDestination(for:ActivityHubRoute.self) { route in
                switch route {
                case .matches: MatchesScreen()
                case .stores: StoresScreen()
                case .ranking: RankingScreen()
                case .events: HubPlaceholderScreen(title:"活动",symbol:"sparkles",subtitle:"后续将在这里聚合主题活动与官方资讯。")
                }
            }
        }
    }
}

private struct HubItem:Identifiable {
    let id:String,title:String,subtitle:String,symbol:String,colors:[UInt32]
}

private struct HubGrid<Destination:View>:View {
    let items:[HubItem]
    @ViewBuilder var destination:(HubItem)->Destination
    var body:some View {
        ScrollView {
            LazyVGrid(columns:[GridItem(.flexible(),spacing:14),GridItem(.flexible(),spacing:14)],spacing:14) {
                ForEach(items) { item in
                    destination(item)
                        .buttonStyle(.plain).accessibilityIdentifier("hub.\(item.id)")
                }
            }.padding(.horizontal,18).padding(.top,8).padding(.bottom,28)
        }.background(Design.canvas)
    }
}

private struct HubTile:View {
    let item:HubItem
    var body:some View {
        ZStack(alignment:.bottomLeading) {
            LinearGradient(colors:item.colors.map(Color.init(hex:)),startPoint:.topLeading,endPoint:.bottomTrailing)
            Image(systemName:item.symbol).font(.system(size:54,weight:.ultraLight)).foregroundStyle(.white.opacity(0.24))
                .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topTrailing).padding(18)
            VStack(alignment:.leading,spacing:6) {
                Text(item.title).font(.system(size:22,weight:.bold))
                Text(item.subtitle).font(.system(size:11,weight:.medium)).opacity(0.76).lineLimit(2)
            }.foregroundStyle(.white).padding(18)
        }.frame(minHeight:176).clipShape(RoundedRectangle(cornerRadius:28,style:.continuous))
    }
}

private struct HubPlaceholderScreen:View {
    let title:String,symbol:String,subtitle:String
    var body:some View {
        VStack(spacing:18) {
            Image(systemName:symbol).font(.system(size:62,weight:.ultraLight)).foregroundStyle(Design.accent)
            Text(title).font(.title.bold())
            Text(subtitle).font(.body).foregroundStyle(Design.secondary).multilineTextAlignment(.center)
        }.padding(30).frame(maxWidth:.infinity,maxHeight:.infinity).background(Design.canvas)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}

struct MatchRow:View {
    let match:Tournament;let isFollowed:Bool
    var body:some View {
        HStack(spacing:15) {
            VStack(spacing:4){Text(match.month).font(.caption);Text(match.day).font(.system(size:27,weight:.semibold,design:.rounded))}
                .foregroundStyle(Design.accent).frame(width:55,height:68).background(Design.accent.opacity(0.07),in:RoundedRectangle(cornerRadius:15))
            VStack(alignment:.leading,spacing:7){Text(match.title).font(.headline);Text(match.place).font(.caption).foregroundStyle(Design.secondary);Text(match.time).font(.caption).foregroundStyle(Design.secondary)}
                .frame(maxWidth:.infinity,alignment:.leading)
            Image(systemName:isFollowed ? "bookmark.fill":"chevron.right").foregroundStyle(isFollowed ? Design.accent:Design.secondary)
        }.padding(15).background(Design.surface,in:RoundedRectangle(cornerRadius:22))
    }
}
