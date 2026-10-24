import SwiftUI

private enum DuelSelection:String,Identifiable {
    case deck="选择卡组",mate="选择桌宠",field="选择场地",server="选择服务器"
    var id:String{rawValue}
    var key:String {
        switch self { case .deck:"deck";case .mate:"mate";case .field:"field";case .server:"server" }
    }
}

struct DuelLobbyScreen:View {
    @Environment(AppStore.self) private var store
    @Environment(DuelLobbyStore.self) private var duel
    @State private var selection:DuelSelection?
    private var selectedDeck:Deck? { store.myDecks.first{$0.id==duel.preferences.deckID} }

    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    arenaPreview
                    VStack(alignment:.leading,spacing:12) {
                        Text("准备你的决斗").font(.title3.bold())
                        VStack(spacing:0) {
                            choiceRow(.deck,title:"卡组",value:selectedDeck?.name ?? "选择一套卡组",detail:selectedDeck.map{"\($0.cards) 张 · 我的卡组"} ?? "从卡组页创建你的构筑",symbol:"rectangle.stack.fill",color:0x4F6AAF)
                            Divider().padding(.leading,72)
                            choiceRow(.mate,title:"桌宠",value:duel.mate.name,detail:"陪伴你的决斗伙伴",symbol:duel.mate.symbol,color:duel.mate.color)
                            Divider().padding(.leading,72)
                            choiceRow(.field,title:"对战场地",value:duel.field.name,detail:duel.field.subtitle,symbol:duel.field.symbol,color:duel.field.color)
                            Divider().padding(.leading,72)
                            choiceRow(.server,title:"对局服务器",value:duel.server.name,detail:duel.server.rules,symbol:"network",color:0x418A78)
                        }.background(Design.surface,in:RoundedRectangle(cornerRadius:24))
                    }
                    VStack(spacing:12) {
                        Button { duel.startSearch(decks:store.myDecks) } label: {
                            Label("开始匹配",systemImage:"bolt.fill").font(.headline)
                                .frame(maxWidth:.infinity)

                        }.primaryActionStyle().disabled(duel.configuration(for:store.myDecks)==nil || duel.isSearching)
                                .accessibilityIdentifier("duel.match.start")
                        Text(selectedDeck?.cards==0 ? "这套卡组还没有卡牌，请先完善构筑。":"当前为演示模式，不连接真实玩家。")
                            .font(.footnote).foregroundStyle(Design.secondary).multilineTextAlignment(.center)
                    }
                }.padding(.horizontal,20).padding(.top,8).padding(.bottom,30)
            }.background(Design.canvas).navigationTitle("决斗").navigationBarTitleDisplayMode(.large)
                .accessibilityIdentifier("duel.lobby")
        }
        .onAppear { duel.reconcileDecks(store.myDecks) }
        .onChange(of:store.myDecks) { _,decks in duel.reconcileDecks(decks) }
        .sheet(item:$selection) { selected in
            DuelSelectionSheet(selection:selected)
        }
        .sheet(isPresented:Binding(get:{duel.isSearching},set:{if !$0 && duel.isSearching { duel.cancelSearch() }}),onDismiss:{duel.openPendingMatch()}) {
            DuelSearchingSheet().interactiveDismissDisabled()
                .presentationDetents([.height(340)]).presentationDragIndicator(.hidden)
        }
        .alert("无法开始对战",isPresented:Binding(get:{duel.errorMessage != nil},set:{if !$0 {duel.errorMessage=nil}})) {
            Button("好",role:.cancel){duel.errorMessage=nil}
        } message: { Text(duel.errorMessage ?? "") }
    }

    private var arenaPreview:some View {
        ZStack(alignment:.bottomLeading) {
            LinearGradient(colors:[Color(hex:duel.field.color),Color(hex:0x20253D)],startPoint:.topLeading,endPoint:.bottomTrailing)
            DuelArenaArtwork(mate:duel.mate,field:duel.field)
                .padding(.leading,92).padding(.bottom,48).accessibilityHidden(true)
            VStack(alignment:.leading,spacing:6) {
                Text("YOUR NEXT DUEL").font(.system(size:9,weight:.semibold)).tracking(2.5).opacity(0.7)
                Text("下一回合，\n与你并肩。").font(.system(size:27,weight:.bold)).lineSpacing(2)
                HStack(spacing:6) {
                    Image(systemName:duel.field.symbol)
                    Text(duel.field.name)
                    Text("·")
                    Text(duel.mate.name)
                }.font(.caption).opacity(0.8)
            }.foregroundStyle(.white).padding(22)
        }.frame(height:230).clipShape(RoundedRectangle(cornerRadius:28))
            .accessibilityElement(children:.ignore).accessibilityLabel("外观预览，\(duel.field.name)，桌宠\(duel.mate.name)")
    }

    private func choiceRow(_ route:DuelSelection,title:String,value:String,detail:String,symbol:String,color:UInt32)->some View {
        Button { selection=route } label: {
            HStack(spacing:14) {
                Image(systemName:symbol).font(.system(size:21,weight:.medium)).foregroundStyle(Color(hex:color))
                    .frame(width:42,height:48).background(Color(hex:color).opacity(0.1),in:RoundedRectangle(cornerRadius:13))
                VStack(alignment:.leading,spacing:4) {
                    Text(title).font(.caption).foregroundStyle(Design.secondary)
                    Text(value).font(.system(size:16,weight:.semibold)).foregroundStyle(Design.ink).lineLimit(2)
                    Text(detail).font(.caption).foregroundStyle(Design.secondary).lineLimit(2)
                }.frame(maxWidth:.infinity,alignment:.leading)
                Image(systemName:"chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Design.secondary)
            }.padding(16).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("duel.select.\(route.key)")
    }
}

private struct DuelSelectionSheet:View {
    let selection:DuelSelection
    @Environment(AppStore.self) private var store
    @Environment(DuelLobbyStore.self) private var duel
    @Environment(\.dismiss) private var dismiss

    var body:some View {
        NavigationStack {
            List {
                Section {
                    switch selection {
                    case .deck:
                        if store.myDecks.isEmpty {
                            EmptyState(icon:"rectangle.stack",title:"还没有卡组",subtitle:"先在卡组页创建一套构筑，再回来选择。")
                        }
                        ForEach(store.myDecks) { deck in
                            option(id:deck.id,name:deck.name,detail:"\(deck.cards) 张 · \(deck.cards==0 ? "待完善":"我的卡组")",symbol:"rectangle.stack.fill",color:0x4F6AAF,selected:duel.preferences.deckID==deck.id) {
                                duel.preferences.deckID=deck.id
                            }
                        }
                    case .mate:
                        ForEach(DuelAppearance.mates) { mate in
                            option(id:mate.id,name:mate.name,detail:mate.subtitle,symbol:mate.symbol,color:mate.color,selected:duel.preferences.mateID==mate.id) {duel.preferences.mateID=mate.id}
                        }
                    case .field:
                        ForEach(DuelAppearance.fields) { field in
                            option(id:field.id,name:field.name,detail:field.subtitle,symbol:field.symbol,color:field.color,selected:duel.preferences.fieldID==field.id) {duel.preferences.fieldID=field.id}
                        }
                    case .server:
                        ForEach(DuelServerOption.options) { server in
                            option(id:server.id,name:server.name,detail:server.rules,symbol:"network",color:0x418A78,selected:duel.preferences.serverID==server.id) {duel.preferences.serverID=server.id}
                        }
                    }
                    Text(selection == .server ? "演示服务器不会连接真实玩家。":"所选内容用于演示决斗。")
                        .font(.footnote).foregroundStyle(Design.secondary).frame(maxWidth:.infinity,alignment:.leading).padding(.top,4)
                }
            }.background(Design.canvas).navigationTitle(selection.rawValue).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.cancellationAction) { ModalCloseButton().accessibilityIdentifier("duel.selection.close") } }
        }.presentationDragIndicator(.visible)
    }

    private func option(id:String,name:String,detail:String,symbol:String,color:UInt32,selected:Bool,action:@escaping ()->Void)->some View {
        Button { action();dismiss() } label: {
            HStack(spacing:15) {
                Image(systemName:symbol).font(.system(size:25)).foregroundStyle(Color(hex:color))
                    .frame(width:38,height:44)
                VStack(alignment:.leading,spacing:6) {
                    Text(name).font(.headline).foregroundStyle(Design.ink)
                    Text(detail).font(.caption).foregroundStyle(Design.secondary)
                }.frame(maxWidth:.infinity,alignment:.leading)
                if selected { Image(systemName:"checkmark").foregroundStyle(Design.accent) }
            }.padding(.vertical,8).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("duel.option.\(id)").accessibilityAddTraits(selected ? .isSelected:[])
    }
}

