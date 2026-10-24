import SwiftUI

extension MatchKind {
    // Mini-program v227, module 54 MATCH_TYPE_MAP / MATCH_TYPE_CONFIG.
    private static let definitions: [MatchKind] = [.all,
        MatchKind(id: 1, title: "娱乐赛"),
        MatchKind(id: 2, title: "积分赛"),
        MatchKind(id: 3, title: "特殊赛"),
        MatchKind(id: 4, title: "巡回赛"),
        MatchKind(id: 5, title: "邀请赛"),
        MatchKind(id: 6, title: "预选赛"),
        MatchKind(id: 11, title: "游戏王日"),
        MatchKind(id: 12, title: "盛夏大会"),
        MatchKind(id: 13, title: "元素盛典"),
        MatchKind(id: 17, title: "校际杯"),
        MatchKind(id: 18, title: "组队嘉年华"),
        MatchKind(id: 19, title: "巡回赛特别场"),
        MatchKind(id: 20, title: "YCSC"),
        MatchKind(id: 21, title: "一星店公认大会"),
        MatchKind(id: 22, title: "旗舰店特别大会"),
        MatchKind(id: 24, title: "经典时光-交流会"),
        MatchKind(id: 25, title: "经典时光-娱乐赛")
    ]
    static var catalog: [MatchKind] { merged([]) }
    static func merged(_ remote: [MatchKind]) -> [MatchKind] {
        let overrides = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        let combined = definitions.map { $0.id == 20 ? $0 : (overrides[$0.id] ?? $0) } + remote.filter { item in !definitions.contains { $0.id == item.id } }
        let priority = [0, 20, 4, 6, 19, 22, 21, 3, 2]
        return combined.sorted {
            let left = priority.firstIndex(of: $0.id) ?? priority.count
            let right = priority.firstIndex(of: $1.id) ?? priority.count
            return left == right ? $0.id < $1.id : left < right
        }
    }
}

extension MatchKind {
    // Category hues sampled from the mini-program backgrounds; rendered with native capsules.
    var tint: Color {
        let hex: UInt32 = switch id {
        case 1, 11: 0x28B987
        case 2: 0xF14D58
        case 3: 0xDAA000
        case 4: 0x4798E7
        case 5, 6, 12, 13: 0xA17BD5
        case 17: 0xD99442
        case 18: 0x7D8EE7
        case 19: 0xDF937C
        case 20: 0x6485D8
        case 21: 0x9987E7
        case 22: 0xD97BC9
        case 24, 25: 0x8A97CA
        default: 0x909090
        }
        return Color(hex: hex)
    }
}

struct MatchCategoryPill: View {
    let kind: MatchKind
    var selected = false
    var compact = false
    var color: Color? = nil
    @Environment(\.colorScheme) private var colorScheme
    private var tint: Color { color ?? kind.tint }
    var body: some View {
        Text(kind.title)
            .font(.system(size: compact ? 11 : 13, weight: .semibold))
            .foregroundStyle(kind.id == 0 && selected ? Color.white : tint)
            .padding(.horizontal, compact ? 10 : 16).padding(.vertical, compact ? 5 : 9)
            .fixedSize(horizontal: true, vertical: false)
            .background {
                Capsule().fill(kind.id == 0 && selected ? Color.gray : tint.opacity(selected ? 0.25 : (colorScheme == .dark ? 0.10 : 0.07)))
            }
            .overlay { Capsule().strokeBorder(tint.opacity(selected ? 1 : 0.5), lineWidth: selected ? 1.5 : 1) }
    }
}

struct CardTypeLabel: View {
    let kind: MatchKind
    var body: some View {
        Text(kind.title).font(.caption2.weight(.semibold)).multilineTextAlignment(.center).lineLimit(2)
            .foregroundStyle(kind.tint).padding(.horizontal, 7).padding(.vertical, 5)
            .frame(maxWidth: 88).background(kind.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(kind.tint.opacity(0.4), lineWidth: 1) }
    }
}
