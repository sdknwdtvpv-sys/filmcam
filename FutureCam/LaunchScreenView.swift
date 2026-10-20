import SwiftUI

/// 开机页：机器上电。
/// 铝面 → 刻字浮起 → 一道高光扫过 → 启动进度线走到头 → 指示灯亮 → 让位给取景器。
struct LaunchScreenView: View {
    var onFinish: () -> Void
    /// 调试用：停在最后一帧不自动退场，方便截图
    var frozen: Bool = false

    @State private var revealText: Bool = false
    @State private var sweep: CGFloat = -0.25
    @State private var progress: CGFloat = 0
    @State private var ledOn: Bool = false
    @State private var leaving: Bool = false
    /// 整块铝面被一道光自上而下扫过
    @State private var scan: CGFloat = -0.25

    private let wordmark = "FUTURE CAM"

    var body: some View {
        let t = ThemeStore.current

        ZStack {
            AluminumFace(tokens: t).ignoresSafeArea()

            // 上下压一点暗，像铝面在灯下的落差
            LinearGradient(colors: [.black.opacity(0.16), .clear, .black.opacity(0.2)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            // 扫描光带：从上往下扫过整块面板
            GeometryReader { geo in
                LinearGradient(colors: [.clear, .white.opacity(0.55), .white.opacity(0.9),
                                        .white.opacity(0.55), .clear],
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
                    .opacity(revealText ? 1 : 0)
                    .blur(radius: revealText ? 0 : 6)
                    .offset(y: revealText ? 0 : 8)

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

    // MARK: 刻字 + 高光

    private func wordmarkView(_ t: ThemeTokens) -> some View {
        ZStack {
            Text(wordmark)
                .font(t.labelFont(30, .medium))
                .tracking(9)
                .foregroundColor(t.ink)
                .shadow(color: .white.opacity(0.55), radius: 0, y: 0.8)

            // 同一段字再叠一层只在窄带里透光的白，形成扫光
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

    /// 分段刻度条：一格一格点亮，像仪表盘自检
    private func progressLine(_ t: ThemeTokens) -> some View {
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

    /// 四角的取景角标（让开灵动岛和 home indicator）
    private func cornerTicks(_ t: ThemeTokens) -> some View {
        let len: CGFloat = 18
        let inset: CGFloat = 26
        let topInset: CGFloat = 68
        let bottomInset: CGFloat = 42
        return GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let inset = inset
            Path { path in
                // 左上
                path.move(to: CGPoint(x: inset, y: topInset + len))
                path.addLine(to: CGPoint(x: inset, y: topInset))
                path.addLine(to: CGPoint(x: inset + len, y: topInset))
                // 右上
                path.move(to: CGPoint(x: w - inset - len, y: topInset))
                path.addLine(to: CGPoint(x: w - inset, y: topInset))
                path.addLine(to: CGPoint(x: w - inset, y: topInset + len))
                // 左下
                path.move(to: CGPoint(x: inset, y: h - bottomInset - len))
                path.addLine(to: CGPoint(x: inset, y: h - bottomInset))
                path.addLine(to: CGPoint(x: inset + len, y: h - bottomInset))
                // 右下
                path.move(to: CGPoint(x: w - inset - len, y: h - bottomInset))
                path.addLine(to: CGPoint(x: w - inset, y: h - bottomInset))
                path.addLine(to: CGPoint(x: w - inset, y: h - bottomInset - len))
            }
            .stroke(t.ink.opacity(revealText ? 0.36 : 0), lineWidth: 1)
        }
    }

    // MARK: 时序

    private func boot() async {
        withAnimation(.easeOut(duration: 0.45)) { revealText = true }

        try? await Task.sleep(nanoseconds: 60_000_000)
        withAnimation(.linear(duration: 1.15)) { scan = 1.25 }

        try? await Task.sleep(nanoseconds: 120_000_000)
        withAnimation(.easeInOut(duration: 1.05)) { sweep = 1.3 }

        try? await Task.sleep(nanoseconds: 80_000_000)
        withAnimation(.easeInOut(duration: 1.05)) { progress = 1 }

        try? await Task.sleep(nanoseconds: 900_000_000)
        withAnimation(.easeOut(duration: 0.18)) { ledOn = true }

        try? await Task.sleep(nanoseconds: 520_000_000)
        guard !frozen else { return }

        withAnimation(.easeInOut(duration: 0.42)) { leaving = true }
        try? await Task.sleep(nanoseconds: 420_000_000)
        onFinish()
    }
}
