import SwiftUI

enum Design {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.906, green: 0.278, blue: 0.384, alpha: 1)
            : UIColor(red: 0.71, green: 0.15, blue: 0.27, alpha: 1)
    })
    static let action = Color(hex: 0xB52645)
    static let ink = Color(uiColor:.label)
    static let secondary = Color(uiColor:.secondaryLabel)
    static let canvas = Color(uiColor:.systemGroupedBackground)
    static let surface = Color(uiColor:.secondarySystemGroupedBackground)
    static let field = Color(uiColor:.secondarySystemBackground)
    static func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN")))
    }
}

extension View {
    func primaryActionStyle() -> some View {
        buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
            .controlSize(.large).tint(Design.action).foregroundStyle(.white)
    }
    func secondaryActionStyle() -> some View {
        buttonStyle(.bordered).buttonBorderShape(.capsule)
            .controlSize(.large).tint(Design.accent)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

struct ScreenHeader<Trailing: View>: View {
    let title: String
    let eyebrow: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                Text(eyebrow).font(.system(size: 10, weight: .bold)).tracking(2.8).foregroundStyle(Design.secondary)
                Text(title).font(.system(size: 32, weight: .bold)).tracking(-1).foregroundStyle(Design.ink)
            }
            Spacer()
            trailing
        }
        .padding(.top, 15)
        .padding(.bottom, 8)
    }
}

struct SectionHeading: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 21, weight: .bold)).foregroundStyle(Design.ink)
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 3) {
                        Text(actionTitle).font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                    }
                }
                .tint(Design.secondary)
            }
        }
    }
}

private struct NativeSelectionAction: ViewModifier {
    let selected:Bool
    var controlSize:ControlSize = .large
    var tint:Color? = nil
    @ViewBuilder func body(content:Content) -> some View {
        if selected {content.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(controlSize).tint(tint ?? Design.action).foregroundStyle(.white)}
        else {content.buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(controlSize).tint(tint ?? Design.secondary)}
    }
}

extension View {
    func selectionActionStyle(_ selected:Bool,controlSize:ControlSize = .large,tint:Color? = nil) -> some View {modifier(NativeSelectionAction(selected:selected,controlSize:controlSize,tint:tint))}
}

private struct ScrollEnd: Equatable {
    let count: Int
    let nearBottom: Bool
}

private struct AutomaticPagination: ViewModifier {
    let itemCount: Int
    let canLoadMore: Bool
    let isLoading: Bool
    var prefetchScreens:CGFloat=0
    var loadMore: () async -> Void
    @State private var end = ScrollEnd(count: -1, nearBottom: false)
    @State private var operation: Task<Void, Never>?
    @ViewBuilder func body(content: Content) -> some View {
        let count = itemCount
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: ScrollEnd.self) { geometry in
                let remaining = geometry.contentSize.height + geometry.contentInsets.bottom - geometry.contentOffset.y - geometry.containerSize.height
                return ScrollEnd(count: count, nearBottom: geometry.contentSize.height > 0 && remaining <= max(80,geometry.containerSize.height*prefetchScreens))
            } action: { _, value in
                end = value; startIfNeeded(value)
            }
            .onChange(of: isLoading) { _, _ in startIfNeeded(end) }
            .onChange(of: canLoadMore) { _, _ in startIfNeeded(end) }
            .onChange(of: operation == nil) { _, ready in if ready { startIfNeeded(end) } }
            .onDisappear { end = ScrollEnd(count: -1, nearBottom: false) }
        } else { content }
    }
    private func startIfNeeded(_ measured: ScrollEnd) {
        guard measured.count == itemCount, measured.nearBottom, itemCount > 0, canLoadMore, !isLoading, operation == nil else { return }
        operation = Task { @MainActor in
            await loadMore()
            operation = nil
        }
    }
}

extension View {
    func automaticPagination(itemCount: Int, canLoadMore: Bool, isLoading: Bool, prefetchScreens:CGFloat=0, loadMore: @escaping () async -> Void) -> some View {
        modifier(AutomaticPagination(itemCount: itemCount, canLoadMore: canLoadMore, isLoading: isLoading, prefetchScreens:prefetchScreens, loadMore: loadMore))
    }
}

struct InfiniteScrollFooter: View {
    let itemCount: Int
    let canLoadMore: Bool
    let isLoading: Bool
    var loadMore: () async -> Void
    @State private var isVisible = false
    @State private var operation: Task<Void, Never>?
    @ViewBuilder var body: some View {
        if #available(iOS 18.0, *) { loadingFrame(isLoading) }
        else { legacyFooter }
    }
    private func loadingFrame(_ active: Bool) -> some View {
        ZStack {
            if active { PaginationLoadingIndicator() }
            Color.clear.frame(height: 1)
        }.frame(maxWidth: .infinity).frame(height: 56)
    }
    private var legacyFooter: some View {
        let visibleBottom = UIScreen.main.bounds.height - 30
        return loadingFrame(isLoading || operation != nil)
            .onGeometryChange(for: Bool.self) { geometry in
                let frame = geometry.frame(in: .global)
                return frame.minY < visibleBottom && frame.maxY > 0
            } action: { isVisible = $0 }
            .onAppear { startIfNeeded() }
            .onChange(of: isVisible) { _, _ in startIfNeeded() }
            .onChange(of: isLoading) { _, _ in startIfNeeded() }
            .onChange(of: itemCount) { _, _ in startIfNeeded() }
            .onChange(of: canLoadMore) { _, _ in startIfNeeded() }
            .onChange(of: operation == nil) { _, ready in if ready { startIfNeeded() } }
            .onDisappear { isVisible = false }
    }
    private func startIfNeeded() {
        guard isVisible, canLoadMore, !isLoading, operation == nil, itemCount > 0 else { return }
        // Scrolling away must not cancel an already requested page. The list owns query validation.
        operation = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            await loadMore()
            operation = nil
        }
    }
}

