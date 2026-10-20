import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import UIKit
import os

/// 后台相机引擎：持有 AVCaptureSession，所有可变状态限制在串行队列或锁内。
/// 负责实时取流滤镜、拍照、手动参数、双重曝光、视频录制（实时 LUT）。
/// 标 @unchecked Sendable：由我们保证线程安全（session 在 sessionQueue 串行访问，
/// 帧处理在 processingQueue 串行访问，preset/base/录制状态用锁或 unsafe 保护）。
final class CaptureSessionController: NSObject, @unchecked Sendable,
    AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCaptureAudioDataOutputSampleBufferDelegate,
    AVCapturePhotoCaptureDelegate {

    nonisolated(unsafe) private let session = AVCaptureSession()
    nonisolated(unsafe) private let videoOutput = AVCaptureVideoDataOutput()
    nonisolated(unsafe) private let audioOutput = AVCaptureAudioDataOutput()
    nonisolated(unsafe) private let photoOutput = AVCapturePhotoOutput()
    nonisolated(unsafe) private var cameraInput: AVCaptureDeviceInput?
    nonisolated(unsafe) private var audioInput: AVCaptureDeviceInput?
    nonisolated(unsafe) private var audioAttached = false
    nonisolated(unsafe) private var audioOutputAttached = false
    private let sessionQueue = DispatchQueue(label: "com.futurecam.session")
    private let processingQueue = DispatchQueue(label: "com.futurecam.processing")
    private let ciContext = CIContext()
    private let presetLock = OSAllocatedUnfairLock<FilmPreset>(initialState: .kodakGold)
    nonisolated(unsafe) private var isConfigured = false
    nonisolated(unsafe) private var videoDevice: AVCaptureDevice?
    /// 当前使用的摄像头方向（前后摄切换用）
    nonisolated(unsafe) private var currentPosition: AVCaptureDevice.Position = .back
    /// 是否前摄（sessionQueue 写 / processingQueue 读，故用锁）
    private let frontLock = OSAllocatedUnfairLock<Bool>(initialState: false)
    private var isFront: Bool { frontLock.withLock { $0 } }
    /// 会话中断 / 运行时错误观察者只注册一次
    nonisolated(unsafe) private var observingSession = false

    // 双重曝光
    nonisolated(unsafe) private var doubleExposureEnabled = false
    nonisolated(unsafe) private var doubleExposureBase: UIImage?

    // 视频录制
    nonisolated(unsafe) private var assetWriter: AVAssetWriter?
    nonisolated(unsafe) private var videoInput: AVAssetWriterInput?
    nonisolated(unsafe) private var audioWriterInput: AVAssetWriterInput?
    nonisolated(unsafe) private var adapter: AVAssetWriterInputPixelBufferAdaptor?
    nonisolated(unsafe) private var recording = false
    /// 拍照闪光模式（UI 循环 off/auto/on）
    nonisolated(unsafe) private var flashMode: AVCaptureDevice.FlashMode = .off
    nonisolated(unsafe) private var sessionStarted = false
    nonisolated(unsafe) private var recordedURL: URL?

    var onPreview: (@Sendable (UIImage) -> Void)?
    /// base 是「只过了胶片、没叠调色」的底，用于拍完再换调色
    var onPhoto: (@Sendable (UIImage, Data?, UIImage) -> Void)?
    var onDoubleExposureFirstShot: (@Sendable (UIImage) -> Void)?
    var onVideoSaved: (@Sendable (URL) -> Void)?
    /// 切换摄像头成功后回调真实方向（true = 前摄），让 UI 与硬件状态保持一致
    var onCameraSwitched: (@Sendable (Bool) -> Void)?

    var preset: FilmPreset {
        get { presetLock.withLock { $0 } }
        set { presetLock.withLock { $0 = newValue } }
    }

    /// 叠在胶片之上的调色预设（可选）
    var lookPreset: FilmPreset? {
        get { traitsLock.lock(); defer { traitsLock.unlock() }; return lookStorage }
        set { traitsLock.lock(); lookStorage = newValue; traitsLock.unlock() }
    }

    /// 当前这卷的随机性格与颗粒参数（由主线程写入，两条渲染路径读取）
    var rollTraits: RollTraits? {
        get { traitsLock.lock(); defer { traitsLock.unlock() }; return traitsStorage }
        set { traitsLock.lock(); traitsStorage = newValue; traitsLock.unlock() }
    }

    var grain: GrainSettings {
        get { traitsLock.lock(); defer { traitsLock.unlock() }; return grainStorage }
        set { traitsLock.lock(); grainStorage = newValue; traitsLock.unlock() }
    }

    private let traitsLock = NSLock()
    private var traitsStorage: RollTraits?
    private var grainStorage: GrainSettings = .none
    private var lookStorage: FilmPreset?

    // MARK: - 启动
    func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            // 会话所有权拿回来：否则 AVFoundation 会锁成 playAndRecord，静音键就管不住齿轮声
            self.session.automaticallyConfiguresApplicationAudioSession = false
            AudioRoute.capture()   // 麦克风输入只有在 playAndRecord 下才挂得上
            self.configureSession()
            self.observeSessionIfNeeded()
            if !self.session.isRunning { self.session.startRunning() }
            self.refreshAudioRoute()   // 没挂麦克风就交还静音键
        }
    }

    /// 进后台 / 系统打断时主动停会话，省电并让系统能释放相机。
    func pause() {
        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    /// 回前台恢复会话。注意 stopRunning 之后必须重新 startRunning，
    /// 否则真机切回来是一片黑屏（旧代码 didStartCamera 一次性锁死，没有恢复路径）。
    func resume() {
        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured, !self.session.isRunning else { return }
            self.refreshAudioRoute()
            self.session.startRunning()
            self.refreshAudioRoute()
        }
    }

    /// 来电 / 其他 App 抢占 / 媒体服务重启后自动恢复。
    private func observeSessionIfNeeded() {
        guard !observingSession else { return }
        observingSession = true
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(sessionNeedsRestart),
                       name: .AVCaptureSessionRuntimeError, object: session)
        nc.addObserver(self, selector: #selector(sessionNeedsRestart),
                       name: .AVCaptureSessionInterruptionEnded, object: session)
        nc.addObserver(self, selector: #selector(sessionWasInterrupted),
                       name: .AVCaptureSessionWasInterrupted, object: session)
    }

    @objc private func sessionNeedsRestart(_ note: Notification) {
        resume()
    }

    /// 来电/被打断：先把录制正常收尾，别留一个没封口的 mov
    @objc private func sessionWasInterrupted(_ note: Notification) {
        stopRecording()
    }

    private func configureSession() {
        guard !isConfigured else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // 广角后置优先，兜底任意视频设备（部分机型/占用时 default(.builtInWideAngleCamera) 可能为 nil）
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video)
        guard let device, let input = try? AVCaptureDeviceInput(device: device) else {
            NSLog("[FutureCam] 无法获取相机设备，会话未配置")
            return
        }
        videoDevice = device
        currentPosition = device.position
        let isFrontDevice = device.position == .front
        frontLock.withLock { $0 = isFrontDevice }
        if session.canAddInput(input) {
            session.addInput(input)
            cameraInput = input
        } else {
            NSLog("[FutureCam] 无法加入相机输入")
            return
        }

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)

        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        // 默认是 .balanced，白白丢掉一部分计算摄影画质
        photoOutput.maxPhotoQualityPrioritization = .quality

        // 音频输出常挂：没有输入时不产生数据，也不会把会话类别锁进 playAndRecord。
        // 麦克风输入只在视频模式下才挂（见 setWantsAudioInput），
        // 音频对象在拍照模式下一个都不挂：只要会话里有麦克风输入，
        // 系统就会把类别锁在 playAndRecord，静音键就管不住齿轮声了。

        isConfigured = true
    }

    // MARK: - 麦克风挂载

    /// 挂着麦克风就必须是 .playAndRecord，没挂就交还 .ambient 让静音键生效。
    private func refreshAudioRoute() {
        if audioAttached { AudioRoute.capture() } else { AudioRoute.idle() }
        #if DEBUG
        print("[AudioRoute] mic=\(audioAttached) category=\(AVAudioSession.sharedInstance().category.rawValue)")
        #endif
    }

    /// 视频模式才把麦克风挂到会话上：一旦挂着，系统会强制 playAndRecord，
    /// 那个类别不跟随静音键；拍照模式下要保持 .ambient。
    func setWantsAudioInput(_ wants: Bool) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if wants { self.attachAudioInput() } else { self.detachAudioInput() }
        }
    }

    private func attachAudioInput() {
        guard !audioAttached else { return }
        AudioRoute.capture()
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
              let device = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        let started = CACurrentMediaTime()
        session.beginConfiguration()
        if session.canAddInput(input) {
            session.addInput(input)
            audioInput = input
            audioAttached = true
            audioOutput.setSampleBufferDelegate(self, queue: processingQueue)
            if session.canAddOutput(audioOutput) {
                session.addOutput(audioOutput)
                audioOutputAttached = true
            }
        }
        session.commitConfiguration()
        #if DEBUG
        print(String(format: "[AudioRoute] 麦克风挂载 %@ %.0f ms",
                     audioAttached ? "成功" : "失败", (CACurrentMediaTime() - started) * 1000))
        #endif
    }

    private func detachAudioInput() {
        guard !recording, audioAttached, let audioInput else { return }
        session.beginConfiguration()
        session.removeInput(audioInput)
        if audioOutputAttached { session.removeOutput(audioOutput) }
        session.commitConfiguration()
        self.audioInput = nil
        audioAttached = false
        audioOutputAttached = false
        AudioRoute.idle()
    }

    // MARK: - 前后摄切换
    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured, !self.recording else { return }
            let target: AVCaptureDevice.Position = self.currentPosition == .back ? .front : .back
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: target),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }

            self.session.beginConfiguration()
            let previous = self.cameraInput
            if let previous { self.session.removeInput(previous) }
            guard self.session.canAddInput(input) else {
                // 回滚：切换失败时保持原摄像头可用
                if let previous, self.session.canAddInput(previous) { self.session.addInput(previous) }
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)
            self.cameraInput = input
            self.videoDevice = device
            self.currentPosition = target
            self.session.commitConfiguration()

            self.frontLock.withLock { $0 = (target == .front) }
            self.onCameraSwitched?(target == .front)
            // 换镜头后旧的构图参数不再成立：清合成底图、重置对焦与变焦
            self.doubleExposureBase = nil
            self.resetFocusAndZoom(on: device)
        }
    }

    private func resetFocusAndZoom(on device: AVCaptureDevice) {
        guard (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        device.videoZoomFactor = device.minAvailableVideoZoomFactor
    }

    // MARK: - 拍照
    func capture() {
        guard session.isRunning else { return }
        let settings = AVCapturePhotoSettings()
        // 当前镜头不支持该闪光模式时退回关闭，避免 capturePhoto 抛异常
        let wanted = flashMode
        settings.flashMode = photoOutput.supportedFlashModes.contains(wanted) ? wanted : .off
        settings.photoQualityPrioritization = .quality
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    /// 拍照闪光模式
    func setFlashMode(_ mode: AVCaptureDevice.FlashMode) {
        flashMode = mode
    }

    /// 视频补光（手电）
    func setTorch(_ on: Bool) {
        guard let device = videoDevice, device.hasTorch else { return }
        guard (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }
        device.torchMode = on ? .on : .off
    }

    // MARK: - 手动参数
    func setManualExposure(iso: Float, shutterSeconds: Double, bias: Float) {
        guard let device = videoDevice else { return }
        do {
            try device.lockForConfiguration()
            let cISO = min(max(iso, device.activeFormat.minISO), device.activeFormat.maxISO)
            var dur = CMTime(seconds: shutterSeconds, preferredTimescale: 1000)
            dur = CMTimeClampToRange(dur,
                                     range: CMTimeRange(start: device.activeFormat.minExposureDuration,
                                                        end: device.activeFormat.maxExposureDuration))
            let cBias = min(max(bias, device.minExposureTargetBias), device.maxExposureTargetBias)
            device.setExposureModeCustom(duration: dur, iso: cISO, completionHandler: nil)
            device.setExposureTargetBias(cBias, completionHandler: nil)
            device.unlockForConfiguration()
        } catch {}
    }

    func setAutoExposure() {
        guard let device = videoDevice else { return }
        do { try device.lockForConfiguration()
             device.exposureMode = .continuousAutoExposure
             device.unlockForConfiguration() } catch {}
    }

    func setWhiteBalance(temperature: Float, tint: Float) {
        guard let device = videoDevice else { return }
        do {
            try device.lockForConfiguration()
            let vals = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: temperature, tint: tint)
            let desired = device.deviceWhiteBalanceGains(for: vals)
            let maxGain = device.maxWhiteBalanceGain
            let clamped = AVCaptureDevice.WhiteBalanceGains(
                redGain: min(max(desired.redGain, 1), maxGain),
                greenGain: min(max(desired.greenGain, 1), maxGain),
                blueGain: min(max(desired.blueGain, 1), maxGain))
            device.setWhiteBalanceModeLocked(with: clamped, completionHandler: nil)
            device.unlockForConfiguration()
        } catch {}
    }

    func setAutoWhiteBalance() {
        guard let device = videoDevice else { return }
        do { try device.lockForConfiguration()
             device.whiteBalanceMode = .continuousAutoWhiteBalance
             device.unlockForConfiguration() } catch {}
    }

    func setAutoFocus() {
        guard let device = videoDevice else { return }
        do { try device.lockForConfiguration()
             device.focusMode = .continuousAutoFocus
             device.unlockForConfiguration() } catch {}
    }

    // MARK: - 点按对焦 / 锁定 / 变焦
    /// - Parameters:
    ///   - point: 归一化设备坐标（传感器原生横图的 (0,0) 在左上）
    ///   - lock: true = 长按锁定 AE/AF（.locked），false = 单次自动对焦
    ///   - touchExposure: 手动曝光模式下不抢曝光控制，只对焦
    func focus(at point: CGPoint, lock: Bool, touchExposure: Bool) {
        guard let device = videoDevice else { return }
        do {
            try device.lockForConfiguration()
            let p = CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))

            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = p
                let mode: AVCaptureDevice.FocusMode = lock ? .locked : .autoFocus
                if device.isFocusModeSupported(mode) { device.focusMode = mode }
            }
            if touchExposure, device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = p
                let mode: AVCaptureDevice.ExposureMode = lock ? .locked : .autoExpose
                if device.isExposureModeSupported(mode) { device.exposureMode = mode }
            }
            device.unlockForConfiguration()
        } catch {}
    }

    /// 解锁 AE/AF，回到连续自动
    func unlockFocusAndExposure() {
        guard let device = videoDevice else { return }
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        } catch {}
    }

    /// 捏合变焦：factor 为绝对倍率（1.0 = 1×），内部 clamp 到设备能力
    func setZoom(_ factor: CGFloat) {
        guard let device = videoDevice else { return }
        let maxZ = min(device.maxAvailableVideoZoomFactor, 8)
        let clamped = min(max(factor, device.minAvailableVideoZoomFactor), maxZ)
        // 变焦不动画面结构，走 ramp 更顺滑；直接赋值在捏合高频回调下会抖动
        if abs(device.videoZoomFactor - clamped) < 0.01 { return }
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
        } catch {}
    }

    /// 设备支持的倍率上限（UI 用来画指示条）
    var maxZoomFactor: CGFloat {
        guard let device = videoDevice else { return 8 }
        return min(device.maxAvailableVideoZoomFactor, 8)
    }

    func setDoubleExposureEnabled(_ enabled: Bool) {
        doubleExposureEnabled = enabled
        if !enabled { doubleExposureBase = nil }
    }

    // MARK: - 视频录制（实时 LUT 写入）
    func startRecording() {
        // 录音期间必须是 playAndRecord，麦克风才有数据
        AudioRoute.capture()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("futurecam_\(Int(Date().timeIntervalSince1970)).mov")
        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return }
        let w = 1080, h = 1920
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: w, AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 12_000_000]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        let adapt = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: w,
                kCVPixelBufferHeightKey as String: h
            ])
        writer.add(input)

        // 音频轨（若会话已接入麦克风则写入 AAC）
        if audioAttached {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128000
            ]
            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            aInput.expectsMediaDataInRealTime = true
            if writer.canAdd(aInput) { writer.add(aInput) }
            audioWriterInput = aInput
        }

        writer.startWriting()
        assetWriter = writer; videoInput = input; adapter = adapt
        recordedURL = url; sessionStarted = false; recording = true
    }

    func stopRecording() {
        guard recording else { return }
        recording = false
        videoInput?.markAsFinished()
        audioWriterInput?.markAsFinished()
        assetWriter?.finishWriting { [weak self] in
            guard let self, let url = self.recordedURL else { return }
            self.assetWriter = nil; self.videoInput = nil; self.audioWriterInput = nil; self.adapter = nil
            self.onVideoSaved?(url)
            self.refreshAudioRoute()
        }
    }

    private func startSessionIfNeeded(at time: CMTime) {
        guard recording, let assetWriter, !sessionStarted else { return }
        assetWriter.startSession(atSourceTime: time)
        sessionStarted = true
    }

    private func writeVideoFrame(_ ciImage: CIImage, time: CMTime) {
        guard recording, let adapter, let input = videoInput, input.isReadyForMoreMediaData else { return }
        guard let pool = adapter.pixelBufferPool else { return }
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
        guard let pixelBuffer = pb else { return }
        ciContext.render(ciImage, to: pixelBuffer)
        startSessionIfNeeded(at: time)
        adapter.append(pixelBuffer, withPresentationTime: time)
    }

    private func writeAudioSample(_ sampleBuffer: CMSampleBuffer) {
        guard recording, let audioWriterInput, audioWriterInput.isReadyForMoreMediaData else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        startSessionIfNeeded(at: time)
        audioWriterInput.append(sampleBuffer)
    }

    // MARK: - 渲染工具
    /// 左右镜像（在已转正的图像空间里执行，保证自拍"照镜子"而不是上下颠倒）
    private func mirroredHorizontally(_ image: CIImage) -> CIImage {
        let extent = image.extent
        return image
            .transformed(by: CGAffineTransform(scaleX: -1, y: 1))
            .transformed(by: CGAffineTransform(translationX: extent.minX + extent.maxX, y: 0))
    }
    private func renderToUIImage(_ ciImage: CIImage) -> UIImage? {
        let extent = ciImage.extent.integral
        guard let cg = ciContext.createCGImage(ciImage, from: extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// 给成片加白色边框 + 拍摄日期戳（拍立得风：上下细边、底部粗边）
    /// 加白色边框 + 日期戳。换调色重渲染后也要走一遍，否则边框会丢
    static func stampImage(_ image: UIImage) -> UIImage {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd  HH:mm"
        let dateStr = formatter.string(from: Date())

        let w = image.size.width
        let h = image.size.height
        let side = w * 0.06          // 上/左/右细白边
        let bottom = w * 0.20        // 底部粗白边（拍立得标志）
        let totalSize = CGSize(width: w + side * 2, height: h + side + bottom)
        let renderer = UIGraphicsImageRenderer(size: totalSize)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: totalSize))
            image.draw(in: CGRect(x: side, y: side, width: w, height: h))
            let font = UIFont.monospacedDigitSystemFont(ofSize: w * 0.05, weight: .medium)
            let attrs: [NSAttributedString.Key: Any] = [.font: font,
                                                        .foregroundColor: UIColor.black]
            let text = dateStr as NSString
            let textSize = text.size(withAttributes: attrs)
            let point = CGPoint(x: (totalSize.width - textSize.width) / 2,
                               y: side + h + (bottom - textSize.height) / 2)
            text.draw(at: point, withAttributes: attrs)
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if output === audioOutput {
            writeAudioSample(sampleBuffer)
            return
        }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let oriented = CIImage(cvImageBuffer: pixelBuffer).oriented(.right)
        let source = isFront ? mirroredHorizontally(oriented) : oriented
        var filtered = FilmFilter.apply(source, preset: preset, traits: rollTraits)
        if let look = lookPreset, let grade = look.grade {
            filtered = FilmFilter.applyGrade(filtered, grade)
        }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        writeVideoFrame(filtered, time: pts)
        guard let uiImage = renderToUIImage(filtered) else { return }
        onPreview?(uiImage)
    }

    // MARK: - AVCapturePhotoCaptureDelegate
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data),
              let cg = image.cgImage else { return }
        // 关键：JPEG 的像素是传感器原生（横向），方向信息只在 EXIF 里；
        // CIImage(cgImage:) 会忽略 EXIF，必须像预览那样补一次 .right 旋转，
        // 否则成片是横躺的（显影页/相册里"横竖别扭"的根因）。
        let oriented = CIImage(cgImage: cg).oriented(.right)
        let ci = isFront ? mirroredHorizontally(oriented) : oriented
        let base = FilmFilter.apply(ci, preset: preset, traits: rollTraits, grain: grain)
        guard let baseImage = renderToUIImage(base) else { return }
        var filtered = base
        if let look = lookPreset, let grade = look.grade {
            filtered = FilmFilter.applyGrade(filtered, grade)
        }
        guard let filteredImage = renderToUIImage(filtered) else { return }

        if doubleExposureEnabled {
            if let base = doubleExposureBase {
                let blended = FilmFilter.doubleExposure(base: base, overlay: filteredImage)
                doubleExposureBase = nil
                deliver(Self.stampImage(blended), metadata: photo.metadata, base: baseImage)
            } else {
                doubleExposureBase = filteredImage
                onDoubleExposureFirstShot?(filteredImage)
            }
        } else {
            deliver(Self.stampImage(filteredImage), metadata: photo.metadata, base: baseImage)
        }
    }

    /// 把成片重新编码成 JPEG，并把原始 EXIF 带回去。
    /// 旧实现直接传 UIImage 给 Photos，重渲染后元数据全丢（相册里看不到机型/ISO/GPS）。
    private func deliver(_ image: UIImage, metadata: [String: Any], base: UIImage) {
        onPhoto?(image, jpegWithMetadata(image, metadata: metadata), base)
    }

    private func jpegWithMetadata(_ image: UIImage, metadata: [String: Any]) -> Data? {
        PhotoEncoding.jpeg(image, metadata: metadata)
    }
}
