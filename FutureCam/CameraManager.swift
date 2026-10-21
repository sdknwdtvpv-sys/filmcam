import SwiftUI
import AVFoundation
import UIKit
import Photos
import Combine

/// 闪光策略：拍照用 off/auto/on 循环，视频里 on 等于常亮补光
enum FlashState: String, CaseIterable {
    case off, auto, on

    var label: String {
        switch self {
        case .off: return "关"
        case .auto: return "自动"
        case .on: return "开"
        }
    }

    var symbol: String {
        switch self {
        case .off: return "bolt.slash"
        case .auto: return "bolt.badge.automatic"
        case .on: return "bolt.fill"
        }
    }

    var next: FlashState {
        switch self {
        case .off: return .auto
        case .auto: return .on
        case .on: return .off
        }
    }

    var deviceMode: AVCaptureDevice.FlashMode {
        switch self {
        case .off: return .off
        case .auto: return .auto
        case .on: return .on
        }
    }
}

/// 单个可调参数（药丸点选 + 展开对应滑杆）
enum ParamKey: String, CaseIterable, Identifiable {
    case iso
    case shutter
    case bias
    case temperature
    case tint
    var id: String { rawValue }
    /// 药丸上的短标题
    var pillTitle: String {
        switch self {
        case .iso: return "ISO"
        case .shutter: return "快门"
        case .bias: return "EV"
        case .temperature: return "色温"
        case .tint: return "色调"
        }
    }
    /// 滑杆行上的完整标题
    var sliderTitle: String {
        switch self {
        case .iso: return "ISO"
        case .shutter: return "快门"
        case .bias: return "曝光补偿"
        case .temperature: return "色温"
        case .tint: return "色调"
        }
    }
}

/// 相册媒体类型
enum AlbumMediaKind: String, Sendable {
    case photo
    case video
}

/// 应用内相册里的一条媒体（本地沙盒存储，不依赖系统相册权限）
/// 一次性相机提示：标题 + 值，视图收到后显示 HUD 并清空
struct CameraNotice: Equatable, Identifiable {
    let id = UUID()
    var title: String
    var value: String
}

struct AlbumItem: Identifiable, Hashable {
    let id: String          // 文件名
    let url: URL            // 本地文件路径
    let kind: AlbumMediaKind
    let createdAt: Date
    var rollID: String? = nil   // 属于哪一卷（旧照片为 nil）
}

/// 主线程相机视图模型：只持有 UI 状态，把相机硬件操作委托给后台 CaptureSessionController。
@MainActor
final class CameraManager: NSObject, ObservableObject {
    // MARK: - 预览
    /// 高频预览帧走 Combine 直连预览视图，刻意【不】用 @Published：
    /// 否则每帧都会重算整棵 SwiftUI 视图树，真机上会造成明显卡顿、甚至看起来"点了没反应"。
    let previewFrames = PassthroughSubject<UIImage, Never>()
    /// 是否已收到首帧（低频状态，用 @Published 安全）
    @Published var hasPreview = false
    /// 最近一帧预览图：PreviewView 重建（如切换主题）时先垫上，避免黑一下
    private(set) var lastPreviewFrame: UIImage?
    /// 已授权但迟迟收不到帧（相机被占用 / 初始化失败）
    @Published var previewStalled = false

    /// 日期背印：打开后才把橙色日期烧进成片
    @Published var dateStampEnabled: Bool = UserDefaults.standard.bool(forKey: "futurecam.dateStamp") {
        didSet { UserDefaults.standard.set(dateStampEnabled, forKey: "futurecam.dateStamp") }
    }
    @Published var capturedImage: UIImage?
    /// 这一张「只过胶片」的底，换调色时从它重渲染
    private(set) var capturedBase: UIImage?
    /// 已经落到应用内相册的那一条（换调色时覆盖它）
    private var capturedAlbumItem: AlbumItem?
    /// 关闭显影页时才写进系统相册，此时用用户最后选的调色
    private var pendingLibrarySave: (UIImage, Data?)?
    @Published var authorizationStatus: AVAuthorizationStatus = .notDetermined
    /// 照片写入相册失败（相册权限被拒 / 写入失败）——用于引导去系统设置。
    @Published var photoSaveBlocked = false
    /// 视频写入系统相册失败
    @Published var videoSaveBlocked = false
    /// 录制完成后的本地文件（供「分享」用，过期即失效）
    @Published var recordedVideoURL: URL?

