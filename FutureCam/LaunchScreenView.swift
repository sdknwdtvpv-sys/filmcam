import SwiftUI

/// 开机页里刻字的出场方式
enum LaunchIntroStyle {
    /// 直接浮起 + 一道高光扫过（采样失败时的兜底）
    case engraved
    /// 噪点汇聚成型（默认）
    case noise
}

/// 开机页：机器上电。
/// 铝面 → 刻字出场 → 光带扫过 → 分段刻度自检 → 指示灯亮 → 让位给取景器。
struct LaunchScreenView: View {
    var onFinish: () -> Void
    var frozen: Bool = false
    var style: LaunchIntroStyle = .noise
    /// 调试用：把进度钉死在这个值上，不播动画（方便截图对比）
    var fixedProgress: CGFloat? = nil

    @State private var start = Date()
    @State private var leaving = false
    @State private var markFrame: CGRect = .zero

    private let wordmark = "FUTURE CAM"
    /// 个人标识：改这一个常量即可
    private let maker = "ELLIOT"

    // 时间轴（秒）
    private let revealEnd: Double = 0.45
    private let scanStart: Double = 0.06
    private let scanDuration: Double = 1.20
    private let convergeStart: Double = 0.18
    private let convergeDuration: Double = 2.05
    private let ledAt: Double = 2.02
    private let outAt: Double = 2.42
    private let total: Double = 2.85

