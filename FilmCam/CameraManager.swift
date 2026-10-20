import AVFoundation
import UIKit
import Photos
import Combine

/// 参数分组：曝光（ISO/快门/EV）或 白平衡（色温/色调），决定药丸行显示哪一组。
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

/// 主线程相机视图模型：只持有 UI 状态，把相机硬件操作委托给后台 CaptureSessionController。
@MainActor
final class CameraManager: NSObject, ObservableObject {
    // MARK: - 预览
    /// 高频预览帧走 Combine 直连预览视图，刻意【不】用 @Published：
    /// 否则每帧都会重算整棵 SwiftUI 视图树，真机上会造成明显卡顿、甚至看起来"点了没反应"。
    let previewFrames = PassthroughSubject<UIImage, Never>()
    /// 是否已收到首帧（低频状态，用 @Published 安全）
    @Published var hasPreview = false
    /// 已授权但迟迟收不到帧（相机被占用 / 初始化失败）
    @Published var previewStalled = false

    @Published var capturedImage: UIImage?
    @Published var authorizationStatus: AVAuthorizationStatus = .notDetermined
    @Published var isSaving = false
    @Published var saveConfirmed = false
    /// 照片写入相册失败（相册权限被拒 / 写入失败）——用于引导去系统设置。
    @Published var photoSaveBlocked = false

    @Published var selectedPreset: FilmPreset = .kodakGold { didSet { controller.preset = selectedPreset } }
    @Published var mode: CameraMode = .photo { didSet { modeChanged(mode) } }
    @Published var doubleExposureStep: Int = 0
    @Published var isRecording = false
    @Published var recordedVideoURL: URL?
    @Published var showVideoSaved = false

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
    @Published var activeParam: ParamKey?
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
        controller.onPreview = { [weak self] image in
            Task { @MainActor in self?.handlePreviewFrame(image) }
        }
        controller.onPhoto = { [weak self] image in
            Task { @MainActor in
                self?.capturedImage = image
                if self?.mode == .doubleExposure, self?.doubleExposureStep == 1 {
                    self?.doubleExposureStep = 2
                }
                self?.saveToLibrary(image)
            }
        }
        controller.onDoubleExposureFirstShot = { [weak self] image in
            Task { @MainActor in
                self?.doubleExposureStep = 1
                self?.capturedImage = image
            }
        }
        controller.onVideoSaved = { [weak self] url in
            Task { @MainActor in
                self?.isRecording = false
                self?.recordedVideoURL = url
                self?.showVideoSaved = true
            }
        }
    }

    // MARK: - 预览帧
    private func handlePreviewFrame(_ image: UIImage) {
        if !hasPreview {
            hasPreview = true
            previewStalled = false
            watchdog?.cancel(); watchdog = nil
        }
        previewFrames.send(image)
    }

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

    /// 回到前台时重新读取权限（用户可能刚在「设置」里改过），并补启动。
    func refreshAuthorization() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status != authorizationStatus { authorizationStatus = status }
        if status == .authorized { startCameraIfNeeded() }
        refreshStorage()
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
    }

    // MARK: - 药丸 / 参数面板交互
    /// 药丸点选：同组内切换焦点，再点一次收起滑杆。
    func toggleParam(_ key: ParamKey) {
        activeParam = (activeParam == key) ? nil : key
    }

    /// 工具停靠栏切换参数分组；若当前展开的滑杆不属于新组则收起。
    func setParamMode(_ mode: ParamMode) {
        paramMode = mode
        guard let active = activeParam else { return }
        let isExposureParam = (active == .iso || active == .shutter || active == .bias)
        if (mode == .exposure) != isExposureParam { activeParam = nil }
    }

    // MARK: - 保存到相册
    private func saveToLibrary(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in
                    self?.isSaving = false
                    self?.photoSaveBlocked = true   // 相册权限被拒：引导去设置
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, _ in
                Task { @MainActor in
                    self?.isSaving = false
                    self?.saveConfirmed = success
                    if !success { self?.photoSaveBlocked = true }
                }
            }
        }
    }

    func dismissPhotoSaveBlocked() { photoSaveBlocked = false }
}
