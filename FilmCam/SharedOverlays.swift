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

/// 胶片仓：打开机背，一排暗盒躺在仓里，点一个装进去。
/// 比"底部卡片轮播"更贴机身：换胶片是装暗盒，不是选颜色。
struct FilmSheet: View {
    @EnvironmentObject var manager: CameraManager

    var body: some View {
        let t = ThemeStore.current

        ZStack(alignment: .bottom) {
            Color.black.opacity(0.5).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { manager.showFilmSheet = false }

            VStack(spacing: 0) {
                // 仓盖沿
                HStack(spacing: 8) {
                    ScrewHead(size: 7)
                    Silkscreen(text: "FILM CHAMBER", color: .black.opacity(0.55),
                               size: 7, tracking: 2.2)
                    Spacer()
                    Silkscreen(text: "\(FilmPreset.allCases.count) STOCKS  ·  TAP TO LOAD",
                               color: .black.opacity(0.4), size: 6, tracking: 1.2)
                    Button { manager.showFilmSheet = false } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.black.opacity(0.6))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    ScrewHead(size: 7)
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(AluminumFace(tokens: t))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(.black.opacity(0.45)).frame(height: 1)
                }

                // 仓内：暗盒导轨
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(FilmPreset.allCases) { preset in
                            FilmCanister(preset: preset,
                                         loaded: manager.selectedPreset == preset,
                                         tokens: t) {
                                manager.selectedPreset = preset
                                Haptics.impact(.medium)
                                manager.showFilmSheet = false
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(LeatherPanel())

                // 仓底齿孔
                HStack(spacing: 5) {
                    ForEach(0..<30, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(.white.opacity(0.10))
                            .frame(width: 7, height: 4)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Color(hex: 0x141516))
            }
            .clipShape(TopRounded(radius: 14))
            .overlay(TopRoundedBorder(radius: 14).stroke(.black.opacity(0.5), lineWidth: 1))
            .transition(.move(edge: .bottom))
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

/// 一个胶片暗盒：金属罐身 + 彩色标签带 + 底部卷轴
struct FilmCanister: View {
    let preset: FilmPreset
    let loaded: Bool
    let tokens: ThemeTokens
    let action: () -> Void

    private var labelColor: Color {
        switch preset {
        case .kodakGold:   return Color(hex: 0xC8912B)
        case .fuji400:     return Color(hex: 0x2E7D53)
        case .classicBnw:  return Color(hex: 0x4A4A4A)
        case .fadedCinema: return Color(hex: 0xB0706A)
        case .cinematic:   return Color(hex: 0x2A6E7A)
        }
    }

    private var iso: String {
        switch preset {
        case .kodakGold:   return "ISO 200"
        case .fuji400:     return "ISO 400"
        case .classicBnw:  return "ISO 400"
        case .fadedCinema: return "ISO 200"
        case .cinematic:   return "ISO 500"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                // 顶盖
                ZStack {
                    LinearGradient(colors: [Color(hex: 0x3A3D40), Color(hex: 0x1B1D1F)],
                                   startPoint: .top, endPoint: .bottom)
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { _ in
                            Capsule().fill(.white.opacity(0.18)).frame(width: 2, height: 6)
                        }
                    }
                }
                .frame(height: 11)

                // 罐身 + 标签
                ZStack {
                    LinearGradient(colors: [Color(hex: 0xCFD4D8), Color(hex: 0x8E9499)],
                                   startPoint: .top, endPoint: .bottom)
                    VStack(spacing: 3) {
                        Rectangle().fill(labelColor).frame(height: 30)
                            .overlay(
                                Text(preset.label)
                                    .font(.custom("Futura-Medium", size: 9))
                                    .foregroundColor(.white.opacity(0.95))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                    .padding(.horizontal, 4)
                            )
                        Text(iso)
                            .font(.system(size: 6, weight: .bold, design: .monospaced))
                            .foregroundColor(.black.opacity(0.55))
                        Spacer(minLength: 0)
                        // 卷轴
                        Circle()
                            .fill(LinearGradient(colors: [Color(hex: 0x2A2C2E), Color(hex: 0x0E0F10)],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().fill(.white.opacity(0.12)).frame(width: 5, height: 5))
                    }
                    .padding(.vertical, 6)
                }
                .frame(height: 86)

                // 底盖
                LinearGradient(colors: [Color(hex: 0x1B1D1F), Color(hex: 0x36393C)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 9)
            }
            .frame(width: 74)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(loaded ? tokens.accent : .black.opacity(0.45),
                                  lineWidth: loaded ? 2 : 1)
            )
            .overlay(alignment: .top) {
                if loaded {
                    HStack(spacing: 3) {
                        LEDDot(color: tokens.glow, size: 4)
                        Text("LOADED")
                            .font(.system(size: 5.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(.black.opacity(0.7)))
                    .offset(y: -7)
                }
            }
            .shadow(color: .black.opacity(0.5), radius: 4, y: 3)
            .scaleEffect(loaded ? 1.0 : 0.96)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preset.label)，\(iso)\(loaded ? "，已装载" : "")")
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
                // 服务面板：螺丝 + 丝印标题，和机身同一套语言
                HStack(spacing: 8) {
                    ScrewHead(size: 7)
                    Silkscreen(text: "SERVICE PANEL", color: CameraTheme.ink.opacity(0.55),
                               size: 7, tracking: 2)
                    Spacer()
                    Text("设置")
                        .font(CameraTheme.mono(11, weight: .bold))
                        .foregroundColor(CameraTheme.ink.opacity(0.6))
                    ScrewHead(size: 7)
                }
                .padding(.vertical, 12)
                GrooveLine()

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

                GrooveLine()

                settingsToggle(title: "预览网格", subtitle: "三分构图辅助线", isOn: $manager.showGrid)
                GrooveLine()
                settingsToggle(title: "水平指示", subtitle: "取景器内显示横滚水平仪", isOn: $manager.showLevel)
                GrooveLine()
                settingsToggle(title: "存储提示", subtitle: "取景器右上角显示可用空间", isOn: $manager.showStorage)

                Color.clear.frame(height: 34)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AluminumFace(tokens: ThemeStore.current))
            .clipShape(TopRounded(radius: 14))
            .overlay(TopRoundedBorder(radius: 14).stroke(.black.opacity(0.45), lineWidth: 1))
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
                .accessibilityLabel(title)
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
        .onAppear {
            UIAccessibility.post(notification: .announcement, argument: message)
        }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            CameraTheme.bgDeep.opacity(0.93).ignoresSafeArea().onTapGesture { onDismiss() }
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
                    .rotationEffect(.degrees(shakeRotation))
                if !model.done {
                    Text(model.useMotion ? "摇一摇 · 显影 \(Int(model.progress * 100))%" : "显影中…")
                        .foregroundColor(CameraTheme.ink).padding(.bottom, 30)
                        .font(CameraTheme.mono(13, weight: .medium))
                } else {
                    Text("轻触关闭").foregroundColor(CameraTheme.inkDim)
                        .padding(.bottom, 30)
                        .font(CameraTheme.mono(13, weight: .medium))
                }
            }
            .padding()
            .onTapGesture { onDismiss() }
        }
        .onAppear {
            model.start()
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.18).repeatForever(autoreverses: true)) { shakePhase = true }
        }
    }

    /// 「减少动态效果」开启时不晃，只保留显影进度
    private var shakeRotation: Double {
        guard !reduceMotion, model.useMotion, !model.done else { return 0 }
        return shakePhase ? 3.5 : -3.5
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
    /// 首帧兜底：视图比帧晚创建时先显示上一帧，而不是黑屏
    var initialImage: UIImage? = nil

    func makeUIView(context: Context) -> UIView {
        // 关键：不能把 UIImageView 直接返回给 SwiftUI。
        // UIImageView 的固有尺寸 = 图片尺寸，相机帧动辄 4000×3000，
        // 会让取景器膨胀到远超屏幕，把顶部/底部所有 UI 挤出屏幕（真机必现）。
        // 用普通容器 view 承载（无固有尺寸），图片 view 靠约束贴边，
        // 尺寸完全由外层 .frame 决定。
        let container = UIView()
        container.backgroundColor = .black

        let iv = UIImageView()
        iv.image = initialImage
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
