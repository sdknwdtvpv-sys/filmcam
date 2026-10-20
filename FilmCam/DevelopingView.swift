import SwiftUI
import UIKit
import CoreMotion
import AVKit

final class DevelopingModel: ObservableObject, @unchecked Sendable {
    @Published var progress: Double = 0
    @Published var done = false
    @Published var useMotion = false

    private let motion = CMMotionManager()
    private let motionQueue = OperationQueue()
    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            DispatchQueue.main.async {
                if self.progress < 1 { self.progress = min(1, self.progress + 0.012) }
                if self.progress >= 1 { self.finish() }
            }
        }
        guard motion.isAccelerometerAvailable else { return }
        useMotion = true
        motion.accelerometerUpdateInterval = 0.05
        motion.startAccelerometerUpdates(to: motionQueue) { [weak self] data, _ in
            guard let self, let data else { return }
            let a = data.acceleration
            let mag = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
            let energy = max(0, mag - 1.3)
            if energy > 0 {
                DispatchQueue.main.async {
                    if self.progress < 1 {
                        self.progress = min(1, self.progress + Double(energy) * 0.18)
                        if self.progress >= 1 { self.finish() }
                    }
                }
            }
        }
    }

    func finish() {
        timer?.invalidate(); timer = nil
        if motion.isAccelerometerActive { motion.stopAccelerometerUpdates() }
        withAnimation(.easeInOut(duration: 0.4)) { done = true; progress = 1 }
    }

    deinit {
        timer?.invalidate()
        if motion.isAccelerometerActive { motion.stopAccelerometerUpdates() }
    }
}

struct DevelopingPhotoView: View {
    let image: UIImage
    let onDismiss: () -> Void
    @StateObject private var model = DevelopingModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 封条滑出比例
    private var slide: Double { reduceMotion ? 1 : model.progress }

    var body: some View {
        let t = ThemeStore.current

        ZStack {
            LeatherPanel().ignoresSafeArea()
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { if model.done { onDismiss() } }

            VStack(spacing: 16) {
                // 相纸托盘 + 压在上面的封条
                ZStack(alignment: .top) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .blur(radius: model.done ? 0 : (1 - model.progress) * 9)
                        .opacity(0.35 + 0.65 * model.progress)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .shadow(color: .black.opacity(0.6), radius: 22, y: 12)

                    GeometryReader { geo in
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            ZStack(alignment: .top) {
                                LinearGradient(colors: [Color(hex: 0x2A2C2E), Color(hex: 0x111213)],
                                               startPoint: .top, endPoint: .bottom)
                                VStack(spacing: 6) {
                                    HStack(spacing: 6) {
                                        ForEach(0..<12, id: \.self) { _ in
                                            Circle().fill(.white.opacity(0.07))
                                                .frame(width: 2.5, height: 2.5)
                                        }
                                    }
                                    Text("PULL TO DEVELOP")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .tracking(2.4)
                                        .foregroundColor(.white.opacity(0.4))
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white.opacity(0.3))
                                }
                                .padding(.top, 14)
                            }
                            .frame(height: geo.size.height * 0.62)
                            .overlay(alignment: .bottom) {
                                TornEdge()
                                    .fill(Color(hex: 0x111213))
                                    .frame(height: 6)
                                    .offset(y: 5)
                            }
                            .offset(y: geo.size.height * 0.62 * slide)
                            .opacity(model.done ? 0 : 1)
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                        .clipped()
                    }
                    .allowsHitTesting(false)
                }
                .padding(.horizontal, 18)

                if model.done {
                    HStack(spacing: 6) {
                        LEDDot(color: t.glow, size: 5)
                        Text("已显影 · 轻触关闭")
                            .font(t.monoFont(11, .medium))
                            .foregroundColor(.white.opacity(0.75))
                    }
                } else {
                    VStack(spacing: 7) {
                        Text(model.useMotion
                             ? "摇一摇 · 显影 \(Int(model.progress * 100))%"
                             : "显影中… \(Int(model.progress * 100))%")
                            .font(t.monoFont(11, .medium))
                            .foregroundColor(.white.opacity(0.7))
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.12)).frame(width: 150, height: 2)
                            Capsule().fill(t.accent)
                                .frame(width: max(2, 150 * model.progress), height: 2)
                        }
                    }
                }
            }
            .padding(.vertical, 24)
        }
        .onAppear { model.start() }
    }
}

/// 撕裂边：一排锯齿

struct TornEdge: Shape {
    var teeth: Int = 22
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        let step = rect.width / CGFloat(teeth)
        var x = rect.minX
        var up = false
        while x < rect.maxX {
            path.addLine(to: CGPoint(x: x + step / 2, y: up ? rect.maxY : rect.minY))
            x += step / 2
            up.toggle()
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - 预览渲染

/// 订阅 Combine 帧流直接改 UIImageView.image，绕过 SwiftUI 的状态观察 ——
/// 避免每帧重算整棵视图树（真机流畅度的关键）。
