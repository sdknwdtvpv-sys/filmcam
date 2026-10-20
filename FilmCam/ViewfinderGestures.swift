import SwiftUI
import UIKit

/// 取景器手势层：单指点击 = 对焦，长按 = 锁定 AE/AF，捏合 = 变焦。
///
/// 为什么用 UIKit 手势而不是 SwiftUI 手势：
/// `onTapGesture` 拿不到点击坐标，`onLongPressGesture` 同样没有位置，
/// 而 `DragGesture(minimumDistance: 0)` 又会和捏合打架。这里用三个独立的
/// UIGestureRecognizer 统一收口，位置和状态都准确。
struct ViewfinderGestureLayer: UIViewRepresentable {

    var onTap: (CGPoint, CGSize) -> Void
    var onLongPress: (CGPoint, CGSize) -> Void
    var onPinchBegan: () -> Void
    var onPinchChanged: (CGFloat) -> Void
    var onPinchEnded: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        let longPress = UILongPressGestureRecognizer(target: context.coordinator,
                                                     action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        let pinch = UIPinchGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handlePinch(_:)))

        // 长按优先于点击：松手时不再触发一次对焦
        tap.require(toFail: longPress)
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(longPress)
        view.addGestureRecognizer(pinch)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onLongPress = onLongPress
        context.coordinator.onPinchBegan = onPinchBegan
        context.coordinator.onPinchChanged = onPinchChanged
        context.coordinator.onPinchEnded = onPinchEnded
    }

    @MainActor
    final class Coordinator {
        var onTap: ((CGPoint, CGSize) -> Void)?
        var onLongPress: ((CGPoint, CGSize) -> Void)?
        var onPinchBegan: (() -> Void)?
        var onPinchChanged: ((CGFloat) -> Void)?
        var onPinchEnded: (() -> Void)?

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            onTap?(gesture.location(in: view), view.bounds.size)
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let view = gesture.view else { return }
            onLongPress?(gesture.location(in: view), view.bounds.size)
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                onPinchBegan?()
            case .changed:
                onPinchChanged?(gesture.scale)
            case .ended, .cancelled, .failed:
                onPinchEnded?()
            default:
                break
            }
        }
    }
}

/// 轻触反馈（对焦/锁定用；系统未开触感时静默失效）
enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        // 手势回调由 UIKit 在主线程触发，这里可以安全断言
        MainActor.assumeIsolated {
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            generator.impactOccurred()
        }
    }
}

/// 对焦/锁定指示框：点击后从大缩到正常并淡出；锁定时常驻并显示 AE/AF 锁定
struct FocusReticle: View {
    let locked: Bool

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4)
                .stroke(locked ? CameraTheme.amber : CameraTheme.amber.opacity(0.85),
                        style: StrokeStyle(lineWidth: 1.5, dash: locked ? [] : [6, 4]))
                .frame(width: 74, height: 74)
                .shadow(color: CameraTheme.amber.opacity(0.5), radius: 4)

            if locked {
                Text("AE/AF 锁定")
                    .font(CameraTheme.mono(10, weight: .semibold))
                    .foregroundColor(CameraTheme.bgDeep)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(CameraTheme.amber)
                    .clipShape(Capsule())
            }
        }
        .scaleEffect(appeared ? 1 : 1.45)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: appeared)
        .allowsHitTesting(false)
        .onAppear { appeared = true }
    }
}

/// 变焦倍率角标（只在非 1× 时出现）
struct ZoomBadge: View {
    let factor: CGFloat

    var body: some View {
        Text(String(format: "%.1f×", factor))
            .font(CameraTheme.mono(11, weight: .semibold))
            .foregroundColor(CameraTheme.bgDeep)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(CameraTheme.amber.opacity(0.92))
            .clipShape(Capsule())
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}

/// 前后摄切换按钮（底部右侧，与左侧相册缩略图对称）
struct FlipCameraButton: View {
    @EnvironmentObject var manager: CameraManager

    var body: some View {
        Button { manager.switchCamera() } label: {
            ZStack {
                Circle().stroke(CameraTheme.hairline, lineWidth: 1)
                    .frame(width: 46, height: 46)
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(manager.isRecording ? CameraTheme.inkDim.opacity(0.4) : CameraTheme.ink)
                    .rotationEffect(.degrees(manager.isFrontCamera ? 180 : 0))
                    .animation(.easeInOut(duration: 0.28), value: manager.isFrontCamera)
            }
            .frame(width: 46, height: 46)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(manager.isRecording)
        .accessibilityLabel(manager.isFrontCamera ? "切换到后置摄像头" : "切换到前置摄像头")
    }
}
