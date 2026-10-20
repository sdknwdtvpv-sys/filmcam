import SwiftUI
import CoreMotion
import Combine

enum CameraMode: String, CaseIterable, Identifiable {
    case photo
    case doubleExposure
    case video
    var id: String { rawValue }
    var label: String {
        switch self {
        case .photo: return "照片"
        case .doubleExposure: return "双曝"
        case .video: return "视频"
        }
    }
}

/// 工具停靠栏的符号（文件级，供 ToolDock 与 ToolIcon 共用）
enum ToolSymbol: String, CaseIterable, Identifiable {
    case exposure, whiteBalance, film, grid, settings
    var id: String { rawValue }
}

struct CameraView: View {
    @EnvironmentObject var manager: CameraManager
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {            CameraTheme.bgDeep.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── 顶部：品牌铭牌 + 时钟 / 可用存储 ──
                TopPlate()
                Rectangle().fill(CameraTheme.hairline).frame(height: 1)
                    .padding(.horizontal, 20)

                // ── 模式 Tab + 右侧格式徽标 ──
                ModeTabs()

                // ── 取景器 ──
                Viewfinder()

                // ── 参数药丸（曝光组 或 白平衡组）──
                ParamPills()

                // ── 展开的滑杆（点药丸才出现）──
                ParamSliderRow()

                // ── 工具停靠栏 ──
                ToolDock()

                // ── 底部：金环缩略图 + 琥珀快门 ──
                BottomBar()
                    .padding(.bottom, 26)
            }
            .frame(maxWidth: .infinity)

            // 权限引导（可操作，绝不空转/死锁）
            if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
                PermissionGate(
                    title: "相机权限已关闭",
                    message: "FilmCam 需要相机权限才能拍摄。点下方按钮前往系统设置开启相机权限，然后返回本页即可。",
                    buttonTitle: "去系统设置开启",
                    action: { manager.openSystemSettings() })
            } else if manager.authorizationStatus == .notDetermined {
                PermissionGate(
                    title: "需要相机权限",
                    message: "FilmCam 需要访问相机来拍摄复古胶片照片。",
                    buttonTitle: "授权并开启",
                    action: { manager.requestAccessAndConfigure() })
            }

            // 成片：拍立得摇一摇显影
            if let captured = manager.capturedImage {
                DevelopingPhotoView(image: captured) { manager.clearCaptured() }
            }

            // 保存提示
            if manager.showVideoSaved { ToastVideoSaved() }
            if manager.videoSaveBlocked { ToastVideoBlocked() }
            if manager.photoSaveBlocked { ToastPhotoBlocked() }
            if manager.showDoubleExposureFirst { ToastDoubleExposureFirst() }

            // 弹层
            if manager.showFilmSheet { FilmSheet() }
            if manager.showSettingsSheet { SettingsSheet() }
            if manager.showAlbum { AlbumView() }
        }
        .sheet(isPresented: $manager.showVideoShare) {
            if let url = manager.recordedVideoURL {
                ShareSheet(items: [url])
            }
        }
        .animation(.easeInOut(duration: 0.22), value: manager.showFilmSheet)
        .animation(.easeInOut(duration: 0.22), value: manager.showSettingsSheet)
        .animation(.easeInOut(duration: 0.18), value: manager.activeParam)
        .onAppear {
            manager.requestAccessAndConfigure()
            #if DEBUG
            DebugHarness.applyLaunchState(manager)
            if DebugHarness.shouldStubPreview { manager.enableStubPreview() }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                manager.refreshAuthorization()
            case .background:
                // 进后台主动停会话；回前台由 refreshAuthorization 恢复（否则黑屏）
                manager.pauseCamera()
            default:
                break
            }
        }
    }
}

// MARK: - 顶部铭牌

struct TopPlate: View {
    @EnvironmentObject var manager: CameraManager
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("FILMCAM")
                .font(CameraTheme.mono(15, weight: .bold))
                .foregroundColor(CameraTheme.amber)
                .tracking(2)
                .shadow(color: CameraTheme.amber.opacity(0.5), radius: 6)
            Spacer()
            Text(now, style: .time)
                .font(CameraTheme.mono(11, weight: .medium))
                .foregroundColor(CameraTheme.inkDim)
            Text("·")
                .font(CameraTheme.mono(11)).foregroundColor(CameraTheme.inkDim)
            Text(manager.freeStorageText)
                .font(CameraTheme.mono(11, weight: .medium))
                .foregroundColor(CameraTheme.inkDim)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .onReceive(timer) { now = $0 }
    }
}

// MARK: - 模式 Tab

