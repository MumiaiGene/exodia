import SwiftUI

struct DataStormLaunchScreen: View {
    let isReady: Bool
    let isEntering: Bool
    let enter: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.008, green: 0.027, blue: 0.09),
                        Color(red: 0.008, green: 0.105, blue: 0.28),
                        Color(red: 0.018, green: 0.20, blue: 0.43)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                DataStormField(isReady: isReady, isEntering: isEntering, reduceMotion: reduceMotion)
                    .scaleEffect(isEntering && !reduceMotion ? 1.16 : 1)
                    .brightness(isEntering && !reduceMotion ? 0.22 : 0)
                    .opacity(isEntering ? 0 : 1)

                if isReady {
                    DataStormEntryPrompt(availableWidth: proxy.size.width, reduceMotion: reduceMotion)
                        .position(x: proxy.size.width / 2, y: proxy.size.height * 0.70)
                        .scaleEffect(isEntering ? 1.10 : 1)
                        .opacity(isEntering ? 0 : 1)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }

                if isReady && !isEntering {
                    Button(action: enter) {
                        Color.clear
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("进入 App")
                    .accessibilityHint("进入首页")
                    .accessibilityIdentifier("launch.enter")
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Color(red: 0.008, green: 0.027, blue: 0.09))
        .ignoresSafeArea()
        .animation(reduceMotion ? .easeOut(duration: 0.25) : .easeOut(duration: 0.48), value: isReady)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .easeIn(duration: 0.42), value: isEntering)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isReady ? "加载完成，等待进入" : "正在载入首页和个人资料")
        .accessibilityIdentifier("launch.dataStorm")
    }
}