    var body: some View {
        let t = ThemeStore.current

        // 用 TimelineView 而不是 withAnimation：进度要逐帧驱动 Canvas，
        // SwiftUI 的隐式动画不会为它插值，会直接跳到终态。
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: fixedProgress != nil)) { context in
            // 定格模式下把时间轴推到末尾，否则按时间淡入的元素会是空的
            let elapsed = fixedProgress == nil ? context.date.timeIntervalSince(start) : total
            let reveal = fixedProgress == nil ? min(1, elapsed / revealEnd) : 1
            let converge = fixedProgress ?? min(max((elapsed - convergeStart) / convergeDuration, 0), 1)
            let led = fixedProgress != nil ? true : elapsed > ledAt

            ZStack {
                AluminumFace(tokens: t).ignoresSafeArea()

                LinearGradient(colors: [.black.opacity(0.16), .clear, .black.opacity(0.2)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                if style == .noise, !WordmarkField.shared.points.isEmpty {
                    particleCloud(t, converge: converge)
                        .allowsHitTesting(false)
                }

                scanBand(t, elapsed: elapsed, reveal: reveal)

                cornerTicks(t, opacity: 0.36 * reveal)

                VStack(spacing: 16) {
                    wordmarkView(t, reveal: reveal, converge: converge)
                    progressLine(t, progress: converge)
                        .opacity(reveal)
                    VStack(spacing: 5) {
                        HStack(spacing: 6) {
                            LEDDot(color: t.glow, size: 4, dimmed: !led)
                            Silkscreen(text: "M-01 RANGEFINDER",
                                       color: t.ink.opacity(0.5), size: 6.5, tracking: 2.2)
                        }

                        // 制作者落款：比型号再弱一级，只做气质不做信息
                        Silkscreen(text: "BY \(maker)",
                                   color: t.ink.opacity(0.3), size: 5.5, tracking: 2.8)
                            .opacity(min(max((elapsed - (ledAt - 0.25)) / 0.4, 0), 1))
                    }
                    .opacity(reveal)
                }
            }
            .onPreferenceChange(MarkFrameKey.self) { markFrame = $0 }
            .opacity(leaving ? 0 : 1)
            .scaleEffect(leaving ? 1.04 : 1)
        }
        .ignoresSafeArea()
        .task {
            guard fixedProgress == nil else { return }
            try? await Task.sleep(nanoseconds: UInt64((frozen ? total : outAt) * 1_000_000_000))
            guard !frozen else { return }
            withAnimation(.easeInOut(duration: 0.42)) { leaving = true }
            try? await Task.sleep(nanoseconds: 420_000_000)
            onFinish()
        }
    }

    // MARK: 刻字

    @ViewBuilder
    private func wordmarkView(_ t: ThemeTokens, reveal: Double, converge: Double) -> some View {
        switch style {
        case .engraved:
            engraved(t, sweep: -1)
                .opacity(reveal)
                .blur(radius: (1 - reveal) * 6)
                .offset(y: (1 - reveal) * 8)
        case .noise:
            if WordmarkField.shared.points.isEmpty {
                engraved(t, sweep: -1).opacity(reveal)
            } else {
                engraved(t, sweep: -1)
                    .opacity(max(0, (Double(converge) - 0.62) / 0.38))
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: MarkFrameKey.self,
                                                   value: proxy.frame(in: .global))
                        }
                    )
            }
        }
    }

    /// 粒子层：全屏铺开，从屏幕边缘一路收拢到刻字上
    private func particleCloud(_ t: ThemeTokens, converge: Double) -> some View {
        let field = WordmarkField.shared
        let settle = Double(min(max(converge, 0), 1))
        let sharp = max(0, (settle - 0.70) / 0.30)
        let dotsFade = 1 - sharp
        let centre = markFrame == .zero
            ? CGPoint(x: 0.5, y: 0.5)
            : CGPoint(x: markFrame.midX, y: markFrame.midY)
        let targetSize = markFrame == .zero ? field.size : markFrame.size

        return GeometryReader { geo in
            let radius = max(geo.size.width, geo.size.height) * 0.78

            Canvas { ctx, _ in
                for (index, point) in field.points.enumerated() {
                    let r1 = Double(hash(index &* 7 &+ 1) % 10_000) / 10_000
                    let r2 = Double(hash(index &* 7 &+ 2) % 10_000) / 10_000
                    let r3 = Double(hash(index &* 7 &+ 3) % 10_000) / 10_000
                    let r4 = Double(hash(index &* 7 &+ 4) % 10_000) / 10_000
                    let r5 = Double(hash(index &* 7 &+ 5) % 10_000) / 10_000
                    let r6 = Double(hash(index &* 7 &+ 6) % 10_000) / 10_000

                    // 起点撒在屏幕外圈，所以是「从四面八方收进来」
                    let angle = r1 * 2 * .pi
                    let distance = radius * (0.55 + 0.75 * r2)
                    let start = CGPoint(x: centre.x + cos(angle) * distance,
                                        y: centre.y + sin(angle) * distance)

                    let target = CGPoint(x: centre.x + (point.x - 0.5) * targetSize.width,
                                         y: centre.y + (point.y - 0.5) * targetSize.height)

                    // 每颗粒子在自己的时间点落地（0.55…0.97），所以是一波一波到位
                    let landing = 0.55 + 0.42 * r3
                    let local = min(1, settle / max(0.05, landing))
                    let eased = 1 - pow(1 - local, 2.4)

                    var x = start.x + (target.x - start.x) * eased
                    var y = start.y + (target.y - start.y) * eased

                    // 落地之后还有一小段衰减抖动，像磁铁吸住之前先弹几下
                    if r4 < 0.45, settle > landing {
                        let since = settle - landing
                        // 衰减控制「抖几下」：半衰期约 0.13 秒，频率 4.5–8 Hz
                        let decay = exp(-since * 11)
                        let amplitude = 3.0 * decay
                        let frequency = 9 + 7 * r5
                        let phase = r6 * 2 * .pi
                        x += cos(since * frequency * 2 * .pi + phase) * amplitude
                        y += sin(since * frequency * 2 * .pi + phase * 1.6) * amplitude
                    }

                    let dotRadius = 0.9 + 1.7 * (1 - eased)
                    let alpha = (0.22 + 0.78 * min(1, eased * 1.4)) * dotsFade
                    guard alpha > 0.01 else { continue }

                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x - dotRadius, y: y - dotRadius,
                                               width: dotRadius * 2, height: dotRadius * 2)),
                        with: .color(t.ink.opacity(alpha)))
                }
            }
        }
        .ignoresSafeArea()
        .opacity(markFrame == .zero ? 0 : 1)
    }

    /// 刻进铝里的字：深墨 + 下缘一道白边
    private func engraved(_ t: ThemeTokens, sweep: CGFloat) -> some View {
        ZStack {
            Text(wordmark)
                .font(t.labelFont(30, .medium))
                .tracking(9)
                .foregroundColor(t.ink)
                .shadow(color: .white.opacity(0.55), radius: 0, y: 0.8)

            Text(wordmark)
                .font(t.labelFont(30, .medium))
                .tracking(9)
                .foregroundStyle(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: max(0, sweep - 0.16)),
                            .init(color: .white.opacity(0.95), location: max(0, min(1, sweep))),
                            .init(color: .clear, location: min(1, sweep + 0.16))
                        ],
                        startPoint: .leading, endPoint: .trailing)
                )
                .blendMode(.plusLighter)
        }
    }

    /// 噪点汇聚：点从散开位置收拢成字形，末段压上真字并让粒子退场
    private func noiseWordmark(_ t: ThemeTokens, reveal: Double, converge: Double) -> some View {
        let field = WordmarkField.shared
        let settle = Double(min(max(converge, 0), 1))
        let sharp = max(0, (settle - 0.62) / 0.38)
        let dotsFade = 1 - sharp * 0.92
        let width = max(field.size.width, 1)
        let height = max(field.size.height, 1)

        return ZStack {
            Canvas { ctx, size in
                for (index, point) in field.points.enumerated() {
                    // 归一化到 0…1，否则 UInt64 直接转 Double 会是个天文数字
                    let r1 = Double(hash(index &* 2 &+ 1) % 10_000) / 10_000
                    let r2 = Double(hash(index &* 2 &+ 7) % 10_000) / 10_000
                    let scatter = 1 - settle
                    let dx = (r1 - 0.5) * 2 * 205 * scatter
                    let dy = (r2 - 0.5) * 2 * 125 * scatter
                    let x = point.x * size.width + dx
                    let y = point.y * size.height + dy
                    let radius = 1.0 + 1.1 * scatter
                    let alpha = (0.45 + 0.55 * settle) * dotsFade
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                                               width: radius * 2, height: radius * 2)),
                        with: .color(t.ink.opacity(alpha)))
                }
            }
            .frame(width: width, height: height)

            engraved(t, sweep: -1).opacity(sharp)
        }
        .opacity(reveal)
    }

    // MARK: 扫描光带 / 刻度 / 角标

    private func scanBand(_ t: ThemeTokens, elapsed: Double, reveal: Double) -> some View {
        let progress = min(max((elapsed - scanStart) / scanDuration, 0), 1.4)
        return GeometryReader { geo in
            LinearGradient(colors: [.clear, .white.opacity(0.45), .white.opacity(0.8),
                                    .white.opacity(0.45), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 190)
                .offset(y: progress * (geo.size.height + 380) - 190)
                .blendMode(.plusLighter)
                .opacity(reveal)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// 分段刻度条：一格一格点亮，像仪表盘自检
    private func progressLine(_ t: ThemeTokens, progress: Double) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<20, id: \.self) { index in
                let lit = Double(index) / 19.0 <= progress
                RoundedRectangle(cornerRadius: 1)
                    .fill(lit ? t.accent : t.ink.opacity(0.14))
                    .frame(width: 6, height: 3)
                    .shadow(color: lit ? t.accent.opacity(0.6) : .clear, radius: 2)
            }
        }
    }

    private func cornerTicks(_ t: ThemeTokens, opacity: Double) -> some View {
        let len: CGFloat = 18
        let inset: CGFloat = 26
        let topInset: CGFloat = 68
        let bottomInset: CGFloat = 42
        return GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            Path { path in
                path.move(to: CGPoint(x: inset, y: topInset + len))
                path.addLine(to: CGPoint(x: inset, y: topInset))
                path.addLine(to: CGPoint(x: inset + len, y: topInset))

                path.move(to: CGPoint(x: w - inset - len, y: topInset))
                path.addLine(to: CGPoint(x: w - inset, y: topInset))
                path.addLine(to: CGPoint(x: w - inset, y: topInset + len))

                path.move(to: CGPoint(x: inset, y: h - bottomInset - len))
                path.addLine(to: CGPoint(x: inset, y: h - bottomInset))
                path.addLine(to: CGPoint(x: inset + len, y: h - bottomInset))

                path.move(to: CGPoint(x: w - inset - len, y: h - bottomInset))
                path.addLine(to: CGPoint(x: w - inset, y: h - bottomInset))
                path.addLine(to: CGPoint(x: w - inset, y: h - bottomInset - len))
            }
            .stroke(t.ink.opacity(opacity), lineWidth: 1)
        }
    }

    /// 每个粒子一个稳定的伪随机数
    private func hash(_ value: Int) -> UInt64 {
        var h = UInt64(bitPattern: Int64(value)) &* 6_364_136_223_846_793_005
        h ^= h >> 33
        h = h &* 0xff51afd7ed558ccd
        h ^= h >> 29
        return h
    }
}