struct ModeTabs: View {
    @EnvironmentObject var manager: CameraManager

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Spacer(minLength: 0)
            HStack(spacing: 20) {
                ForEach(CameraMode.allCases) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { manager.mode = mode }
                    } label: {
                        Text(mode.label)
                            .font(CameraTheme.mono(13, weight: manager.mode == mode ? .semibold : .regular))
                            .foregroundColor(manager.mode == mode ? CameraTheme.amber : CameraTheme.inkDim)
                            .overlay(alignment: .bottom) {
                                if manager.mode == mode {
                                    Rectangle().fill(CameraTheme.amber).frame(height: 2)
                                        .offset(y: 6)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 8)
            Text("\(manager.selectedPreset.label) · 1080P")
                .font(CameraTheme.mono(11, weight: .medium))
                .foregroundColor(CameraTheme.inkDim)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}

// MARK: - 取景器

struct Viewfinder: View {
    @EnvironmentObject var manager: CameraManager

    // 对焦指示框状态
    @State private var focusPoint: CGPoint?
    @State private var focusLocked = false
    @State private var focusToken = UUID()
    // 捏合起始倍率
    @State private var zoomBase: CGFloat = 1

    private var modeTag: String {
        switch manager.mode {
        case .photo: return "实时预览"
        case .video: return "视频"
        case .doubleExposure:
            return manager.doubleExposureStep == 0 ? "双曝 1/2" : "双曝 2/2"
        }
    }

    var body: some View {
        ZStack {
            // 注意：不要给 PreviewView 加 .aspectRatio(contentMode: .fill)！
            // UIViewRepresentable 无固有宽高比，.fill 会让它按高度撑宽（约 1:1），
            // 把整条 VStack 撑得比屏幕更宽，导致顶部内容被裁掉。
            PreviewView(frames: manager.previewFrames)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CameraTheme.bgDeep)

            if manager.showGrid { GridOverlay() }
            if manager.showLevel { LevelIndicator() }

            RoundedRectangle(cornerRadius: 14)
                .stroke(CameraTheme.hairline, lineWidth: 1.5)
                .padding(10)
            ViewfinderBrackets().padding(10)

            // 左上：模式标签
            Text(modeTag)
                .font(CameraTheme.mono(11, weight: .medium))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .overlay(Capsule().stroke(CameraTheme.amber, lineWidth: 1))
                .foregroundColor(CameraTheme.amber)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 36).padding(.top, 34)

            // 右上：存储角标
            if manager.showStorage {
                Text("\(manager.freeStorageText) · \(manager.recordMinutesText)")
                    .font(CameraTheme.mono(11, weight: .medium))
                    .foregroundColor(CameraTheme.inkDim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, 36).padding(.top, 36)
            }

            // 顶部居中：REC
            if manager.isRecording {
                HStack(spacing: 6) {
                    Circle().fill(CameraTheme.recRed).frame(width: 9, height: 9)
                    Text("REC")
                        .font(CameraTheme.mono(12, weight: .bold))
                        .foregroundColor(CameraTheme.recRed)
                }
                .padding(6)
                .background(CameraTheme.bgDeep.opacity(0.55))
                .cornerRadius(6)
                .shadow(color: CameraTheme.recRed.opacity(0.6), radius: 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 34)
            }

            // 启动 / 不可用提示
            if manager.authorizationStatus == .authorized && !manager.hasPreview {
                VStack(spacing: 10) {
                    ProgressView().tint(CameraTheme.amber)
                    Text(manager.previewStalled ? "相机预览不可用" : "正在启动相机…")
                        .font(CameraTheme.mono(13, weight: .medium))
                        .foregroundColor(CameraTheme.inkDim)
                }
            }

            // 底部：日期
            if manager.hasPreview {
                VStack {
                    Spacer()
                    Text(AlbumDateFormat.day(Date()))
                        .font(CameraTheme.mono(12, weight: .medium))
                        .foregroundColor(CameraTheme.inkDim)
                        .padding(.bottom, 24)
                }
            }

            // ── 手势层放在最上层，保证任何装饰元素都挡不住对焦/变焦 ──
            ViewfinderGestureLayer(
                onTap: { point, size in handleFocus(point, size, lock: false) },
                onLongPress: { point, size in handleFocus(point, size, lock: true) },
                onPinchBegan: { zoomBase = manager.zoomFactor },
                onPinchChanged: { scale in manager.applyZoom(base: zoomBase, scale: scale) },
                onPinchEnded: { manager.endZoom() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 对焦 / 锁定指示框
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

            // 变焦倍率角标
            if manager.zoomFactor > 1.02 {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        ZoomBadge(factor: manager.zoomFactor)
                            .padding(.trailing, 26).padding(.bottom, 56)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 12)
    }

    private func handleFocus(_ point: CGPoint, _ size: CGSize, lock: Bool) {
        manager.focus(at: point, in: size, lock: lock)
        focusPoint = point
        focusLocked = lock
        focusToken = UUID()
        Haptics.impact(lock ? .medium : .light)
    }
}

struct GridOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: CGPoint(x: geo.size.width / 3, y: 0))
                p.addLine(to: CGPoint(x: geo.size.width / 3, y: geo.size.height))
                p.move(to: CGPoint(x: geo.size.width * 2 / 3, y: 0))
                p.addLine(to: CGPoint(x: geo.size.width * 2 / 3, y: geo.size.height))
                p.move(to: CGPoint(x: 0, y: geo.size.height / 3))
                p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 3))
                p.move(to: CGPoint(x: 0, y: geo.size.height * 2 / 3))
                p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height * 2 / 3))
            }
            .stroke(CameraTheme.amber.opacity(0.28), lineWidth: 0.75)
        }
        .padding(10)
    }
}