private struct DataStormField: View {
    let isReady: Bool
    let isEntering: Bool
    let reduceMotion: Bool
    @State private var startedAt = Date.now

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 / 12.0 : 1.0 / 60.0, paused: reduceMotion)) { timeline in
            Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                let elapsed = max(0, timeline.date.timeIntervalSince(startedAt))
                let speed = isEntering ? 2.8 : (isReady ? 0.68 : 1.0)
                let time = reduceMotion ? 0.75 : elapsed * speed
                drawStorm(context: &context, size: size, time: time, ready: isReady)
            }
        }
        .accessibilityHidden(true)
    }

    private func drawStorm(context: inout GraphicsContext, size: CGSize, time: Double, ready: Bool) {
        let center = CGPoint(x: size.width * 0.48, y: size.height * 0.42)
        let maximumRadius = hypot(size.width, size.height) * 0.82
        context.blendMode = .plusLighter

        drawPerspectiveGrid(context: &context, center: center, radius: maximumRadius, time: time)
        drawVortex(context: &context, center: center, radius: maximumRadius, time: time)
        drawStreams(context: &context, center: center, radius: maximumRadius, time: time)
        drawFragments(context: &context, center: center, radius: maximumRadius, time: time)
        drawCore(context: &context, center: center, time: time, ready: ready)
    }

    private func drawPerspectiveGrid(context: inout GraphicsContext, center: CGPoint, radius: CGFloat, time: Double) {
        for index in 0..<24 {
            let angle = Double(index) * .pi * 2 / 24 + sin(time * 0.14) * 0.025
            var line = Path()
            line.move(to: point(center, radius: 22, angle: angle))
            line.addLine(to: point(center, radius: radius, angle: angle))
            context.stroke(line, with: .color(Color(red: 0.08, green: 0.55, blue: 1).opacity(0.10)), lineWidth: index.isMultiple(of: 3) ? 0.8 : 0.35)
        }

        for index in 0..<9 {
            let phase = fraction(time * 0.13 + Double(index) / 9)
            let ringRadius = 30 + CGFloat(pow(phase, 1.8)) * radius
            let alpha = (1 - phase) * phase * 0.36
            let rect = CGRect(x: center.x - ringRadius, y: center.y - ringRadius, width: ringRadius * 2, height: ringRadius * 2)
            context.stroke(Path(ellipseIn: rect), with: .color(Color(red: 0.12, green: 0.64, blue: 1).opacity(alpha)), lineWidth: index.isMultiple(of: 3) ? 1.1 : 0.45)
        }
    }

    private func drawVortex(context: inout GraphicsContext, center: CGPoint, radius: CGFloat, time: Double) {
        let radii: [CGFloat] = [52, 84, 126, 178, 242]
        for (index, currentRadius) in radii.enumerated() {
            let direction = index.isMultiple(of: 2) ? 1.0 : -1.0
            let start = time * (0.24 + Double(index) * 0.018) * direction + Double(index) * 0.9
            var arc = Path()
            arc.addArc(
                center: center,
                radius: currentRadius,
                startAngle: .radians(start),
                endAngle: .radians(start + direction * (1.65 + Double(index) * 0.18)),
                clockwise: direction < 0
            )
            context.stroke(
                arc,
                with: .linearGradient(
                    Gradient(colors: [Color.clear, Color(red: 0.28, green: 0.91, blue: 1), Color.white.opacity(0.8), Color.clear]),
                    startPoint: CGPoint(x: center.x - currentRadius, y: center.y),
                    endPoint: CGPoint(x: center.x + currentRadius, y: center.y)
                ),
                style: StrokeStyle(lineWidth: index < 2 ? 2.2 : 1.2, lineCap: .square)
            )
        }

        let outerPhase = fraction(time * 0.08)
        let outerRadius = radius * (0.16 + CGFloat(outerPhase) * 0.20)
        let outerRect = CGRect(x: center.x - outerRadius, y: center.y - outerRadius, width: outerRadius * 2, height: outerRadius * 2)
        context.stroke(Path(ellipseIn: outerRect), with: .color(Color(red: 0.33, green: 0.92, blue: 1).opacity(0.12)), lineWidth: 2)
    }

    private func drawStreams(context: inout GraphicsContext, center: CGPoint, radius: CGFloat, time: Double) {
        for index in 0..<82 {
            let seed = unit(index, salt: 1)
            let speed = 0.22 + unit(index, salt: 2) * 0.36
            let phase = fraction(time * speed + unit(index, salt: 3))
            let eased = pow(phase, 2.25)
            let baseAngle = unit(index, salt: 4) * .pi * 2
            let spiral = (1 - phase) * 0.30 + sin(time * 0.16 + seed * 7) * 0.025
            let angle = baseAngle + spiral
            let outer = 18 + CGFloat(eased) * radius
            let length = 5 + CGFloat(phase * phase) * (32 + CGFloat(unit(index, salt: 5)) * 60)
            let head = point(center, radius: outer, angle: angle)
            let tail = point(center, radius: max(14, outer - length), angle: angle - 0.012)
            var path = Path()
            path.move(to: tail)
            path.addLine(to: head)
            let fade = sin(phase * .pi)
            let color = index.isMultiple(of: 7) ? Color.white : Color(red: 0.12, green: 0.69, blue: 1)
            context.stroke(path, with: .color(color.opacity(0.12 + fade * 0.58)), style: StrokeStyle(lineWidth: 0.6 + phase * 1.8, lineCap: .square))
        }
    }

    private func drawFragments(context: inout GraphicsContext, center: CGPoint, radius: CGFloat, time: Double) {
        for index in 0..<22 {
            let phase = fraction(time * (0.10 + unit(index, salt: 7) * 0.12) + unit(index, salt: 8))
            let angle = unit(index, salt: 9) * .pi * 2 + (1 - phase) * 0.22
            let distance = 42 + CGFloat(pow(phase, 1.9)) * radius
            let location = point(center, radius: distance, angle: angle)
            let tangent = angle + .pi / 2
            let long = 6 + CGFloat(phase) * (18 + CGFloat(unit(index, salt: 10)) * 28)
            let wide = 2 + CGFloat(phase) * 5
            let radial = CGVector(dx: cos(angle), dy: sin(angle))
            let side = CGVector(dx: cos(tangent), dy: sin(tangent))
            let a = CGPoint(x: location.x - radial.dx * long * 0.5 - side.dx * wide, y: location.y - radial.dy * long * 0.5 - side.dy * wide)
            let b = CGPoint(x: location.x + radial.dx * long * 0.5 - side.dx * wide, y: location.y + radial.dy * long * 0.5 - side.dy * wide)
            let c = CGPoint(x: location.x + radial.dx * long * 0.5 + side.dx * wide, y: location.y + radial.dy * long * 0.5 + side.dy * wide)
            let d = CGPoint(x: location.x - radial.dx * long * 0.5 + side.dx * wide, y: location.y - radial.dy * long * 0.5 + side.dy * wide)
            var shard = Path()
            shard.move(to: a); shard.addLine(to: b); shard.addLine(to: c); shard.addLine(to: d); shard.closeSubpath()
            let opacity = sin(phase * .pi) * 0.20
            context.fill(shard, with: .color(Color(red: 0.16, green: 0.78, blue: 1).opacity(opacity)))
            context.stroke(shard, with: .color(Color(red: 0.54, green: 0.95, blue: 1).opacity(opacity * 1.9)), lineWidth: 0.7)
        }
    }

    private func drawCore(context: inout GraphicsContext, center: CGPoint, time: Double, ready: Bool) {
        let pulse = (ready ? 4.5 : 5.5) + CGFloat(sin(time * (ready ? 2.0 : 3.1))) * (ready ? 1.2 : 1.8)
        let glowRadius: CGFloat = ready ? 76 : 62
        let glow = CGRect(x: center.x - glowRadius, y: center.y - glowRadius, width: glowRadius * 2, height: glowRadius * 2)
        context.fill(
            Path(ellipseIn: glow),
            with: .radialGradient(
                Gradient(colors: [Color.white.opacity(ready ? 0.28 : 0.20), Color(red: 0.18, green: 0.78, blue: 1).opacity(0.15), Color.clear]),
                center: center,
                startRadius: 0,
                endRadius: glowRadius
            )
        )
        let core = CGRect(x: center.x - pulse, y: center.y - pulse, width: pulse * 2, height: pulse * 2)
        context.fill(Path(ellipseIn: core), with: .color(Color.white.opacity(0.92)))
        for multiplier in [2.8, 5.2] {
            let value = pulse * multiplier
            let rect = CGRect(x: center.x - value, y: center.y - value, width: value * 2, height: value * 2)
            context.stroke(Path(ellipseIn: rect), with: .color(Color(red: 0.35, green: 0.92, blue: 1).opacity(0.38)), lineWidth: 0.8)
        }
    }

    private func point(_ center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }

    private func fraction(_ value: Double) -> Double { value - floor(value) }

    private func unit(_ index: Int, salt: Int) -> Double {
        let value = sin(Double(index * 127 + salt * 311)) * 43_758.5453
        return value - floor(value)
    }
}