// MARK: - 刻字采样

/// 从字体轮廓里直接采点，不走位图渲染 —— 冷启动最早期渲染管线还没就绪，
/// UIGraphicsImageRenderer 有可能返回空图，那样粒子会整个消失。
/// 刻字在屏幕上的实际位置，粒子层据此瞄准
struct MarkFrameKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

@MainActor
struct WordmarkField {
    static let shared = build()

    let points: [CGPoint]
    let size: CGSize

    private static func build() -> WordmarkField {
        let wordmark = "FUTURE CAM"
        let fontSize: CGFloat = 30
        let kern: CGFloat = 9

        let font = CTFontCreateWithName("Futura-Medium" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTKernAttributeName as String): kern
        ]
        let attributed = NSAttributedString(string: wordmark, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)

        let path = CGMutablePath()
        if let runs = CTLineGetGlyphRuns(line) as? [CTRun] {
            for run in runs {
                let count = CTRunGetGlyphCount(run)
                guard count > 0 else { continue }
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRangeMake(0, count), &glyphs)
                CTRunGetPositions(run, CFRangeMake(0, count), &positions)

                for index in 0..<count {
                    guard let glyphPath = CTFontCreatePathForGlyph(font, glyphs[index], nil) else { continue }
                    var transform = CGAffineTransform(translationX: positions[index].x,
                                                      y: positions[index].y)
                    path.addPath(glyphPath, transform: transform)
                    _ = transform
                }
            }
        }

        let bounds = path.boundingBoxOfPath
        guard bounds.width > 1, bounds.height > 1, bounds.width.isFinite else {
            return WordmarkField(points: [], size: CGSize(width: 320, height: 40))
        }

        // 网格采样：落在字形内部的点留下。Core Text 的 y 向上，画布 y 向下，这里翻转
        var points: [CGPoint] = []
        let step: CGFloat = 0.85
        var y = bounds.minY
        while y < bounds.maxY {
            var x = bounds.minX
            while x < bounds.maxX {
                if path.contains(CGPoint(x: x, y: y)) {
                    points.append(CGPoint(x: (x - bounds.minX) / bounds.width,
                                          y: 1 - (y - bounds.minY) / bounds.height))
                }
                x += step
            }
            y += step
        }

        #if DEBUG
        NSLog("[Launch] 刻字轮廓采样 %d 点", points.count)
        #endif
        return WordmarkField(points: Array(points.prefix(2600)), size: bounds.size)
    }
}
