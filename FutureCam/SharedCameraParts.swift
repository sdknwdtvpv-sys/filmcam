import SwiftUI

/// 取景画面 + 手势 + 对焦框 + 变焦角标。
/// 三个主题只在「外面套什么边框」上不同，画面层共用这一份。
struct PreviewSurface: View {
    @EnvironmentObject var manager: CameraManager

    /// 是否在上下边加压暗（亮色主题的取景窗通常自带边框，不需要）
    var showsScrim: Bool = true

    @State private var focusPoint: CGPoint?
    @State private var focusLocked = false
    @State private var focusToken = UUID()
    @State private var zoomBase: CGFloat = 1

    var body: some View {
        let t = ThemeStore.current

        ZStack {
            PreviewView(frames: manager.previewFrames, initialImage: manager.lastPreviewFrame)
                .background(Color.black)

            if showsScrim {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.black.opacity(0.38), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 76)
                    Spacer(minLength: 0)
                    LinearGradient(colors: [.clear, .black.opacity(0.32)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 66)
                }
                .allowsHitTesting(false)
            }

            if manager.showGrid { GridOverlay() }
            if manager.showLevel { LevelIndicator() }

            if manager.authorizationStatus == .authorized && !manager.hasPreview {
                VStack(spacing: 10) {
                    ProgressView().tint(t.accent)
                    Text(manager.previewStalled ? "相机预览不可用" : "正在启动相机…")
                        .font(t.labelFont(12, .medium))
                        .foregroundColor(.white.opacity(0.75))
                }
            }

            // 手势层永远在最上面，装饰元素挡不住对焦 / 变焦
            ViewfinderGestureLayer(
                onTap: { point, size in handleFocus(point, size, lock: false) },
                onLongPress: { point, size in handleFocus(point, size, lock: true) },
                onPinchBegan: { zoomBase = manager.zoomFactor },
                onPinchChanged: { scale in manager.applyZoom(base: zoomBase, scale: scale) },
                onPinchEnded: { manager.endZoom() }
            )

            if let focusPoint {
                FocusReticle(locked: focusLocked)
                    .position(focusPoint)
                    .task(id: focusToken) {
                        guard !focusLocked else { return }
                        try? await Task.sleep(nanoseconds: 900_000_000)
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeOut(duration: 0.25)) { self.focusPoint = nil }
                    }
            }

            if manager.zoomFactor > 1.02 {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        ZoomBadge(factor: manager.zoomFactor)
                            .padding(.trailing, 14).padding(.bottom, 14)
                    }
                }
            }

            if manager.isRecording {
                VStack {
                    HStack(spacing: 5) {
                        Circle().fill(t.recRed).frame(width: 7, height: 7)
                        Text("REC")
                            .font(t.monoFont(10, .bold))
                            .foregroundColor(t.recRed)
                    }
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.black.opacity(0.55))
                    .clipShape(Capsule())
                    .padding(.top, 10)
                    Spacer()
                }
            }
        }
        .clipped()
    }

    private func handleFocus(_ point: CGPoint, _ size: CGSize, lock: Bool) {
        manager.focus(at: point, in: size, lock: lock)
        focusPoint = point
        focusLocked = lock
        focusToken = UUID()
        Haptics.impact(lock ? .medium : .light)
    }
}

// MARK: - 三个主题共用的读数格式化

func shutterLabel(_ v: Double) -> String { CameraMath.shutterLabel(v) }

func evLabel(_ v: Double) -> String { CameraMath.evLabel(v) }

/// 参数短标题（戳记 / 读数字段上用）
func paramTitle(_ key: ParamKey) -> String {
    switch key {
    case .iso: return "ISO"
    case .shutter: return "T"
    case .bias: return "EV"
    case .temperature: return "K"
    case .tint: return "TINT"
    }
}

/// 参数读数（不含标题）
@MainActor
func paramValue(_ key: ParamKey, _ manager: CameraManager) -> String {
    switch key {
    case .iso: return "\(Int(manager.iso))"
    case .shutter: return shutterLabel(manager.shutterSeconds)
    case .bias: return evLabel(manager.bias)
    case .temperature: return "\(Int(manager.temperature))"
    case .tint: return "\(manager.tint >= 0 ? "+" : "")\(Int(manager.tint))"
    }
}

/// 当前参数分组下要显示的 2–3 个参数
@MainActor
/// 读数条一次显示全部五个参数：曝光三项 + 白平衡两项并排，不再分组切换
func visibleParams(_ manager: CameraManager) -> [ParamKey] {
    [.iso, .shutter, .bias, .temperature, .tint]
}

/// 快门按钮上的动作词
@MainActor
func shutterVerb(_ manager: CameraManager) -> String {
    switch manager.mode {
    case .video: return manager.isRecording ? "停止录制" : "开始录制"
    case .doubleExposure: return manager.doubleExposureStep == 1 ? "第二张" : "第一张"
    case .photo: return "按下快门"
    }
}

/// 快门按钮上的英文小注（版面节奏用）
@MainActor
func shutterHint(_ manager: CameraManager) -> String {
    switch manager.mode {
    case .video: return manager.isRecording ? "STOP · REC" : "RECORD · 1080P"
    case .doubleExposure: return manager.doubleExposureStep == 1 ? "SECOND EXPOSURE" : "FIRST EXPOSURE"
    case .photo: return "SHUTTER"
    }
}
