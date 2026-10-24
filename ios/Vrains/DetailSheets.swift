import SwiftUI

struct DeckDetailSheet: View {
    @Environment(AppStore.self) private var store
    let deck: Deck
    private var isSaved: Bool { store.decks.first(where: { $0.id == deck.id })?.isMine == true }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack { ModalCloseButton(); Text("构筑灵感").font(.headline); Spacer() }
                Artwork(kind: deck.kind).frame(height: 285).clipShape(RoundedRectangle(cornerRadius: 28))
                VStack(alignment: .leading, spacing: 10) {
                    Text(deck.name).font(.largeTitle.bold()).foregroundStyle(Design.ink)
                    Text(deck.subtitle).font(.subheadline).foregroundStyle(Design.secondary)
                }
                HStack(spacing: 14) {
                    Label("\(deck.cards) 张卡牌", systemImage: "rectangle.stack")
                    Label("构筑灵感", systemImage: "sparkles")
                }.font(.system(size: 12)).foregroundStyle(Design.secondary)
                AccentButton(title: isSaved ? "已在我的卡组" : "收藏到我的卡组", icon: isSaved ? "checkmark" : "plus") { store.saveDeck(deck) }
                    .disabled(isSaved).opacity(isSaved ? 0.6 : 1)
            }.padding(24)
        }.background(Design.canvas).presentationDragIndicator(.visible)
    }
}

struct CreateDeckSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: ArtworkKind = .blue
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack { ModalCloseButton(); Text("新的构筑").font(.title2.bold()); Spacer() }
                Artwork(kind: kind).frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 27))
                Text("给灵感一个名字。").font(.title2.bold())
                TextField("卡组名称",text:$name).padding(18).background(Design.field,in:RoundedRectangle(cornerRadius:16))
                    .onChange(of: name) { _, value in if value.count > 24 { name = String(value.prefix(24)) } }
                HStack(spacing: 18) {
                    ForEach(ArtworkKind.allCases, id: \.self) { option in
                        Button { kind = option } label: {
                            Circle().fill(option.colors[1]).frame(width: 44, height: 44)
                                .overlay { if option == kind { Image(systemName: "checkmark").foregroundStyle(.white) } }
                        }.buttonStyle(.plain).accessibilityLabel("\(option.rawValue) 封面")
                    }
                }
                AccentButton(title: "创建卡组", icon: "plus") {
                    store.addDeck(name: name.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind)
                    dismiss()
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
            }.padding(24)
        }.background(Design.canvas).presentationDragIndicator(.visible)
    }
}

struct MatchDetailSheet: View {
    @Environment(AppStore.self) private var store
    let match: Tournament
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                HStack { ModalCloseButton(); Text("赛程详情").font(.headline); Spacer() }
                Image(systemName: "trophy.fill").font(.system(size: 78, weight: .light))
                    .foregroundStyle(Design.accent.gradient).frame(maxWidth: .infinity).padding(.vertical, 35)
                Text(match.title).font(.system(size: 30, weight: .bold))
                VStack(alignment: .leading, spacing: 17) {
                    Label("\(match.month) \(match.day) 日 · \(match.time)", systemImage: "calendar")
                    Label(match.place, systemImage: "mappin.and.ellipse")
                    Label(match.tag, systemImage: "flag.checkered")
                }.font(.subheadline).foregroundStyle(Design.secondary)
                Text("关注的比赛保存在本机。")
                    .font(.subheadline).lineSpacing(6).foregroundStyle(Design.secondary)
                AccentButton(title: store.followedMatches.contains(match.id) ? "已关注 · 点击取消" : "关注这场比赛", icon: "bookmark") { store.toggleMatch(match.id) }
            }.padding(24)
        }.background(Design.canvas).presentationDragIndicator(.visible)
    }
}
