import AVFoundation
import UIKit
import Photos
import Combine

/// 拍摄模式
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

/// 参数分组：曝光（ISO/快门/EV）或 白平衡（色温/色调），决定读数条显示哪一组。
enum ParamMode: String, CaseIterable, Identifiable {
    case exposure
    case whiteBalance
    var id: String { rawValue }
    var label: String { self == .exposure ? "曝光" : "白平衡" }
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
struct AlbumItem: Identifiable, Hashable {
    let id: String          // 文件名
    let url: URL            // 本地文件路径
    let kind: AlbumMediaKind
    let createdAt: Date
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

    @Published var capturedImage: UIImage?
    @Published var authorizationStatus: AVAuthorizationStatus = .notDetermined
    /// 照片写入相册失败（相册权限被拒 / 写入失败）——用于引导去系统设置。
    @Published var photoSaveBlocked = false
    /// 视频写入系统相册失败
    @Published var videoSaveBlocked = false
    /// 录制完成后的本地文件（供「分享」用，过期即失效）
    @Published var recordedVideoURL: URL?

    @Published var selectedPreset: FilmPreset = .kodakGold { didSet { controller.preset = selectedPreset } }
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
    @Published var zoomFactor: CGFloat = 1
    /// 是否前摄
    @Published var isFrontCamera = false
    /// 胶片计数器（跨启动累计，暗房工单 / 胶片带主题的主视觉）
    @Published var frameCount: Int = UserDefaults.standard.integer(forKey: "filmcam.frameCount")

    // 手动参数（UI 状态，device 内部会 clamp 到支持范围）
    @Published var iso: Double = 200
    @Published var shutterSeconds: Double = 1.0 / 60.0
    @Published var bias: Double = 0
    @Published var temperature: Double = 5500
    @Published var tint: Double = 0
    @Published var autoExposure = true
    @Published var autoWB = true

    // MARK: - 取景辅助与信息架构状态（对标飓风相机）
    /// 当前参数分组（药丸行显示曝光组还是白平衡组）
    @Published var paramMode: ParamMode = .exposure
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
        refreshStorage()
        loadAlbum()
        controller.onPreview = { [weak self] image in
            Task { @MainActor in self?.handlePreviewFrame(image) }
        }
        controller.onPhoto = { [weak self] image in
            Task { @MainActor in
                self?.showDoubleExposureFirst = false
                self?.capturedImage = image
                self?.bumpFrameCount()
                if self?.mode == .doubleExposure, self?.doubleExposureStep == 1 {
                    self?.doubleExposureStep = 2
                }
                self?.saveToLibrary(image)
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
            }
        }
        controller.onVideoSaved = { [weak self] url in
            Task { @MainActor in
                self?.isRecording = false
                self?.recordedVideoURL = url
                // 本地相册（应用内）立刻可见；同时真写进系统相册，
                // 成功后才提示「已保存」，失败走拦截引导
                self?.persistVideoLocally(url)
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

    /// 进入后台：主动停会话（系统也会停，但我们自己要能恢复）
    func pauseCamera() {
        controller.pause()
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
    private func persistLocally(_ image: UIImage) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let item = AlbumStore.savePhoto(image) else { return }
            DispatchQueue.main.async {
                if self?.albumItems.firstIndex(where: { $0.id == item.id }) == nil {
                    self?.albumItems.insert(item, at: 0)
                }
            }
        }
    }

    /// 录制完成的视频：复制进相册目录（tmp 会被系统清掉），并让「分享」指向本地副本
    private func persistVideoLocally(_ tmpURL: URL) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let item = AlbumStore.saveVideo(from: tmpURL)
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
    func capturePhoto() { controller.capture() }

    /// 前后摄切换（录制中不允许，避免把一条视频写成两种镜头）
    func switchCamera() {
        guard !isRecording else { return }
        controller.switchCamera()   // 成功后由 onCameraSwitched 回写 isFrontCamera
    }

    /// 点按对焦 / 长按锁定。point 为取景器内的局部坐标（pt）。
    func focus(at point: CGPoint, in size: CGSize, lock: Bool) {
        guard let aspect = previewAspect, size.width > 0, size.height > 0 else { return }
        // 预览图以 scaleAspectFill 铺满容器：先还原成图片内归一化坐标
        let scale = max(size.width / aspect, size.height / 1)
        let drawnW = aspect * scale
        let drawnH = scale
        let originX = (size.width - drawnW) / 2
        let originY = (size.height - drawnH) / 2
        let u = min(max((point.x - originX) / drawnW, 0), 1)
        let v = min(max((point.y - originY) / drawnH, 0), 1)
        // 竖屏图像坐标 → 传感器原生横图坐标（图像顺时针转了 90°）
        // 前摄预览是镜像过的，横向要再反一次
        let devicePoint = isFrontCamera
            ? CGPoint(x: v, y: u)
            : CGPoint(x: v, y: 1 - u)
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
        capturedImage = nil
        if doubleExposureStep == 2 { doubleExposureStep = 0 }
    }

    func clearVideoSaved() { showVideoSaved = false; recordedVideoURL = nil }
    func clearDoubleExposureFirst() { showDoubleExposureFirst = false }

    private func modeChanged(_ m: CameraMode) {
        controller.setDoubleExposureEnabled(m == .doubleExposure)
        if m != .doubleExposure { doubleExposureStep = 0 }
        if isRecording { isRecording = false; controller.stopRecording() }
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

    /// 工具停靠栏切换参数分组；若当前展开的滑杆不属于新组则收起。
    func setParamMode(_ mode: ParamMode) {
        paramMode = mode
        let isExposureParam = (activeParam == .iso || activeParam == .shutter || activeParam == .bias)
        let needsSwitch = (mode == .exposure) != isExposureParam
        if needsSwitch {
            activeParam = (mode == .exposure) ? .iso : .temperature
        }
    }

    // MARK: - 保存到相册
    private func saveToLibrary(_ image: UIImage) {
        // 本地相册（应用内）始终保存，不依赖系统相册权限
        persistLocally(image)
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in
                    self?.photoSaveBlocked = true   // 相册权限被拒：引导去设置
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, _ in
                Task { @MainActor in
                    // 成功不弹窗（应用内相册里已经能看到），失败才引导
                    if !success { self?.photoSaveBlocked = true }
                }
            }
        }
    }

    func dismissPhotoSaveBlocked() { photoSaveBlocked = false }

    /// 计数器进位（拍立得/胶片带主题用）
    private func bumpFrameCount() {
        frameCount += 1
        UserDefaults.standard.set(frameCount, forKey: "filmcam.frameCount")
    }

    // MARK: - 视频保存
    /// 把录制完的视频写进系统相册。
    /// 旧实现只把文件留在 tmp 就弹「视频已保存到相册」，退出 App 文件即丢 —— 提示与事实不符。
    private func saveVideoToLibrary(_ url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in self?.videoSaveBlocked = true }
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