    /// 当前这一张用的调色（只表示显影页里选了什么，不参与拍摄）。
    /// 调色是纯后置的：拍摄永远只出胶片，调色在显影页里选。
    @Published var selectedLook: LookChoice = .none
    /// 胶卷仓库：当前装着的这卷 + 已拍完的卷
    let rolls = RollStore.shared
    /// 一次性提示（本卷拍完 / 已换卷），视图消费后清空
    @Published var notice: CameraNotice?
    @Published var selectedPreset: FilmPreset = .kodakGold {
        didSet {
            controller.preset = selectedPreset
            syncGrain()
        }
    }
    @Published var mode: CameraMode = .photo { didSet { modeChanged(mode) } }
    @Published var doubleExposureStep: Int = 0
    @Published var isRecording = false
    @Published var showVideoSaved = false
    /// 系统分享面板（录制完成的视频）
    @Published var showVideoShare = false
    /// 双曝第一张已曝光提示（短暂出现，不弹显影层）
    @Published var showDoubleExposureFirst = false

    // 取景手势状态（对焦/变焦/镜头）
    /// 当前取景画面的宽高比（来自首帧，用于把点击坐标换算成设备坐标）
    @Published var previewAspect: CGFloat?
    /// 当前变焦倍率（1.0 = 1×）
    /// 三脚架检测
    private let stability = StabilityMonitor()
    private var longExposureWarned = false
    /// 自制胶卷编辑器
    @Published var showFilmEditor = false
    /// 长曝光进行中：按钮转红、盘面显示积分进度
    @Published var isLongExposing = false
    @Published var longExposureProgress: Double = 0

    /// 当前焦段（用户视角：0.5× / 1× / 2× / 5×…），由物理镜头切换实现
    @Published var zoomFactor: CGFloat = 1
    /// 这台机型支持的光学焦段
    var focalOptions: [CGFloat] { controller.focalLengthOptions }
    /// 焦段切换时短暂显示的框线（取景范围提示）
    @Published var frameFlashAt: CGFloat?

