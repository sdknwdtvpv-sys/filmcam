import SwiftUI
import UIKit

/// 显影：拍完不是「等」，而是一张相纸在显影盘里慢慢浮上来。
/// 画面从暗而灰的潜影逐渐显出色密度，显影完成后才能关闭，也可以这时换调色。
struct DevelopingPhotoView: View {
    @EnvironmentObject var manager: CameraManager
    let image: UIImage
    let onDismiss: () -> Void
    /// 调试用：>= 0.97 表示直接给已显影的成品（方便截图）
    var initialPull: Double = 0

    @State private var density: Double
    @State private var done: Bool
    @State private var started = false

    private let developDuration: Double = 1.7

    init(image: UIImage, initialPull: Double = 0, onDismiss: @escaping () -> Void) {
        self.image = image
        self.onDismiss = onDismiss
        self.initialPull = initialPull
        let preDeveloped = initialPull >= 0.97
        _density = State(initialValue: preDeveloped ? 1 : 0)
        _done = State(initialValue: preDeveloped)
    }

    var body: some View {
        let t = ThemeStore.current

        ZStack {
            LeatherPanel().ignoresSafeArea()
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(spacing: 14) {
                header(t)
                Spacer(minLength: 0)
                plate(t)
                Spacer(minLength: 0)
                caption(t)
                if done {
                    lookStrip(t)
                }
                hint(t)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 22)
        }
        .contentShape(Rectangle())
        .onTapGesture { if done { onDismiss() } }
        .task {
            guard !done, !started else { return }
            started = true
            withAnimation(.easeOut(duration: developDuration)) { density = 1 }
            try? await Task.sleep(nanoseconds: UInt64(developDuration * 1_000_000_000) + 120_000_000)
            withAnimation(.easeOut(duration: 0.25)) { done = true }
            Haptics.impact(.rigid)
        }
    }

    // MARK: 顶部：显影状态

    private func header(_ t: ThemeTokens) -> some View {
        VStack(spacing: 7) {
            HStack(spacing: 6) {
                LEDDot(color: done ? t.glow : t.accent, size: 4, dimmed: false)
                Silkscreen(text: done ? "FIXED" : "DEVELOPING",
                           color: .white.opacity(0.62), size: 6.5, tracking: 2.4)
                Spacer()
                Silkscreen(text: manager.selectedPreset.label,
                           color: .white.opacity(0.4), size: 6.5, tracking: 1.8)
            }

            // 显影进度：一条细发丝线
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(.white.opacity(0.12))
                    Rectangle().fill(t.accent.opacity(0.85))
                        .frame(width: geo.size.width * density)
                }
            }
            .frame(height: 1)
        }
    }

    // MARK: 相纸

    private func plate(_ t: ThemeTokens) -> some View {
        GeometryReader { geo in
            let aspect = max(0.6, image.size.width / max(image.size.height, 1))
            let maxW = geo.size.width
            let maxH = geo.size.height
            let w = min(maxW, maxH * aspect)
            let h = w / aspect

            ZStack {
                // 相纸底：显影完成前是一张灰白的片基
                Rectangle()
                    .fill(.white.opacity(0.06))

                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)
                    .clipped()
                    // 潜影 → 显影：暗、灰、低对比，逐渐恢复
                    .brightness(-0.24 * (1 - density))
                    .saturation(0.25 + 0.75 * density)
                    .contrast(0.72 + 0.28 * density)
                    .opacity(0.35 + 0.65 * density)

                // 取景角标：显影完成后描绘框角
                CornerMarks(color: .white.opacity(0.5 * density), length: 14)
                    .frame(width: w, height: h)

                Rectangle()
                    .strokeBorder(.white.opacity(0.10 + 0.06 * density), lineWidth: 0.5)
                    .frame(width: w, height: h)
            }
            .frame(width: maxW, height: maxH)
        }
    }

    // MARK: 底部说明

    private func caption(_ t: ThemeTokens) -> some View {
        let roll = manager.roll
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd HH:mm"

        return HStack(spacing: 8) {
            Silkscreen(text: "VOL.\(String(format: "%02d", roll.number)) · \(roll.countText)",
                       color: .white.opacity(0.4), size: 6, tracking: 1.6)
            Rectangle().fill(.white.opacity(0.14)).frame(width: 1, height: 8)
            Silkscreen(text: formatter.string(from: Date()),
                       color: .white.opacity(0.4), size: 6, tracking: 1.6)
            Spacer(minLength: 0)
        }
        .opacity(done ? 1 : 0.4)
    }

    private func lookStrip(_ t: ThemeTokens) -> some View {
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
            .padding(.vertical, 2)
        }
        .frame(height: 34)
        .transition(.opacity)
    }

    private func hint(_ t: ThemeTokens) -> some View {
        Button {
            if done { onDismiss() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: done ? "checkmark" : "hourglass")
                    .font(.system(size: 10, weight: .bold))
                Text(done ? "轻触关闭" : "显影中…")
                    .font(t.monoFont(10, .medium))
            }
            .foregroundColor(done ? .white.opacity(0.75) : .white.opacity(0.35))
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(Capsule().fill(.white.opacity(done ? 0.12 : 0.05)))
        }
        .buttonStyle(.plain)
        .disabled(!done)
        .animation(.easeOut(duration: 0.25), value: done)
    }
}

/// 四角取景角标（只画角，不画整框）
struct CornerMarks: View {
    var color: Color
    var length: CGFloat = 14
    var lineWidth: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            Path { p in
                p.move(to: CGPoint(x: 0, y: length));      p.addLine(to: .zero)
                p.addLine(to: CGPoint(x: length, y: 0))

                p.move(to: CGPoint(x: w - length, y: 0));  p.addLine(to: CGPoint(x: w, y: 0))
                p.addLine(to: CGPoint(x: w, y: length))

                p.move(to: CGPoint(x: 0, y: h - length));  p.addLine(to: CGPoint(x: 0, y: h))
                p.addLine(to: CGPoint(x: length, y: h))

                p.move(to: CGPoint(x: w - length, y: h));  p.addLine(to: CGPoint(x: w, y: h))
                p.addLine(to: CGPoint(x: w, y: h - length))
            }
            .stroke(color, lineWidth: lineWidth)
        }
    }
}

/// 系统分享面板（相册里分享成片用）
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