/// 水平仪：加速度算横滚角，中心琥珀线随倾斜偏移，接近水平时变亮
struct LevelIndicator: View {
    @StateObject private var meter = LevelMeter()

    var body: some View {
        GeometryReader { geo in
            let midY = geo.size.height / 2
            let maxOffset = geo.size.width / 2 - 24
            let offset = CGFloat(meter.roll) / 45.0 * maxOffset
            let level = abs(meter.roll) < 1.0
            ZStack {
                Rectangle().fill(CameraTheme.amber.opacity(0.18))
                    .frame(width: geo.size.width - 48, height: 1)
                Rectangle()
                    .fill(level ? CameraTheme.amber : CameraTheme.amber.opacity(0.55))
                    .frame(width: 60, height: 2)
                    .position(x: geo.size.width / 2 + offset, y: midY)
                    .shadow(color: level ? CameraTheme.amber.opacity(0.6) : .clear, radius: 6)
            }
            .overlay(alignment: .bottom) {
                Text(String(format: "%.1f°", meter.roll))
                    .font(CameraTheme.mono(11))
                    .foregroundColor(level ? CameraTheme.amber : CameraTheme.inkDim)
                    .padding(.bottom, 34)
            }
        }
        .padding(10)
        .onAppear { meter.start() }
        .onDisappear { meter.stop() }
    }
}

/// 横滚角数据源（仅水平仪可见时运行）
final class LevelMeter: ObservableObject, @unchecked Sendable {
    @Published var roll: Double = 0
    private let motion = CMMotionManager()
    private let queue = OperationQueue()

    func start() {
        guard motion.isAccelerometerAvailable, !motion.isAccelerometerActive else { return }
        motion.accelerometerUpdateInterval = 1.0 / 20.0
        motion.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
            guard let self, let data else { return }
            let a = data.acceleration
            let roll = atan2(a.x, sqrt(a.y * a.y + a.z * a.z)) * 180.0 / .pi
            DispatchQueue.main.async { self.roll = roll }
        }
    }

    func stop() { motion.stopAccelerometerUpdates() }
    deinit { motion.stopAccelerometerUpdates() }
}

// MARK: - 参数药丸

struct ParamPills: View {
    @EnvironmentObject var manager: CameraManager