private struct PaginationLoadingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false
    var body: some View {
        Group {
            if reduceMotion { ProgressView().tint(Design.accent) }
            else {
                HStack(spacing: 7) {
                    ForEach(0..<3) { index in
                        Circle().fill(Design.accent).frame(width: 7, height: 7)
                            .scaleEffect(animating ? 1 : 0.65).opacity(animating ? 0.9 : 0.3)
                            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(Double(index) * 0.14), value: animating)
                    }
                }.onAppear { animating = true }
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel("正在加载")
            .accessibilityIdentifier("pagination.loading")
    }
}

struct AccentButton: View {
    let title: String
    var icon: String? = nil
    var isLoading = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading { ProgressView().tint(.white) }
                else if let icon { Image(systemName: icon) }
                Text(title).font(.headline)
            }
            .frame(maxWidth: .infinity)
        }
        .primaryActionStyle()
        .disabled(isLoading)
    }
}

struct RoundIconButton: View {
    let icon: String
    let label: String
    var action: () -> Void
    @ViewBuilder var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            Button(action:action) {
                Image(systemName:icon).font(.system(size:17,weight:.semibold))
                    .frame(width:30,height:30)
            }.buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large)
                .tint(Design.ink).accessibilityLabel(label)
        } else { legacyButton }
        #else
        legacyButton
        #endif
    }
    private var legacyButton: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Design.ink).frame(width: 32, height: 32)
        }.buttonStyle(.bordered).buttonBorderShape(.circle).controlSize(.large).accessibilityLabel(label)
    }
}

struct Artwork: View {
    let kind: ArtworkKind
    var compact = false
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack {
                LinearGradient(colors: kind.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(kind.colors[2].opacity(0.35)).frame(width: width * 0.9)
                    .blur(radius: 30).offset(x: width * 0.3, y: -height * 0.15)
                Canvas { context, size in
                    let center = CGPoint(x: size.width * 0.52, y: size.height * 0.46)
                    for index in 0..<5 {
                        let radius = size.width * (0.21 + Double(index) * 0.075)
                        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                        context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(index == 1 ? 0.35 : 0.10)), lineWidth: 0.7)
                    }
                    for index in 0..<24 {
                        let angle = Double(index) * .pi / 12
                        let radius = size.width * 0.41
                        let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                        context.fill(Path(ellipseIn: CGRect(x: point.x, y: point.y, width: index % 3 == 0 ? 3 : 1.5, height: index % 3 == 0 ? 3 : 1.5)), with: .color(.white.opacity(0.5)))
                    }
                }
                Image(systemName: kind.symbol)
                    .font(.system(size: min(width, height) * 0.45, weight: .ultraLight))
                    .foregroundStyle(.linearGradient(colors: [.white, kind.colors[2].opacity(0.4)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: kind.colors[2].opacity(0.55), radius: 20)
                    .rotationEffect(.degrees(-12)).offset(y: -height * 0.04)
                VStack {
                    HStack {
                        Text("EX / \(kind == .blue ? "01" : kind == .forest ? "02" : kind == .ember ? "03" : "04")")
                            .font(.system(size: compact ? 7 : 9, weight: .medium, design: .monospaced)).tracking(2)
                        Spacer()
                        Image(systemName: "sparkle").font(.system(size: compact ? 8 : 12))
                    }
                    Spacer()
                    HStack {
                        Text("THE ART OF DUEL").font(.system(size: compact ? 6 : 8, weight: .medium)).tracking(compact ? 1 : 2)
                        Spacer()
                    }
                }.padding(compact ? 10 : 18).foregroundStyle(.white.opacity(0.72))
            }
        }.clipped().accessibilityHidden(true)
    }
}

struct DeckTile: View {
    let deck: Deck
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Artwork(kind: deck.kind).aspectRatio(1.12, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 21))
            Text(deck.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Design.ink)
            Text("\(deck.cards) 张 · \(deck.kind == .blue ? "龙族" : deck.kind == .forest ? "自然" : deck.kind == .ember ? "炎属性" : "魔法师")")
                .font(.system(size: 11)).foregroundStyle(Design.secondary)
        }
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let subtitle: String
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            if !subtitle.isEmpty { Text(subtitle) }
        }.frame(maxWidth: .infinity)
    }
}

struct ModalCloseButton: View {
    var hitSize:CGFloat=44
    var action:(()->Void)?=nil
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Button { if let action {action()} else{dismiss()} } label: {
            Image(systemName: "xmark").font(.system(size: 17, weight: .semibold))
                .frame(width: hitSize, height: hitSize).contentShape(Rectangle())
        }.accessibilityLabel("关闭").tint(Design.ink)
    }
}

extension View {
    @ViewBuilder func stableSearchToolbar() -> some View {
        if #available(iOS 17.1, *) { searchPresentationToolbarBehavior(.avoidHidingContent) }
        else { self }
    }
}