private struct DataStormEntryPrompt: View {
    let availableWidth: CGFloat
    let reduceMotion: Bool
    private let title = Array("INTO THE VRAINS")

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let size = min(32, max(24, availableWidth * 0.075))
            HStack(spacing: max(0.5, size * 0.035)) {
                ForEach(Array(title.enumerated()), id: \.offset) { index, glyph in
                    if glyph == " " {
                        Color.clear.frame(width: size * 0.36, height: size)
                    } else {
                        let energy = reduceMotion ? 0 : pow(max(0, sin(time * 4.4 - Double(index) * 0.52)), 6)
                        DataStormGlyph(value: String(glyph), size: size)
                            .offset(y: -energy * 2.2)
                            .scaleEffect(1 + energy * 0.035)
                            .shadow(color: Color(red: 0.32, green: 0.92, blue: 1).opacity(0.35 + energy * 0.45), radius: 5 + energy * 4)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("INTO THE VRAINS")
        .accessibilityIdentifier("launch.prompt")
    }
}

private struct DataStormGlyph: View {
    let value: String
    let size: CGFloat

    private var font: Font { .custom("DINAlternate-Bold", fixedSize: size) }
    private let outer: [CGSize] = [
        CGSize(width: -1.7, height: 0), CGSize(width: 1.7, height: 0),
        CGSize(width: 0, height: -1.7), CGSize(width: 0, height: 1.7),
        CGSize(width: -1.2, height: -1.2), CGSize(width: 1.2, height: -1.2),
        CGSize(width: -1.2, height: 1.2), CGSize(width: 1.2, height: 1.2)
    ]

    var body: some View {
        ZStack {
            ForEach(Array(outer.enumerated()), id: \.offset) { _, offset in
                Text(value).font(font).foregroundStyle(Color(red: 0.0, green: 0.08, blue: 0.22))
                    .offset(x: offset.width, y: offset.height)
            }
            Text(value).font(font).foregroundStyle(Color(red: 0.34, green: 0.91, blue: 1))
                .offset(y: 0.6)
            Text(value).font(font).foregroundStyle(Color(red: 0.96, green: 0.99, blue: 1))
        }
    }
}