    private var keys: [ParamKey] {
        manager.paramMode == .exposure ? [.iso, .shutter, .bias] : [.temperature, .tint]
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(keys) { key in
                Button { manager.toggleParam(key) } label: {
                    HStack(spacing: 6) {
                        ParamPillIcon(key: key, active: manager.activeParam == key)
                        Text(valueText(for: key))
                            .font(CameraTheme.mono(12, weight: manager.activeParam == key ? .semibold : .regular))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(manager.activeParam == key ? CameraTheme.amber : CameraTheme.bgElevated)
                    .foregroundColor(manager.activeParam == key ? CameraTheme.bgDeep : CameraTheme.inkDim)
                    .overlay(Capsule().stroke(CameraTheme.hairline, lineWidth: 1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private func valueText(for key: ParamKey) -> String {
        switch key {
        case .iso: return "ISO \(Int(manager.iso))"
        case .shutter: return shutterLabel(manager.shutterSeconds)
        case .bias: return String(format: "EV %+.1f", manager.bias)
        case .temperature: return "\(Int(manager.temperature))K"
        case .tint: return "\(Int(manager.tint))"
        }
    }
}

struct ParamPillIcon: View {
    let key: ParamKey
    let active: Bool
    private var tint: Color { active ? CameraTheme.bgDeep : CameraTheme.inkDim }

    var body: some View {
        Group {
            switch key {
            case .iso:
                HStack(spacing: 1.5) { bar(4, 7); bar(4, 11); bar(4, 15) }
            case .shutter:
                ZStack {
                    Circle().stroke(tint, lineWidth: 1.3).frame(width: 12, height: 12)
                    Circle().fill(tint).frame(width: 12, height: 12)
                        .mask(Rectangle().frame(width: 12, height: 6).offset(y: 3))
                }
            case .bias:
                ZStack {
                    Circle().stroke(tint, lineWidth: 1.3).frame(width: 12, height: 12)
                    Circle().fill(tint).frame(width: 12, height: 12)
                        .mask(HStack { Spacer(minLength: 0); Rectangle().frame(width: 6, height: 12) })
                }
            case .temperature:
                ZStack {
                    Circle().stroke(tint, lineWidth: 1.3).frame(width: 12, height: 12)
                    Circle().fill(tint).frame(width: 12, height: 12)
                        .mask(Rectangle().frame(width: 12, height: 6))
                }
            case .tint:
                ZStack {
                    Circle().stroke(tint, lineWidth: 1.3).frame(width: 12, height: 12)
                    Circle().fill(tint).frame(width: 5, height: 5)
                }
            }
        }
        .frame(width: 14, height: 14)
    }

    private func bar(_ w: CGFloat, _ h: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 1).fill(tint).frame(width: w, height: h)
    }
}

// MARK: - 展开滑杆

struct ParamSliderRow: View {
    @EnvironmentObject var manager: CameraManager

    var body: some View {
        Group {
            if let key = manager.activeParam {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(key.sliderTitle)
                            .font(CameraTheme.mono(11)).foregroundColor(CameraTheme.inkDim)
                        Spacer()
                        let isAuto = (key == .iso || key == .shutter || key == .bias)
                            ? manager.autoExposure : manager.autoWB
                        if isAuto {
                            Text("自动").font(CameraTheme.mono(11)).foregroundColor(CameraTheme.amber)
                        }
                        Text(valueText(key))
                            .font(CameraTheme.mono(12, weight: .semibold))
                            .foregroundColor(CameraTheme.amber)
                    }
                    slider(for: key)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    @ViewBuilder private func slider(for key: ParamKey) -> some View {
        switch key {
        case .iso:
            ParamSlider(title: "ISO", value: $manager.iso, range: 50...1600, step: 50,
                        onChanged: manager.applyExposure)
        case .shutter:
            ParamSlider(title: "快门", value: $manager.shutterSeconds,
                        range: 0.00025...0.25, step: nil,
                        onChanged: manager.applyExposure)
        case .bias:
            ParamSlider(title: "曝光补偿", value: $manager.bias, range: -2...2, step: 0.1,
                        onChanged: manager.applyExposure)
        case .temperature:
            ParamSlider(title: "色温", value: $manager.temperature, range: 3000...8000, step: 100,
                        onChanged: manager.applyWhiteBalance)
        case .tint:
            ParamSlider(title: "色调", value: $manager.tint, range: -150...150, step: 10,
                        onChanged: manager.applyWhiteBalance)
        }
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

struct ParamSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// nil = 连续滑杆。注意：**step 必须 > 0**，传 0 会让 SwiftUI 内部
    /// 按 (上界-下界)/step 计算步数时除零，直接 EXC_BREAKPOINT 崩溃
    /// （旧代码快门用的就是 step: 0，藏在折叠面板里没暴露，药丸一展开就崩）。
    let step: Double?
    let onChanged: () -> Void

    var body: some View {
        Group {
            if let step {
                Slider(value: $value, in: range, step: step)
            } else {
                Slider(value: $value, in: range)
            }
        }
        .accentColor(CameraTheme.amber)
        .onChange(of: value) { _, _ in onChanged() }
    }
}

func shutterLabel(_ v: Double) -> String {
    if v >= 1 { return String(format: "%.1fs", v) }
    return "1/\(Int(round(1 / v)))"
}

// MARK: - 工具停靠栏

struct ToolDock: View {
    @EnvironmentObject var manager: CameraManager

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(ToolSymbol.allCases) { symbol in
                    tool(symbol: symbol) { handle(symbol) }
                }
            }
            .padding(.horizontal, 20)
        }
        // 横向 ScrollView 必须收回屏幕宽度，否则撑宽父视图
        .frame(maxWidth: .infinity)
    }

    private func handle(_ symbol: ToolSymbol) {
        switch symbol {
        case .exposure: manager.setParamMode(.exposure)
        case .whiteBalance: manager.setParamMode(.whiteBalance)
        case .film:
            manager.showSettingsSheet = false
            manager.showFilmSheet = true
        case .grid: manager.showGrid.toggle()
        case .settings:
            manager.showFilmSheet = false
            manager.showSettingsSheet = true
        }
    }

    private func isActive(_ symbol: ToolSymbol) -> Bool {
        switch symbol {
        case .exposure: return manager.paramMode == .exposure
        case .whiteBalance: return manager.paramMode == .whiteBalance
        case .film: return manager.showFilmSheet
        case .grid: return manager.showGrid
        case .settings: return manager.showSettingsSheet
        }
    }

    private func label(for symbol: ToolSymbol) -> String {
        switch symbol {
        case .exposure: return "曝光"
        case .whiteBalance: return "白平衡"
        case .film: return "胶片"
        case .grid: return "网格"
        case .settings: return "设置"
        }
    }

    private func tool(symbol: ToolSymbol, action: @escaping () -> Void) -> some View {
        let active = isActive(symbol)
        return Button(action: action) {
            VStack(spacing: 5) {
                Circle()
                    .fill(active ? CameraTheme.amber.opacity(0.16) : Color.clear)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(active ? CameraTheme.amber : CameraTheme.hairline, lineWidth: 1))
                    .overlay(ToolIcon(symbol: symbol, active: active))
                Text(label(for: symbol))
                    .font(CameraTheme.mono(11))
                    .foregroundColor(active ? CameraTheme.amber : CameraTheme.inkDim)
            }
        }
        .buttonStyle(.plain)
    }
}

struct ToolIcon: View {
    let symbol: ToolSymbol
    let active: Bool
    private var stroke: Color { active ? CameraTheme.amber : CameraTheme.inkDim }

    var body: some View {
        Group {
            switch symbol {
            case .exposure:
                ZStack {
                    Circle().stroke(stroke, lineWidth: 1.3).frame(width: 15, height: 15)
                    Circle().fill(stroke).frame(width: 15, height: 15)
                        .mask(HStack { Spacer(minLength: 0); Rectangle().frame(width: 7.5, height: 15) })
                }
            case .whiteBalance:
                ZStack {
                    Circle().stroke(stroke, lineWidth: 1.3).frame(width: 15, height: 15)
                    Path { p in
                        p.move(to: CGPoint(x: 7.5, y: 0.5)); p.addLine(to: CGPoint(x: 7.5, y: 2.6))
                        p.move(to: CGPoint(x: 7.5, y: 12.4)); p.addLine(to: CGPoint(x: 7.5, y: 14.5))
                        p.move(to: CGPoint(x: 0.5, y: 7.5)); p.addLine(to: CGPoint(x: 2.6, y: 7.5))
                        p.move(to: CGPoint(x: 12.4, y: 7.5)); p.addLine(to: CGPoint(x: 14.5, y: 7.5))
                    }
                    .stroke(stroke, lineWidth: 1.2)
                }
            case .film:
                ZStack {
                    RoundedRectangle(cornerRadius: 2).stroke(stroke, lineWidth: 1.3)
                        .frame(width: 15, height: 13)
                    VStack(spacing: 2) {
                        HStack(spacing: 0) {
                            Circle().fill(stroke).frame(width: 2, height: 2)
                            Spacer(minLength: 0)
                            Circle().fill(stroke).frame(width: 2, height: 2)
                        }
                        .frame(width: 11)
                        Spacer(minLength: 0)
                        HStack(spacing: 0) {
                            Circle().fill(stroke).frame(width: 2, height: 2)
                            Spacer(minLength: 0)
                            Circle().fill(stroke).frame(width: 2, height: 2)
                        }
                        .frame(width: 11)
                    }
                    .frame(width: 15, height: 13)
                }
            case .grid:
                Path { p in
                    p.move(to: CGPoint(x: 5.3, y: 0.5)); p.addLine(to: CGPoint(x: 5.3, y: 14.5))
                    p.move(to: CGPoint(x: 9.7, y: 0.5)); p.addLine(to: CGPoint(x: 9.7, y: 14.5))
                    p.move(to: CGPoint(x: 0.5, y: 5.3)); p.addLine(to: CGPoint(x: 14.5, y: 5.3))
                    p.move(to: CGPoint(x: 0.5, y: 9.7)); p.addLine(to: CGPoint(x: 14.5, y: 9.7))
                }
                .stroke(stroke, lineWidth: 1.2)
            case .settings:
                ZStack {
                    Circle().stroke(stroke, lineWidth: 1.3).frame(width: 9, height: 9)
                    Circle().stroke(stroke, style: StrokeStyle(lineWidth: 1.1, dash: [2, 1.8]))
                        .frame(width: 15, height: 15)
                }
            }
        }
        .frame(width: 16, height: 16)
    }
}

// MARK: - 底部栏

struct BottomBar: View {
    @EnvironmentObject var manager: CameraManager

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            ShutterButton(mode: manager.mode, isRecording: manager.isRecording) {
                if manager.mode == .video { manager.toggleRecording() }
                else { manager.capturePhoto() }
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .leading) {
            LastShotThumbnail().padding(.leading, 26)
        }
        .overlay(alignment: .trailing) {
            FlipCameraButton().padding(.trailing, 26)
        }
    }
}

/// 最近成片缩略图：琥珀金双环框（借鉴飓风的渐变框相册入口）
/// 数据源是「应用内相册里最新的一张」，不再用显影层的临时图 —— 否则关掉显影后缩略图就是空的。
struct LastShotThumbnail: View {
    @EnvironmentObject var manager: CameraManager

    private var latest: AlbumItem? { manager.albumItems.first }

    var body: some View {
        Button { manager.openAlbum() } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(CameraTheme.amber, lineWidth: 2)
                    .frame(width: 46, height: 46)
                RoundedRectangle(cornerRadius: 8)
                    .fill(CameraTheme.bgElevated)
                    .frame(width: 34, height: 34)
                if let latest {
                    MediaThumbnail(item: latest, maxPixel: 160, fill: true)
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(CameraTheme.inkDim)
                }
            }
            .opacity(latest == nil ? 0.45 : 1)
            .frame(width: 46, height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(latest == nil ? "打开相册" : "打开相册，查看最近一张照片")
    }
}

// MARK: - 取景框四角 HUD

struct ViewfinderBrackets: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let len: CGFloat = 22
            Path { p in
                p.move(to: CGPoint(x: 0, y: len)); p.addLine(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: len, y: 0))
                p.move(to: CGPoint(x: w - len, y: 0)); p.addLine(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w, y: len))
                p.move(to: CGPoint(x: 0, y: h - len)); p.addLine(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: len, y: h))
                p.move(to: CGPoint(x: w - len, y: h)); p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w, y: h - len))
            }
            .stroke(CameraTheme.amber, lineWidth: 2)
        }
    }
}

