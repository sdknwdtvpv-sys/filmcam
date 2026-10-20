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

    @State private var p: CGFloat = 0
    @State private var revealText = false
    @State private var sweep: CGFloat = -0.25
    @State private var scan: CGFloat = -0.25
    @State private var ledOn = false
    @State private var leaving = false
    /// 刻字采样点与画布尺寸，进程内只算一次

    private let wordmark = "FUTURE CAM"

    var body: some View {
        let t = ThemeStore.current

        ZStack {
            AluminumFace(tokens: t).ignoresSafeArea()

            LinearGradient(colors: [.black.opacity(0.16), .clear, .black.opacity(0.2)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            // 扫描光带
            GeometryReader { geo in
                LinearGradient(colors: [.clear, .white.opacity(0.45), .white.opacity(0.8),
                                        .white.opacity(0.45), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 190)
                    .offset(y: scan * (geo.size.height + 380) - 190)
                    .blendMode(.plusLighter)
                    .opacity(revealText ? 1 : 0)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            cornerTicks(t)

            VStack(spacing: 16) {
                wordmarkView(t)
                progressLine(t)
                    .opacity(revealText ? 1 : 0)
                HStack(spacing: 6) {
                    LEDDot(color: t.glow, size: 4, dimmed: !ledOn)
                    Silkscreen(text: "M-01 RANGEFINDER",
                               color: t.ink.opacity(0.5), size: 6.5, tracking: 2.2)
                }
                .opacity(revealText ? 1 : 0)
            }
        }
        .ignoresSafeArea()
        .opacity(leaving ? 0 : 1)
        .scaleEffect(leaving ? 1.04 : 1)
        .task { await boot() }
    }

    // MARK: 刻字

    @ViewBuilder
    private func wordmarkView(_ t: ThemeTokens) -> some View {
        switch style {
        case .engraved:
            engraved(t)
                .opacity(revealText ? 1 : 0)
                .blur(radius: revealText ? 0 : 6)
                .offset(y: revealText ? 0 : 8)
        case .noise:
            if WordmarkField.shared.points.isEmpty {
                engraved(t).opacity(revealText ? 1 : 0)
            } else {
                noiseWordmark(t)
            }
        }
    }

    /// 刻进铝里的字：深墨 + 下缘一道白边
    private func engraved(_ t: ThemeTokens) -> some View {
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

    /// 噪点汇聚：一堆点从散开的位置收拢成字形，末段再压上真字
    private func noiseWordmark(_ t: ThemeTokens) -> some View {
        let field = WordmarkField.shared
        let settle = Double(min(max(p, 0), 1))
        let width = max(field.size.width, 1)
        let height = max(field.size.height, 1)
        let sharp = max(0, (settle - 0.62) / 0.38)
        // 字变实的同时粒子退场，免得两套字形叠在一起发糊
        let dotsFade = 1 - sharp * 0.92

        return ZStack {
            Canvas { ctx, size in
                guard !field.points.isEmpty else { return }
                for (index, point) in field.points.enumerated() {
                    // 归一化到 0…1，否则 UInt64 直接转 Double 会是个天文数字
                    let r1 = Double(hash(index &* 2 &+ 1) % 10_000) / 10_000
                    let r2 = Double(hash(index &* 2 &+ 7) % 10_000) / 10_000
                    let scatter = 1 - settle
                    let dx = (r1 - 0.5) * 2 * 150 * scatter
                    let dy = (r2 - 0.5) * 2 * 90 * scatter
                    let x = point.x * size.width + dx
                    let y = point.y * size.height + dy
                    let radius = 0.85 + 0.75 * scatter
                    let alpha = (0.2 + 0.8 * settle) * dotsFade
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                                               width: radius * 2, height: radius * 2)),
                        with: .color(t.ink.opacity(alpha)))
                }
            }
            .frame(width: width, height: height)

            engraved(t)
                .opacity(sharp)
        }
        .opacity(revealText ? 1 : 0)
    }

    // MARK: 分段刻度 / 角标

    private func progressLine(_ t: ThemeTokens) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<20, id: \.self) { index in
                let lit = Double(index) / 19.0 <= Double(p)
                RoundedRectangle(cornerRadius: 1)
                    .fill(lit ? t.accent : t.ink.opacity(0.14))
                    .frame(width: 6, height: 3)
                    .shadow(color: lit ? t.accent.opacity(0.6) : .clear, radius: 2)
            }
        }
    }

    private func cornerTicks(_ t: ThemeTokens) -> some View {
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
            .stroke(t.ink.opacity(revealText ? 0.36 : 0), lineWidth: 1)
        }
    }

    // MARK: 字形采样

    /// 每个粒子一个稳定的伪随机数
    private func hash(_ value: Int) -> UInt64 {
        var h = UInt64(bitPattern: Int64(value)) &* 6_364_136_223_846_793_005
        h ^= h >> 33
        h = h &* 0xff51afd7ed558ccd
        h ^= h >> 29
        return h
    }

    // MARK: 时序

    private func boot() async {
        if let fixedProgress {
            p = fixedProgress
            revealText = true
            ledOn = true
            return
        }

        withAnimation(.easeOut(duration: 0.45)) { revealText = true }

        try? await Task.sleep(nanoseconds: 60_000_000)
        withAnimation(.linear(duration: 1.15)) { scan = 1.25 }

        try? await Task.sleep(nanoseconds: 120_000_000)
        withAnimation(.easeInOut(duration: 1.05)) { sweep = 1.3 }

        // 刻字出场进度：噪点/色散都靠这个值
        withAnimation(.easeOut(duration: 0.95)) { p = 1 }

        try? await Task.sleep(nanoseconds: 900_000_000)
        withAnimation(.easeOut(duration: 0.18)) { ledOn = true }

        try? await Task.sleep(nanoseconds: 520_000_000)
        guard !frozen else { return }

        withAnimation(.easeInOut(duration: 0.42)) { leaving = true }
        try? await Task.sleep(nanoseconds: 420_000_000)
        onFinish()
    }
}

