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