// MARK: - 快门

struct ShutterButton: View {
    let mode: CameraMode
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().stroke(CameraTheme.amber, lineWidth: 4)
                    .frame(width: 74, height: 74)
                Circle()
                    .fill(innerFill)
                    .frame(width: 60, height: 60)
                    .overlay(Circle().stroke(CameraTheme.bgDeep, lineWidth: 2))
            }
            .shadow(color: glowColor, radius: 12)
        }
        .frame(width: 74, height: 74)
    }

    private var innerFill: some ShapeStyle {
        if mode == .video && isRecording { return AnyShapeStyle(CameraTheme.recRed) }
        return AnyShapeStyle(RadialGradient(colors: [CameraTheme.amberGlow, CameraTheme.amberDeep],
                                            center: .center, startRadius: 2, endRadius: 33))
    }

    private var glowColor: Color {
        (mode == .video && isRecording) ? CameraTheme.recRed.opacity(0.5) : CameraTheme.amber.opacity(0.45)
    }
}

// MARK: - 顶部圆角形状

/// 只描三条边（左 / 上 / 右）的圆角描边：
/// 弹层面板贴屏幕底部时，底边不该出现一条横线。
struct TopRoundedBorder: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

/// 只有上方两角为圆角的矩形：底部贴屏幕边缘的弹层用，底部保持直角与屏幕齐平
struct TopRounded: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - 胶片选择弹层