// MARK: - 刻字采样

/// 把 FUTURE CAM 渲染成位图、取亮像素当粒子落点。进程内只算一次。
@MainActor
struct WordmarkField {
    static let shared = build()

    let points: [CGPoint]
    let size: CGSize

    private static func build() -> WordmarkField {
        let wordmark = "FUTURE CAM"
        // 和 engraved 用同一个字号、字距，采样画布就等于真字的实际尺寸
        let font = UIFont(name: "Futura-Medium", size: 30) ?? .systemFont(ofSize: 30)
        let text = NSAttributedString(string: wordmark, attributes: [
            .font: font,
            .foregroundColor: UIColor.white,
            .kern: 9
        ])
        let textSize = text.size()
        let w = ceil(textSize.width) + 4
        let h = ceil(textSize.height) + 4
        let canvas = CGSize(width: w, height: h)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        let image = renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: canvas))
            text.draw(at: CGPoint(x: 2, y: 2))
        }
        guard let cg = image.cgImage else { return WordmarkField(points: [], size: canvas) }

        var pixels = [UInt8](repeating: 0, count: Int(w) * Int(h))
        pixels.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress,
                  let ctx = CGContext(data: base, width: Int(w), height: Int(h),
                                      bitsPerComponent: 8, bytesPerRow: Int(w),
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            ctx.draw(cg, in: CGRect(origin: .zero, size: canvas))
        }

        var points: [CGPoint] = []
        let step = 2
        for y in Swift.stride(from: 0, to: Int(h), by: step) {
            for x in Swift.stride(from: 0, to: Int(w), by: step) where pixels[y * Int(w) + x] > 150 {
                points.append(CGPoint(x: CGFloat(x) / w, y: CGFloat(y) / h))
            }
        }
        #if DEBUG
        print("[Launch] 刻字采样 \(points.count) 点 / \(Int(w))x\(Int(h))")
        #endif
        return WordmarkField(points: Array(points.prefix(1500)), size: canvas)
    }
}