    func selectFocalLength(_ value: CGFloat) {
        zoomFactor = value
        controller.setFocalLength(value)
        Haptics.impact(.light)
        // 400ms 框线提示：切换瞬间告诉用户画幅怎么变了
        frameFlashAt = value
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 420_000_000)
            guard let self, self.frameFlashAt == value else { return }
            withAnimation(.easeOut(duration: 0.18)) { self.frameFlashAt = nil }
        }
    }
    /// 当前焦段最接近的档位（用于高亮）
    var nearestFocal: CGFloat {
        focalOptions.min(by: { abs($0 - zoomFactor) < abs($1 - zoomFactor) }) ?? 1
    }
    /// 是否前摄
    @Published var isFrontCamera = false
    /// 闪光 / 视频补光
    @Published var flashState: FlashState = .off
    /// 保存视频时申请的后台时间，避免切后台被立刻挂起导致写盘中断
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    /// 胶片计数器（跨启动累计，暗房工单 / 胶片带主题的主视觉）
    @Published var frameCount: Int = UserDefaults.standard.integer(forKey: "futurecam.frameCount")

    // 手动参数（UI 状态，device 内部会 clamp 到支持范围）
    @Published var iso: Double = 200 { didSet { syncGrain() } }
    @Published var shutterSeconds: Double = 1.0 / 60.0
    @Published var bias: Double = 0
    @Published var temperature: Double = 5500
    @Published var tint: Double = 0
    @Published var autoExposure = true
    @Published var autoWB = true

    // MARK: - 取景辅助与信息架构状态（对标飓风相机）
    /// 当前参数分组（药丸行显示曝光组还是白平衡组）
    /// 当前展开滑杆的参数；nil = 收起
    @Published var activeParam: ParamKey? = .shutter
    /// 三分构图网格
    @Published var showGrid = false
    /// 水平仪
    @Published var showLevel = false
    /// 取景器内是否显示存储角标
    @Published var showStorage = true
    /// 胶片选择弹层
    @Published var showFilmSheet = false
    /// 设置弹层
    @Published var showSettingsSheet = false
    /// 应用内相册弹层
    @Published var showAlbum = false
    /// 应用内相册里的照片（本地沙盒，最新在前）
    @Published var albumItems: [AlbumItem] = []
    /// 可用空间文本（如 "52 GB"）
    @Published var freeStorageText = "--"
    /// 按 1080p30 估算的剩余可录时长（如 "298 min"）
    @Published var recordMinutesText = "--"

    private let controller = CaptureSessionController()
    private var didStartCamera = false
    private var watchdog: Task<Void, Never>?

    override init() {
        super.init()
        selectedPreset = rolls.current.preset
        selectedLook = .none
        syncGrain()
        refreshStorage()
        loadAlbum()
        controller.onPreview = { [weak self] image in
            Task { @MainActor in self?.handlePreviewFrame(image) }
        }
        controller.onPhoto = { [weak self] image, jpeg, base in
            Task { @MainActor in
                guard let self else { return }
                self.showDoubleExposureFirst = false
                let final = self.finalized(image)
                self.capturedImage = final
                self.capturedBase = base
                self.capturedAlbumItem = nil
                self.pendingLibrarySave = (final, jpeg)
                self.selectedLook = .none
                self.bumpFrameCount()
                self.rolls.recordShot()
                let rollID = self.rolls.current.id
                if self.mode == .doubleExposure, self.doubleExposureStep == 1 {
                    self.doubleExposureStep = 2
                }
                self.saveToAlbumOnly(final, jpeg: jpeg, rollID: rollID)
            }
        }
        controller.onDoubleExposureFirstShot = { [weak self] image in
            Task { @MainActor in
                // 第一张只作为合成底图，不进入拍立得显影层
                self?.doubleExposureStep = 1
                self?.showDoubleExposureFirst = true
            }
        }
        controller.onCameraSwitched = { [weak self] isFront in
            Task { @MainActor in
                self?.isFrontCamera = isFront
                self?.zoomFactor = 1
                self?.controller.setFocalLength(1)
            }
        }
        controller.onVideoSaved = { [weak self] url in
            Task { @MainActor in
                self?.isRecording = false
                self?.recordedVideoURL = url
                // 本地相册（应用内）立刻可见；同时真写进系统相册，
                // 成功后才提示「已保存」，失败走拦截引导
                self?.persistVideoLocally(url, rollID: self?.rolls.current.id)
                self?.saveVideoToLibrary(url)
            }
        }
    }

    // MARK: - 预览帧
    private func handlePreviewFrame(_ image: UIImage) {
        if !hasPreview {
            hasPreview = true
            previewStalled = false
            watchdog?.cancel(); watchdog = nil
            if image.size.height > 0 {
                previewAspect = image.size.width / image.size.height
            }
        }
        lastPreviewFrame = image
        previewFrames.send(image)
    }

    #if DEBUG
    /// 仅 Debug：没有相机的模拟器里垫一帧合成画面，用来检查叠加层布局
    func enableStubPreview() {
        guard !hasPreview, let frame = DebugHarness.stubPreviewFrame() else { return }
        handlePreviewFrame(frame)
    }
    #endif

    // MARK: - 权限 & 启动
    /// 首次/主动请求：只处理 notDetermined。
    /// denied / restricted 时【不能】空转——由界面引导用户去系统设置，见 openSystemSettings()。
    func requestAccessAndConfigure() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        authorizationStatus = status
        switch status {
        case .authorized:
            startCameraIfNeeded()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    self?.authorizationStatus = granted ? .authorized : .denied
                    if granted { self?.startCameraIfNeeded() }
                }
            }
        default:
            // denied / restricted：什么都不做（界面会给"去系统设置"按钮）
            break
        }
    }

    /// 回到前台时重新读取权限（用户可能刚在「设置」里改过），并补启动 / 恢复会话。
    func refreshAuthorization() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status != authorizationStatus { authorizationStatus = status }
        if status == .authorized {
            startCameraIfNeeded()
            // 已在运行过的情况下 startCameraIfNeeded 会直接 return，
            // 这里必须显式恢复会话，否则切后台回来是黑屏。
            controller.resume()
        }
        refreshStorage()
    }

    /// 进入后台：正在录制就先收尾（否则 mov 永远不封口），再停会话。
    /// 收尾和写盘期间申请后台时间，避免文件还没写完进程就被挂起。
    func pauseCamera() {
        if isRecording {
            isRecording = false
            beginBackgroundGrace()
            controller.stopRecording()
        }
        controller.pause()
    }

    private func beginBackgroundGrace() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "FutureCam.finishRecording") { [weak self] in
            self?.endBackgroundGrace()
        }
    }

    private func endBackgroundGrace() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    /// 读取可用空间，并按 1080p30（≈12 Mbps）估算剩余可录时长。
    func refreshStorage() {
        let fm = FileManager.default
        let url = fm.urls(for: .documentDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let bytes = values.volumeAvailableCapacityForImportantUsage else { return }
        freeStorageText = String(format: "%.0f GB", Double(bytes) / 1_000_000_000)
        let bytesPerMinute = 12_000_000.0 / 8.0 * 60.0   // 12 Mbps → 90 MB/分钟
        recordMinutesText = "\(Int(Double(bytes) / bytesPerMinute)) min"
    }

    /// 跳转到本 App 的系统设置页（相机权限被拒后的唯一出路）。
    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url) { [weak self] _ in
            // 返回后由 scenePhase 触发 refreshAuthorization()，这里无需处理
            _ = self
        }
    }

    /// 打开应用内相册（不再跳出 App 跳系统「照片」）
    func openAlbum() { showAlbum = true }
    func closeAlbum() { showAlbum = false }

    /// 启动时从本地沙盒读取已拍照片，填充相册
    func loadAlbum() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let items = AlbumStore.loadAll()
            DispatchQueue.main.async { self?.albumItems = items }
        }
    }

    /// 把一张成片写入本地沙盒，供应用内相册展示（不依赖系统相册权限）
    private func persistLocally(_ image: UIImage, jpeg: Data?, rollID: String?) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let item = AlbumStore.savePhoto(image, jpeg: jpeg, rollID: rollID) else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                if self.albumItems.firstIndex(where: { $0.id == item.id }) == nil {
                    self.albumItems.insert(item, at: 0)
                }
                // 记下这一条，换调色时覆盖它
                if self.capturedAlbumItem == nil { self.capturedAlbumItem = item }
            }
        }
    }

    /// 录制完成的视频：复制进相册目录（tmp 会被系统清掉），并让「分享」指向本地副本
    private func persistVideoLocally(_ tmpURL: URL, rollID: String?) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let item = AlbumStore.saveVideo(from: tmpURL, rollID: rollID)
            DispatchQueue.main.async {
                guard let self, let item else { return }
                if self.albumItems.firstIndex(where: { $0.id == item.id }) == nil {
                    self.albumItems.insert(item, at: 0)
                }
                self.recordedVideoURL = item.url
            }
        }
    }

    private func startCameraIfNeeded() {
        guard !didStartCamera else { return }
        didStartCamera = true
        startWatchdog()
        requestAudioThenStart()
    }

    /// 首帧看门狗：授权后若长时间收不到帧，给出可见反馈，避免"永久黑屏无提示"。
    private func startWatchdog() {
        watchdog?.cancel()
        previewStalled = false
        watchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, !Task.isCancelled else { return }
            if !self.hasPreview { self.previewStalled = true }
        }
    }

    /// 请求麦克风授权（视频录音需要），随后启动相机会话。
    /// 若用户拒绝，则降级为无声视频录制。
    private func requestAudioThenStart() {
        let aStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        switch aStatus {
        case .authorized:
            controller.configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                Task { @MainActor in self?.controller.configureAndStart() }
            }
        default:
            controller.configureAndStart()
        }
    }

    // MARK: - 控制
    func capturePhoto() {
        guard !rolls.current.isFull else {
            notice = CameraNotice(title: "本卷拍完", value: "换一卷")
            Haptics.impact(.heavy)
            return
        }
        guard !isLongExposing else { return }

        // 快门超过 1 秒：走多帧堆栈（设备单帧上限约 1 秒）
        if shutterSeconds >= CameraMath.longExposureThreshold {
            MechanicalSounds.shared.shutter()
            startLongExposure()
            return
        }
        MechanicalSounds.shared.shutterThenAdvance()
        controller.capture()
    }

    /// 长曝光：积分期间按快门可提前结束
    private func startLongExposure() {
        isLongExposing = true
        longExposureProgress = 0
        stability.start()
        Haptics.impact(.rigid)

        longExposureWarned = false
        controller.onLongExposureProgress = { [weak self] progress in
            DispatchQueue.main.async {
                guard let self else { return }
                self.longExposureProgress = progress
                // 长时间积分且没架稳：提醒一次，别等拍完才发现糊了
                if !self.longExposureWarned, self.shutterSeconds >= 8,
                   progress > 0.25, !self.stability.isSteady {
                    self.longExposureWarned = true
                    self.notice = CameraNotice(title: "画面在动", value: "架稳再拍")
                    Haptics.impact(.rigid)
                }
            }
        }
        controller.startLongExposure(seconds: shutterSeconds) { [weak self] stacked in
            guard let self else { return }
            self.stability.stop()
            self.isLongExposing = false
            // 积分完再走成片管线：胶片 + 颗粒 + 当前调色
            let roll = self.rolls.current
            let recipe = RenderPipeline.Recipe.still(
                preset: roll.preset,
                traits: roll.traits,
                grain: roll.preset.hasGrain
                    ? GrainSettings.make(iso: self.iso, traits: roll.traits, seed: roll.seed)
                    : .none,
                grade: nil,
                mirrored: self.isFrontCamera)
            let base = RenderPipeline.render(stacked, recipe: recipe)
            guard let rendered = FilmFilter.render(base) else { return }
            let final = self.finalized(rendered.0)
            self.capturedImage = final
            self.capturedBase = rendered.0
            self.capturedAlbumItem = nil
            self.pendingLibrarySave = (final, self.controller.reencodeJPEG(final))
            self.selectedLook = .none
            self.bumpFrameCount()
            self.saveToAlbumOnly(final, jpeg: nil, rollID: self.rolls.current.id)
            Haptics.impact(.heavy)
        }
    }

    /// 机器档案：全部来自本机数据，不联网
    struct MachineStats {
        var shots: Int = 0
        var rolls: Int = 0
        var firstShotAt: Date?
        var favouriteFilm: String?
    }

    var machineStats: MachineStats {
        var stats = MachineStats()
        stats.shots = albumItems.filter { $0.kind == .photo }.count
        let archived = rolls.archive.count
        stats.rolls = archived + 1

        let dates = albumItems.map(\.createdAt)
        let rollDates = ([rolls.current.startedAt] + rolls.archive.map(\.startedAt))
        stats.firstShotAt = (dates + rollDates).min()

        // 哪一卷用得最多：按 rollID 分组数张数
        var counts: [String: Int] = [:]
        for item in albumItems {
            guard let id = item.rollID else { continue }
            counts[id, default: 0] += 1
        }
        if let top = counts.max(by: { $0.value < $1.value }),
           let roll = rolls.roll(id: top.key) {
            stats.favouriteFilm = roll.preset.label
        }
        return stats
    }

    /// 这条记录属于哪一卷胶卷（相册详情里显示用）
    func presetLabel(for item: AlbumItem) -> String {
        guard let id = item.rollID, let roll = rolls.roll(id: id) else { return "未归档" }
        return roll.preset.label
    }

    func rollNumberText(for item: AlbumItem) -> String {
        guard let id = item.rollID, let roll = rolls.roll(id: id) else { return "--" }
        return String(format: "%02d", roll.number)
    }

    func frameText(for item: AlbumItem) -> String {
        let siblings = albumItems.filter { $0.rollID == item.rollID && $0.kind != .video }
        guard let index = siblings.firstIndex(where: { $0.id == item.id }) else { return "--/--" }
        return String(format: "%02d/%02d", siblings.count - index, siblings.count)
    }

    /// 重新读一遍应用内相册（冲印覆盖文件后调用）
    func refreshAlbum() {
        albumItems = AlbumStore.loadAll()
    }

    /// 当前这卷
    var roll: FilmRoll { rolls.current }

    /// 换一卷：把当前这卷收起来，装新的
    @discardableResult
    func loadRoll(_ preset: FilmPreset) -> FilmRoll {
        let fresh = rolls.load(preset)
        selectedPreset = preset
        syncGrain()
        syncWidget()
        notice = CameraNotice(title: "已装卷", value: "\(preset.label) \(fresh.numberText)")
        return fresh
    }

    /// 把当前这卷的性格与颗粒参数推给渲染层
    private func syncGrain() {
        let traits = rolls.current.traits
        controller.rollTraits = traits
        controller.grain = rolls.current.preset.hasGrain
            ? GrainSettings.make(iso: iso, traits: traits, seed: rolls.current.seed)
            : .none
    }

    /// 闪光循环：关 → 自动 → 开；视频模式下"开"同时点着手电
    func cycleFlash() {
        flashState = flashState.next
        controller.setFlashMode(flashState.deviceMode)
        controller.setTorch(mode == .video && flashState == .on)
        Haptics.impact(.light)
    }

    /// 前后摄切换（录制中不允许，避免把一条视频写成两种镜头）
    func switchCamera() {
        guard !isRecording else { return }
        controller.switchCamera()   // 成功后由 onCameraSwitched 回写 isFrontCamera
    }

    /// 点按对焦 / 长按锁定。point 为取景器内的局部坐标（pt）。
    func focus(at point: CGPoint, in size: CGSize, lock: Bool) {
        guard let aspect = previewAspect, size.width > 0, size.height > 0 else { return }
        let devicePoint = CameraMath.sensorPoint(from: point,
                                                 container: size,
                                                 previewAspect: aspect,
                                                 mirrored: isFrontCamera)
        controller.focus(at: devicePoint, lock: lock, touchExposure: autoExposure)
    }

    /// 解除 AE/AF 锁定
    func clearFocusLock() {
        controller.unlockFocusAndExposure()
    }

    /// 捏合变焦：传入相对倍率（1.0 = 不缩放）
    func applyZoom(base: CGFloat, scale: CGFloat) {
        let target = min(max(base * scale, 1), 8)
        zoomFactor = target
        controller.setZoom(target)
    }

    func endZoom() { controller.setZoom(zoomFactor) }

    func toggleRecording() {
        if isRecording {
            isRecording = false
            controller.stopRecording()
        } else {
            isRecording = true
            controller.startRecording()
        }
    }

    func clearCaptured() {
        if let pending = pendingLibrarySave {
            saveToLibrary(pending.0, jpeg: pending.1, rollID: rolls.current.id)
        }
        pendingLibrarySave = nil
        capturedBase = nil
        capturedAlbumItem = nil
        capturedImage = nil
        if doubleExposureStep == 2 { doubleExposureStep = 0 }
    }

    #if DEBUG
    /// 调试：让假成片也走一遍成片出口（日期背印等），用于截图自检
    func previewCapturedForDebug(_ image: UIImage) {
        let final = finalized(image)
        capturedImage = final
        // 把成片写到沙盒，用来做像素级自检（有没有真的烧上日期、位置对不对）
        if DebugHarness.shouldProbeDateStamp, let data = final.jpegData(compressionQuality: 0.95) {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("datestamp-probe.jpg")
            try? data.write(to: url)
            NSLog("[DateProbe] 写入 %@ size=%.0fx%.0f", url.lastPathComponent,
                  final.size.width, final.size.height)
        }
    }
    #endif

    /// 成片统一出口：需要日期背印就烧上去，并把 JPEG 重新编码（保留 EXIF）
    private func finalized(_ image: UIImage) -> UIImage {
        guard dateStampEnabled else { return image }
        return DateBack.apply(to: image)
    }

    /// 拍完再换调色：从「只过胶片的底」重渲染，覆盖相册里那一张
    func regradeCaptured(to look: LookChoice) {
        guard let base = capturedBase, let ci = CIImage(image: base) else { return }
        let out = look.apply(to: ci)
        guard let rendered = FilmFilter.render(out) else { return }
        let final = finalized(rendered.0)
        // 用原片的 EXIF 重新编码，换调色不会丢元数据
        let jpeg = controller.reencodeJPEG(final)
            ?? final.jpegData(compressionQuality: 0.92)
        capturedImage = final
        selectedLook = look
        pendingLibrarySave = (final, jpeg)

        guard let item = capturedAlbumItem, let jpeg else { return }
        let albumCopy = jpeg
        DispatchQueue.global(qos: .userInitiated).async {
            AlbumStore.overwrite(item, jpeg: albumCopy)
        }
    }

    func clearVideoSaved() { showVideoSaved = false; recordedVideoURL = nil }
    func clearDoubleExposureFirst() { showDoubleExposureFirst = false }

    private func modeChanged(_ m: CameraMode) {
        controller.setDoubleExposureEnabled(m == .doubleExposure)
        controller.setTorch(m == .video && flashState == .on)
        if m != .doubleExposure { doubleExposureStep = 0 }
        // 先收尾录像，再动麦克风：录着的时候摘输入会把这一条的后半段弄成无声
        if isRecording { isRecording = false; controller.stopRecording() }
        controller.setWantsAudioInput(m == .video)
    }

    // MARK: - 手动参数
    func applyExposure() {
        autoExposure = false
        controller.setManualExposure(iso: Float(iso), shutterSeconds: shutterSeconds, bias: Float(bias))
    }

    func applyWhiteBalance() {
        autoWB = false
        controller.setWhiteBalance(temperature: Float(temperature), tint: Float(tint))
    }

    func resetAuto() {
        autoExposure = true
        autoWB = true
        controller.setAutoExposure()
        controller.setAutoWhiteBalance()
        controller.setAutoFocus()
        // 复位变焦，避免「恢复自动」后画面还停在 3×
        zoomFactor = 1
        controller.setZoom(1)
    }

    // MARK: - 药丸 / 参数面板交互
    /// 选中参数：机身右下那颗滚花轮盘会驱动当前选中的参数
    func selectParam(_ key: ParamKey) {
        activeParam = key
    }

    /// 兼容旧调用名
    func toggleParam(_ key: ParamKey) { selectParam(key) }

    // MARK: - 保存到相册
    /// 只写应用内相册（立刻，避免丢片）
    private func saveToAlbumOnly(_ image: UIImage, jpeg: Data?, rollID: String?) {
        persistLocally(image, jpeg: jpeg, rollID: rollID)
    }

    /// 写系统相册（延后到关闭显影页，用最终选定的调色）
    private func saveToLibrary(_ image: UIImage, jpeg: Data?, rollID: String?) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in
                    self?.photoSaveBlocked = true   // 相册权限被拒：引导去设置
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                if let jpeg {
                    // 走 data 资源，EXIF 才会跟着进系统相册
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, data: jpeg, options: nil)
                } else {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
            }) { success, _ in
                Task { @MainActor in
                    // 成功不弹窗（应用内相册里已经能看到），失败才引导
                    if !success { self?.photoSaveBlocked = true }
                }
            }
        }
    }

    func dismissPhotoSaveBlocked() { photoSaveBlocked = false }

    #if DEBUG
    /// 调试：模拟拍摄张数 / 造示范成片（模拟器没有真相机）
    func applyDebugSeeds() {
        if DebugHarness.shouldResetRollNumber {
            rolls.resetNumbering(to: 1)
        }

        if let count = DebugHarness.simulateShots {
            for _ in 0..<count { rolls.recordShot() }
            if rolls.current.isFull {
                notice = CameraNotice(title: "本卷拍完", value: "换一卷")
            }
        }

        guard DebugHarness.shouldSeedAlbum else { return }
        // 第一卷拍 3 张，第二卷拍 2 张，成片按卷归档
        var rollIDs: [String] = []
        let first = rolls.current
        for _ in 0..<3 { rolls.recordShot() }
        rollIDs.append(first.id)
        let second = loadRoll(.fuji400)
        for _ in 0..<2 { rolls.recordShot() }
        rollIDs.append(second.id)

        let counts = [3, 2]
        for (index, rollID) in rollIDs.enumerated() {
            for n in 0..<counts[index] {
                let size = CGSize(width: 900, height: 1200)
                let renderer = UIGraphicsImageRenderer(size: size)
                let image = renderer.image { ctx in
                    let colors = [UIColor(red: 0.72, green: 0.53, blue: 0.29, alpha: 1),
                                  UIColor(red: 0.29, green: 0.48, blue: 0.44, alpha: 1)][index % 2]
                    colors.setFill()
                    ctx.fill(CGRect(origin: .zero, size: size))
                    let text = "\(index + 1)-\(n + 1)" as NSString
                    text.draw(at: CGPoint(x: 80, y: 80), withAttributes: [
                        .font: UIFont.monospacedSystemFont(ofSize: 140, weight: .bold),
                        .foregroundColor: UIColor.white.withAlphaComponent(0.85)
                    ])
                }
                AlbumStore.savePhoto(image, jpeg: image.jpegData(compressionQuality: 0.85), rollID: rollID)
            }
        }
        loadAlbum()
    }
    #endif

    /// 计数器进位（拍立得/胶片带主题用）
    /// 把当前卷的进度写给 Widget（App Group 不可用时静默失败）
    private func syncWidget() {
        let roll = rolls.current
        let ui = UIColor(canisterColor(roll.preset))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        WidgetBridge.publish(film: roll.preset.label,
                             rollNumber: roll.number,
                             used: roll.used,
                             capacity: roll.capacity,
                             colorHex: String(format: "%02X%02X%02X",
                                              Int(r * 255), Int(g * 255), Int(b * 255)))
    }

    private func bumpFrameCount() {
        defer { syncWidget() }
        frameCount += 1
        UserDefaults.standard.set(frameCount, forKey: "futurecam.frameCount")
    }

    // MARK: - 视频保存
    /// 把录制完的视频写进系统相册。
    /// 旧实现只把文件留在 tmp 就弹「视频已保存到相册」，退出 App 文件即丢 —— 提示与事实不符。
    private func saveVideoToLibrary(_ url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in
                    self?.videoSaveBlocked = true
                    self?.endBackgroundGrace()
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { success, _ in
                Task { @MainActor in
                    if success {
                        self?.showVideoSaved = true
                    } else {
                        self?.videoSaveBlocked = true
                    }
                    self?.endBackgroundGrace()
                }
            }
        }
    }

    func dismissVideoSaveBlocked() { videoSaveBlocked = false }

    // MARK: - 删除
    /// 从应用内相册删除一条媒体。
    /// 只删沙盒副本；系统「照片」里已保存的副本删不掉（我们只有 addOnly 权限），
    /// 所以确认弹窗里必须把这一点说清楚。
    func delete(_ item: AlbumItem) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            AlbumStore.delete(item)
            DispatchQueue.main.async {
                self?.albumItems.removeAll { $0.id == item.id }
                MediaThumbnailLoader.evictAll()
            }
        }
    }
    func openVideoShare() { showVideoShare = true }
    func closeVideoShare() { showVideoShare = false }
}