struct FilmSheet: View {
    @EnvironmentObject var manager: CameraManager

    private let descriptions: [FilmPreset: String] = [
        .kodakGold:   "暖金复古，肤色与阳光最出彩",
        .fuji400:     "清透冷绿，风光与街拍更通透",
        .classicBnw:  "高对比银盐，线条与颗粒",
        .fadedCinema: "低饱和奶油，像翻旧相册",
        .cinematic:   "青橙电影感，宽银幕叙事"
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraTheme.bgDeep.opacity(0.6).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { manager.showFilmSheet = false }

            VStack(spacing: 0) {
                Capsule().fill(CameraTheme.inkDim).frame(width: 38, height: 5)
                    .padding(.top, 10)
                Text("选择胶片").font(CameraTheme.mono(15, weight: .semibold))
                    .foregroundColor(CameraTheme.ink)
                    .padding(.vertical, 14)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(FilmPreset.allCases) { preset in
                            Button {
                                manager.selectedPreset = preset
                                manager.showFilmSheet = false
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    ZStack(alignment: .topTrailing) {
                                        FilmThumb(preset: preset)
                                        if manager.selectedPreset == preset {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(CameraTheme.amber)
                                                .padding(6)
                                        }
                                    }
                                    Text(preset.label)
                                        .font(CameraTheme.mono(12, weight: .semibold))
                                        .foregroundColor(CameraTheme.ink)
                                    Text(descriptions[preset] ?? "")
                                        .font(CameraTheme.mono(11))
                                        .foregroundColor(CameraTheme.inkDim)
                                        .lineLimit(2, reservesSpace: true)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(10)
                                .frame(width: 150, alignment: .leading)
                                .background(manager.selectedPreset == preset
                                            ? CameraTheme.amber.opacity(0.12)
                                            : CameraTheme.bgElevated)
                                .overlay(RoundedRectangle(cornerRadius: 12)
                                    .stroke(manager.selectedPreset == preset
                                            ? CameraTheme.amber : CameraTheme.hairline, lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                Color.clear.frame(height: 34)
            }
            .frame(maxWidth: .infinity)
            .background(CameraTheme.bgPanel)
            .clipShape(TopRounded(radius: 22))
            .overlay(TopRoundedBorder(radius: 22).stroke(CameraTheme.hairline, lineWidth: 1))
            .transition(.move(edge: .bottom))
        }
        // 面板贴到屏幕物理底边，底部留白由内层的 34pt 承担（避开 home indicator）
        .ignoresSafeArea(edges: .bottom)
    }
}

struct FilmThumb: View {
    let preset: FilmPreset
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                CameraTheme.bgDeep
            }
        }
        .frame(width: 128, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear { image = FilmPreview.image(for: preset) }
    }
}

// MARK: - 设置弹层

struct SettingsSheet: View {
    @EnvironmentObject var manager: CameraManager

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraTheme.bgDeep.opacity(0.6).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { manager.showSettingsSheet = false }

