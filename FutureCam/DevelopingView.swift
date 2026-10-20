import SwiftUI
import UIKit

/// 撕拉片：拍完不是「等显影」，而是一张相纸从仓里被拉出来。
/// 手指往下拉 → 相纸从槽口滑出；拉到底出片完成，轻触关闭。
struct DevelopingPhotoView: View {
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
        _pull = State(initialValue: initialPull)
    }

    private var done: Bool { pull >= 0.97 }

    var body: some View {
        let t = ThemeStore.current

        ZStack {
            LeatherPanel().ignoresSafeArea()
            Color.black.opacity(0.62).ignoresSafeArea()
                .onTapGesture { if done { onDismiss() } }

            VStack(spacing: 0) {
                pack
                slotLip
                emerging(t)
                footer(t)
            }
            .padding(.horizontal, 22)
        }
    }

    // MARK: 相纸仓

    private var pack: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x2B2E31), Color(hex: 0x121416)],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 3) {
                Text("PEEL-APART")
                    .font(.custom("Futura-Medium", size: 11))
                    .tracking(3.2)
                    .foregroundColor(.white.opacity(0.4))
                Text("INSTANT FILM PACK")
                    .font(.system(size: 6, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.22))
            }
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

    private func emerging(_ t: ThemeTokens) -> some View {
        GeometryReader { geo in
            let travel = max(geo.size.height - 6, 1)

            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(hex: 0x050607), Color(hex: 0x0B0D0F)],
                               startPoint: .top, endPoint: .bottom)

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width - 18)
                    .offset(y: (1 - pull) * travel)
                    .shadow(color: .black.opacity(0.7), radius: 10, y: 4)

                // 槽口投影
                LinearGradient(colors: [.black.opacity(0.6), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 26)
                    .allowsHitTesting(false)

                if !done {
                    VStack {
                        Spacer()
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                            Text("下拉取片")
                                .font(t.monoFont(10, .medium))
                        }
                        .foregroundColor(.white.opacity(0.65))
                        .padding(.bottom, 12)
                        .opacity(max(0, 1 - pull * 1.6))
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.45)) { pull = 1 }
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if dragBase == nil { dragBase = pull }
                        let base = dragBase ?? pull
                        let next = min(max(base + value.translation.height / travel, 0), 1)
                        pull = next
                        let bucket = Int(next * 4)
                        if bucket != lastTick {
                            lastTick = bucket
                            Haptics.impact(.light)
                        }
                    }
                    .onEnded { _ in
                        dragBase = nil
                        // 拉过一半就吸附到底，否则退回仓里
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                            pull = pull > 0.5 ? 1 : 0
                        }
                        Haptics.impact(.medium)
                    }
            )
        }
    }

    private func footer(_ t: ThemeTokens) -> some View {
        HStack(spacing: 6) {
            if done {
                LEDDot(color: t.glow, size: 5)
                Text("已出片 · 轻触关闭")
                    .font(t.monoFont(11, .medium))
                    .foregroundColor(.white.opacity(0.75))
            } else {
                Text("按住相纸往下拉")
                    .font(t.monoFont(10, .regular))
                    .foregroundColor(.white.opacity(0.45))
            }
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
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