private struct DuelSearchingSheet:View {
    @Environment(DuelLobbyStore.self) private var duel
    var body:some View {
        VStack(spacing:18) {
            ProgressView().controlSize(.large).tint(Design.accent).padding(.top,18)
            Text("正在寻找对手").font(.title2.bold()).accessibilityIdentifier("duel.match.searching")
            Text(duel.server.rules).font(.subheadline).foregroundStyle(Design.secondary)
            Text("演示匹配，不会连接真实玩家。").font(.footnote).foregroundStyle(Design.secondary)
            Button("取消匹配",role:.cancel){duel.cancelSearch()}
                .font(.headline).frame(maxWidth:.infinity,minHeight:44).secondaryActionStyle()
                .accessibilityIdentifier("duel.match.cancel")
        }.padding(28).frame(maxWidth:.infinity,maxHeight:.infinity).background(Design.canvas)
    }
}

/// Static artwork for the lobby and integration preview; it is not a 3D renderer.
private struct DuelArenaArtwork:View {
    let mate:DuelAppearance
    let field:DuelAppearance
    var body:some View {
        ZStack {
            Circle().stroke(.white.opacity(0.12),lineWidth:1).frame(width:175,height:175)
            Circle().stroke(.white.opacity(0.2),lineWidth:1).frame(width:125,height:125)
            Image(systemName:field.symbol).font(.system(size:73,weight:.ultraLight)).foregroundStyle(.white.opacity(0.15))
            Image(systemName:mate.symbol).font(.system(size:44,weight:.light)).foregroundStyle(.white.opacity(0.85))
                .shadow(color:Color(hex:mate.color),radius:20).offset(x:42,y:15)
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
    }
}

struct DuelBattlePreviewScreen:View {
    let session:DuelMatchSession
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        GeometryReader { geometry in
            let landscape=geometry.size.width>geometry.size.height
            ScrollView {
                VStack(spacing:20) {
                    HStack {
                        Text("对战预览").font(.headline)
                        Spacer()
                        Button { dismiss() } label: { Label("返回",systemImage:"xmark") }
                            .accessibilityIdentifier("duel.battle.close")
                    }.foregroundStyle(.white)
                    HStack(spacing:12) {
                        player(session.opponentName)
                        Text("VS").font(.title3.bold()).foregroundStyle(.white.opacity(0.5))
                        player("我 · \(session.configuration.deckName)")
                    }
                    if landscape {
                        HStack(spacing:22) { board;status.frame(maxWidth:280) }
                    } else { board;status }
                }.padding(22)
            }.background(LinearGradient(colors:[Color(hex:session.configuration.field.color),Color(hex:0x171C2D)],startPoint:.topLeading,endPoint:.bottomTrailing))
                .accessibilityIdentifier("duel.battle.preview")
        }.interactiveDismissDisabled()
    }
    private var board:some View {
        VStack(spacing:12) {
            zones
            zones
            Image(systemName:session.configuration.mate.symbol).font(.system(size:38)).foregroundStyle(.white.opacity(0.8)).padding(.vertical,8)
            zones
            zones
            HStack(spacing:7) {
                ForEach(0..<5) { _ in RoundedRectangle(cornerRadius:5).fill(.white.opacity(0.16)).frame(width:35,height:50).overlay(RoundedRectangle(cornerRadius:5).stroke(.white.opacity(0.2))) }
            }.padding(.top,8).accessibilityLabel("示意手牌，未开始真实决斗")
        }.padding(18).frame(maxWidth:.infinity).background(.white.opacity(0.06),in:RoundedRectangle(cornerRadius:22)).accessibilityHidden(true)
    }
    private var zones:some View {
        HStack(spacing:8) {
            ForEach(0..<5) { _ in RoundedRectangle(cornerRadius:6).stroke(.white.opacity(0.2),style:StrokeStyle(lineWidth:1,dash:[4,4])).frame(maxWidth:.infinity).frame(height:46) }
        }
    }
    private func player(_ name:String)->some View {
        VStack(alignment:.leading,spacing:6) {
            Text(name).font(.caption.weight(.semibold)).lineLimit(2)
            Text("8000 LP").font(.title3.bold().monospacedDigit())
        }.foregroundStyle(.white).frame(maxWidth:.infinity,alignment:.leading)
    }
    private var status:some View {
        VStack(alignment:.leading,spacing:12) {
            Label("演示匹配成功",systemImage:"checkmark.circle.fill").font(.headline).foregroundStyle(Color(hex:0xB4E6D2))
            Text("\(session.configuration.field.name) · \(session.configuration.mate.name)").font(.subheadline).foregroundStyle(.white)
            Text(session.configuration.server.name).font(.caption).foregroundStyle(.white.opacity(0.7))
            Text("当前显示模拟对战布局，仅供流程预览。")
                .font(.footnote).foregroundStyle(.white.opacity(0.7)).fixedSize(horizontal:false,vertical:true)
                .accessibilityIdentifier("duel.battle.preview")
        }.frame(maxWidth:.infinity,alignment:.leading).padding(18).background(.white.opacity(0.07),in:RoundedRectangle(cornerRadius:20))
    }
}