            VStack(alignment: .leading, spacing: 0) {
                Capsule().fill(CameraTheme.inkDim).frame(width: 38, height: 5)
                    .padding(.top, 10)
                Text("设置").font(CameraTheme.mono(15, weight: .semibold))
                    .foregroundColor(CameraTheme.ink)
                    .padding(.vertical, 14)

                Button {
                    manager.resetAuto()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("自动曝光与白平衡")
                                .font(CameraTheme.mono(13, weight: .medium))
                                .foregroundColor(CameraTheme.ink)
                            Text("恢复连续自动对焦 / 曝光 / 白平衡")
                                .font(CameraTheme.mono(11)).foregroundColor(CameraTheme.inkDim)
                        }
                        Spacer()
                        Text(manager.autoExposure && manager.autoWB ? "已开启" : "恢复自动")
                            .font(CameraTheme.mono(12, weight: .medium))
                            .foregroundColor(CameraTheme.amber)
                    }
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)

                Divider().overlay(CameraTheme.hairline)

                settingsToggle(title: "预览网格", subtitle: "三分构图辅助线", isOn: $manager.showGrid)
                Divider().overlay(CameraTheme.hairline)
                settingsToggle(title: "水平指示", subtitle: "取景器内显示横滚水平仪", isOn: $manager.showLevel)
                Divider().overlay(CameraTheme.hairline)
                settingsToggle(title: "存储提示", subtitle: "取景器右上角显示可用空间", isOn: $manager.showStorage)

                Color.clear.frame(height: 34)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CameraTheme.bgPanel)
            .clipShape(TopRounded(radius: 22))
            .overlay(TopRoundedBorder(radius: 22).stroke(CameraTheme.hairline, lineWidth: 1))
            .transition(.move(edge: .bottom))
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func settingsToggle(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(CameraTheme.mono(13, weight: .medium)).foregroundColor(CameraTheme.ink)
                Text(subtitle).font(CameraTheme.mono(11)).foregroundColor(CameraTheme.inkDim)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(CameraTheme.amber)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - 权限引导层

struct PermissionGate: View {
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        ZStack {
            CameraTheme.bgDeep.opacity(0.94).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 34)).foregroundColor(CameraTheme.amber)
                Text(title).foregroundColor(CameraTheme.ink).font(.headline)
                Text(message)
                    .foregroundColor(CameraTheme.inkDim)
                    .font(CameraTheme.mono(14))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 290)
                Button(action: action) {
                    Text(buttonTitle)
                        .font(CameraTheme.mono(15, weight: .semibold))
                        .padding(.horizontal, 24).padding(.vertical, 12)
                        .background(CameraTheme.amber).foregroundColor(CameraTheme.bgDeep)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 36)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Toast

/// 底部提示条底座：图标 + 文案 + 右侧动作。
/// 视频/照片/双曝三条提示原本各写一份同样的底板，样式一改就漏改，统一到这里。
struct ToastBar<Actions: View>: View {
    let icon: String
    let iconTint: Color
    let message: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundColor(iconTint)
                Text(message)
                    .foregroundColor(CameraTheme.ink)
                    .font(CameraTheme.mono(13))
                actions()
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(CameraTheme.bgDeep.opacity(0.9))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(CameraTheme.hairline, lineWidth: 1))
            .padding(.bottom, 40)
        }
        .transition(.move(edge: .bottom))
    }
}

