import SwiftUI
import UIKit

/// 撕拉片：拍完不是「等显影」，而是一张相纸从仓里被拉出来。
/// 手指往下拉 → 相纸从槽口滑出；拉到底出片完成，轻触关闭。
struct DevelopingPhotoView: View {
    @EnvironmentObject var manager: CameraManager
    let image: UIImage
    let onDismiss: () -> Void
    var initialPull: Double = 0

    @State private var pull: Double
    @State private var dragBase: Double?
    @State private var lastTick: Int = -1

    init(image: UIImage, initialPull: Double = 0, onDismiss: @escaping () -> Void) {
        self.image = image
        self.onDismiss = onDismiss
        self.initialPull = initialPull
        _pull = State(initialValue: initialPull > 0 ? initialPull : 0.12)
    }

    private var done: Bool { pull >= 0.97 }

    var body: some View {
        let t = ThemeStore.current

        ZStack {
            LeatherPanel().ignoresSafeArea()
            Color.black.opacity(0.62).ignoresSafeArea()
                .onTapGesture { if done { onDismiss() } }

            GeometryReader { geo in
                VStack(spacing: 0) {
                    pack.frame(height: max(88, geo.size.height * 0.22))
                    slotLip
                    emerging(t, areaHeight: geo.size.height * 0.66)
                    footer(t)
                }
                .padding(.horizontal, 22)
            }
        }
    }

    // MARK: 相纸仓

    private var pack: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x2B2E31), Color(hex: 0x121416)],
                           startPoint: .top, endPoint: .bottom)
            Text("PEEL-APART")
                .font(.custom("Futura-Medium", size: 11))
                .tracking(3.2)
                .foregroundColor(.white.opacity(0.35))
        }
        .frame(height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .black.opacity(0.55)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.55), radius: 12, y: 6)
    }

    private var slotLip: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x0A0B0C), Color(hex: 0x1D1F22)],
                           startPoint: .top, endPoint: .bottom)
            Rectangle()
                .fill(.white.opacity(0.16))
                .frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 13)
        .overlay(alignment: .top) {
            Rectangle().fill(.black.opacity(0.8)).frame(height: 2)
        }
    }

    // MARK: 出片区

    private func emerging(_ t: ThemeTokens, areaHeight: CGFloat) -> some View {
        GeometryReader { geo in
            let maxW = geo.size.width - 18
            let aspect = image.size.height / max(image.size.width, 1)
            let naturalH = maxW * aspect
            let printH = min(naturalH, areaHeight - 6)
            let printW = printH / max(aspect, 0.01)

            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(hex: 0x050607), Color(hex: 0x0B0D0F)],
                               startPoint: .top, endPoint: .bottom)

                // 相纸：顶端贴着槽口，随拉动向下展开
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: printW, height: printH)
                    .offset(y: -(1 - pull) * printH)
                    .shadow(color: .black.opacity(0.7), radius: 10, y: 4)

                // 槽口投影
                LinearGradient(colors: [.black.opacity(0.65), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 16)
                    .allowsHitTesting(false)

                // 往下流动的箭头：不用文字也能看懂"往下拉"
                if pull < 0.55 {
                    PullHint(tokens: t)
                        // 箭头跟着相纸的可抓边一起走
                        .padding(.top, pull * printH + 22)
                        .opacity(max(0, 1 - pull * 2.2))
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if dragBase == nil { dragBase = pull }
                        let base = dragBase ?? pull
                        let next = min(max(base + value.translation.height / max(printH, 1), 0), 1)
                        pull = next
                        let bucket = Int(next * 4)
                        if bucket != lastTick {
                            lastTick = bucket
                            Haptics.impact(.light)
                        }
                    }
                    .onEnded { _ in
                        dragBase = nil
                        // 拉过三成就吸附到底，否则退回到"露一条边"
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                            pull = pull > 0.3 ? 1 : 0.12
                        }
                        Haptics.impact(.medium)
                    }
            )
        }
    }

    private func footer(_ t: ThemeTokens) -> some View {
        VStack(spacing: 8) {
            if done {
                // 出片之后还能换调色：从「只过胶片的底」重渲染
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        LookChip(title: "原色", color: .white.opacity(0.25),
                                 selected: manager.selectedLook == nil, tokens: t) {
                            manager.regradeCaptured(to: nil)
                            Haptics.impact(.light)
                        }
                        ForEach(FilmPreset.looks) { preset in
                            LookChip(title: preset.label, color: canisterColor(preset),
                                     selected: manager.selectedLook == preset, tokens: t) {
                                manager.regradeCaptured(to: preset)
                                Haptics.impact(.light)
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
                }
                .transition(.opacity)
            }

            ZStack {
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(t.accent.opacity(0.85)))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(height: 34)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.25), value: done)
        .accessibilityLabel(done ? "已出片，可换调色，轻触关闭" : "下拉相纸取片")
    }
}

/// 从槽口往下流动的箭头：只靠动效提示"往下拉"
struct PullHint: View {
    let tokens: ThemeTokens
    @State private var phase = false

    var body: some View {
        VStack(spacing: -2) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: "chevron.compact.down")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(tokens.accent)
                    .opacity(phase ? 0.95 : 0.18)
                    .animation(
                        .easeInOut(duration: 0.85)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.13),
                        value: phase
                    )
            }
        }
        .shadow(color: tokens.accent.opacity(0.5), radius: 6)
        .onAppear { phase = true }
    }
}

/// 系统分享面板（保存/分享当前成片）
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
