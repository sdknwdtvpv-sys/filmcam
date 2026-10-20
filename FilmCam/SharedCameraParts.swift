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

/// 展开的参数滑杆（点参数读数后出现）。
/// 滑块本体用 SwiftUI 原生 Slider，外观交给 accentColor，三个主题自然跟随。
struct ParamTuningPanel: View {
    @EnvironmentObject var manager: CameraManager

    var body: some View {
        let t = ThemeStore.current

        Group {
            if let key = manager.activeParam {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(key.sliderTitle.uppercased())
                            .font(t.labelFont(10, .semibold))
                            .tracking(1.2)
                            .foregroundColor(t.inkDim)
                        if isAuto(key) {
                            Text("自动")
                                .font(t.labelFont(9, .semibold))
                                .foregroundColor(t.accent)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .overlay(Capsule().stroke(t.accent, lineWidth: 1))
                        }
                        Spacer()
                        Text(valueText(key))
                            .font(t.displayFont(17, .regular))
                            .foregroundColor(t.ink)
                    }
                    slider(for: key, tokens: t)
                }
                .padding(.horizontal, t.inset)
                .padding(.vertical, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func isAuto(_ key: ParamKey) -> Bool {
        (key == .iso || key == .shutter || key == .bias) ? manager.autoExposure : manager.autoWB
    }

    @ViewBuilder private func slider(for key: ParamKey, tokens t: ThemeTokens) -> some View {
        switch key {
        case .iso:
            Slider(value: binding(\.iso, apply: manager.applyExposure),
                   in: 50...1600, step: 50).tint(t.accent)
        case .shutter:
            Slider(value: binding(\.shutterSeconds, apply: manager.applyExposure),
                   in: 0.00025...0.25).tint(t.accent)
        case .bias:
            Slider(value: binding(\.bias, apply: manager.applyExposure),
                   in: -2...2, step: 0.1).tint(t.accent)
        case .temperature:
            Slider(value: binding(\.temperature, apply: manager.applyWhiteBalance),
                   in: 3000...8000, step: 100).tint(t.accent)
        case .tint:
            Slider(value: binding(\.tint, apply: manager.applyWhiteBalance),
                   in: -150...150, step: 10).tint(t.accent)
        }
    }

    /// 拖动即写回设备：值变化时顺手把对应自动模式关掉
    private func binding(_ keyPath: ReferenceWritableKeyPath<CameraManager, Double>,
                         apply: @escaping () -> Void) -> Binding<Double> {
        Binding(
            get: { manager[keyPath: keyPath] },
            set: { newValue in
                manager[keyPath: keyPath] = newValue
                apply()
            }
        )
    }

    private func valueText(_ key: ParamKey) -> String {
        switch key {
        case .iso: return "\(Int(manager.iso))"
        case .shutter: return shutterLabel(manager.shutterSeconds)
        case .bias: return String(format: "%+.1f", manager.bias)
        case .temperature: return "\(Int(manager.temperature))K"
        case .tint: return "\(Int(manager.tint))"
        }
    }
}

// MARK: - 三个主题共用的读数格式化

func shutterLabel(_ v: Double) -> String {
    if v >= 1 { return String(format: "%.1fs", v) }
    return "1/\(Int(round(1 / v)))"
}

func evLabel(_ v: Double) -> String {
    String(format: "%+.1f", v)
}

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
func visibleParams(_ manager: CameraManager) -> [ParamKey] {
    manager.paramMode == .exposure ? [.iso, .shutter, .bias] : [.temperature, .tint]
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