/// 提示条上的文字按钮统一样式
struct ToastAction: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .foregroundColor(CameraTheme.amber)
            .font(CameraTheme.mono(13, weight: .semibold))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}

struct ToastVideoSaved: View {
    @EnvironmentObject var manager: CameraManager

    var body: some View {
        ToastBar(icon: "checkmark.circle.fill", iconTint: .green,
                 message: "视频已保存到相册") {
            ToastAction(title: "分享") { manager.openVideoShare() }
            ToastAction(title: "好") { manager.clearVideoSaved() }
        }
    }
}

struct ToastVideoBlocked: View {
    @EnvironmentObject var manager: CameraManager

    var body: some View {
        ToastBar(icon: "exclamationmark.triangle.fill", iconTint: CameraTheme.amber,
                 message: "视频未保存：请在设置中允许访问照片") {
            ToastAction(title: "去设置") { manager.openSystemSettings() }
            ToastAction(title: "好") { manager.dismissVideoSaveBlocked() }
        }
    }
}

struct ToastPhotoBlocked: View {
    @EnvironmentObject var manager: CameraManager

    var body: some View {
        ToastBar(icon: "exclamationmark.triangle.fill", iconTint: CameraTheme.amber,
                 message: "照片未保存：请在设置中允许访问照片") {
            ToastAction(title: "去设置") { manager.openSystemSettings() }
            ToastAction(title: "好") { manager.dismissPhotoSaveBlocked() }
        }
    }
}

struct ToastDoubleExposureFirst: View {
    @EnvironmentObject var manager: CameraManager

    var body: some View {
        ToastBar(icon: "1.circle.fill", iconTint: CameraTheme.amber,
                 message: "第一张已曝光 · 请拍第二张") {
            ToastAction(title: "好") { manager.clearDoubleExposureFirst() }
        }
        .task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            manager.clearDoubleExposureFirst()
        }
    }
}

// MARK: - 拍立得摇一摇显影

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
    @State private var shakePhase = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea().onTapGesture { onDismiss() }
            VStack(spacing: 20) {
                // 成片本身已带白色拍立得边框 + 日期戳，直接按原始比例展示即可。
                // 旧实现外套一张铺满全屏的白卡：竖版白框里浮着一张横版照片，
                // 上下大片空白 → 观感"横竖很别扭"。改为相纸贴合照片比例。
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: 26, x: 0, y: 14)
                    .padding(.horizontal, 18)
                    .opacity(model.done ? 1 : max(0.3, model.progress))
                    .blur(radius: model.done ? 0 : (1 - model.progress) * 9)
                    .rotationEffect(.degrees(model.useMotion && !model.done ? (shakePhase ? 3.5 : -3.5) : 0))
                if !model.done {
                    Text(model.useMotion ? "摇一摇 · 显影 \(Int(model.progress * 100))%" : "显影中…")
                        .foregroundColor(.white).padding(.bottom, 30)
                        .font(CameraTheme.mono(13, weight: .medium))
                } else {
                    Text("轻触关闭").foregroundColor(.white.opacity(0.6))
                        .padding(.bottom, 30)
                        .font(CameraTheme.mono(13, weight: .medium))
                }
            }
            .padding()
            .onTapGesture { onDismiss() }
        }
        .onAppear {
            model.start()
            withAnimation(.easeInOut(duration: 0.18).repeatForever(autoreverses: true)) { shakePhase = true }
        }
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

// MARK: - 预览渲染

/// 订阅 Combine 帧流直接改 UIImageView.image，绕过 SwiftUI 的状态观察 ——
/// 避免每帧重算整棵视图树（真机流畅度的关键）。
struct PreviewView: UIViewRepresentable {
    let frames: PassthroughSubject<UIImage, Never>

    func makeUIView(context: Context) -> UIView {
        // 关键：不能把 UIImageView 直接返回给 SwiftUI。
        // UIImageView 的固有尺寸 = 图片尺寸，相机帧动辄 4000×3000，
        // 会让取景器膨胀到远超屏幕，把顶部/底部所有 UI 挤出屏幕（真机必现）。
        // 用普通容器 view 承载（无固有尺寸），图片 view 靠约束贴边，
        // 尺寸完全由外层 .frame 决定。
        let container = UIView()
        container.backgroundColor = .black

        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = .black
        iv.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(iv)
        NSLayoutConstraint.activate([
            iv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            iv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            iv.topAnchor.constraint(equalTo: container.topAnchor),
            iv.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        context.coordinator.cancellable = frames
            .receive(on: DispatchQueue.main)
            .sink { [weak iv] image in iv?.image = image }
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var cancellable: AnyCancellable?
    }
}
