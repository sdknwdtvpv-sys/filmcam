import AVFoundation
import CoreImage
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
    nonisolated(unsafe) private var audioInput: AVCaptureDeviceInput?
    nonisolated(unsafe) private var hasAudio = false
    private let sessionQueue = DispatchQueue(label: "com.filmcam.session")
    private let processingQueue = DispatchQueue(label: "com.filmcam.processing")
    private let ciContext = CIContext()
    private let presetLock = OSAllocatedUnfairLock<FilmPreset>(initialState: .kodakGold)
    nonisolated(unsafe) private var isConfigured = false
    nonisolated(unsafe) private var videoDevice: AVCaptureDevice?

    // 双重曝光
    nonisolated(unsafe) private var doubleExposureEnabled = false
    nonisolated(unsafe) private var doubleExposureBase: UIImage?

    // 视频录制
    nonisolated(unsafe) private var assetWriter: AVAssetWriter?
    nonisolated(unsafe) private var videoInput: AVAssetWriterInput?
    nonisolated(unsafe) private var audioWriterInput: AVAssetWriterInput?
    nonisolated(unsafe) private var adapter: AVAssetWriterInputPixelBufferAdaptor?
    nonisolated(unsafe) private var recording = false
    nonisolated(unsafe) private var sessionStarted = false
    nonisolated(unsafe) private var recordedURL: URL?

    var onPreview: (@Sendable (UIImage) -> Void)?
    var onPhoto: (@Sendable (UIImage) -> Void)?
    var onDoubleExposureFirstShot: (@Sendable (UIImage) -> Void)?
    var onVideoSaved: (@Sendable (URL) -> Void)?

    var preset: FilmPreset {
        get { presetLock.withLock { $0 } }
        set { presetLock.withLock { $0 = newValue } }
    }

    // MARK: - 启动
    func configureAndStart() {
        sessionQueue.async { [weak self] in
            self?.configureSession()
            self?.session.startRunning()
        }
    }

    private func configureSession() {
        guard !isConfigured else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // 广角后置优先，兜底任意视频设备（部分机型/占用时 default(.builtInWideAngleCamera) 可能为 nil）
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video)
        guard let device, let input = try? AVCaptureDeviceInput(device: device) else {
            NSLog("[FilmCam] 无法获取相机设备，会话未配置")
            return
        }
        videoDevice = device
        if session.canAddInput(input) {
            session.addInput(input)
        } else {
            NSLog("[FilmCam] 无法加入相机输入")
            return
        }

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)

        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }

        // 音频（需麦克风授权；未授权则静音录制）
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
           let audioDevice = AVCaptureDevice.default(for: .audio),
           let aInput = try? AVCaptureDeviceInput(device: audioDevice),
           session.canAddInput(aInput) {
            session.addInput(aInput)
            audioInput = aInput
            audioOutput.setSampleBufferDelegate(self, queue: processingQueue)
            if session.canAddOutput(audioOutput) { session.addOutput(audioOutput) }
            hasAudio = true
        }

        isConfigured = true
    }

    // MARK: - 拍照
    func capture() {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        photoOutput.capturePhoto(with: settings, delegate: self)
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

    func setDoubleExposureEnabled(_ enabled: Bool) {
        doubleExposureEnabled = enabled
        if !enabled { doubleExposureBase = nil }
    }

    // MARK: - 视频录制（实时 LUT 写入）
    func startRecording() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("filmcam_\(Int(Date().timeIntervalSince1970)).mov")
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
        if hasAudio {
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
    private func renderToUIImage(_ ciImage: CIImage) -> UIImage? {
        let extent = ciImage.extent.integral
        guard let cg = ciContext.createCGImage(ciImage, from: extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// 给成片加白色边框 + 拍摄日期戳（拍立得风）
    private func stampImage(_ image: UIImage) -> UIImage {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd  HH:mm"
        let dateStr = formatter.string(from: Date())

        let margin = image.size.width * 0.06
        let totalSize = CGSize(width: image.size.width + margin * 2,
                               height: image.size.height + margin * 2)
        let renderer = UIGraphicsImageRenderer(size: totalSize)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: totalSize))
            image.draw(in: CGRect(x: margin, y: margin,
                                  width: image.size.width, height: image.size.height))
            let font = UIFont.monospacedDigitSystemFont(ofSize: margin * 0.42, weight: .medium)
            let attrs: [NSAttributedString.Key: Any] = [.font: font,
                                                        .foregroundColor: UIColor.black]
            let text = dateStr as NSString
            let textSize = text.size(withAttributes: attrs)
            let point = CGPoint(x: (totalSize.width - textSize.width) / 2,
                               y: totalSize.height - margin * 0.8 - textSize.height)
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
        let ciImage = CIImage(cvImageBuffer: pixelBuffer).oriented(.right)
        let filtered = FilmFilter.apply(ciImage, preset: preset)
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
        let ci = CIImage(cgImage: cg)
        let filtered = FilmFilter.apply(ci, preset: preset)
        guard let filteredImage = renderToUIImage(filtered) else { return }

        if doubleExposureEnabled {
            if let base = doubleExposureBase {
                let blended = FilmFilter.doubleExposure(base: base, overlay: filteredImage)
                doubleExposureBase = nil
                onPhoto?(stampImage(blended))
            } else {
                doubleExposureBase = filteredImage
                onDoubleExposureFirstShot?(filteredImage)
            }
        } else {
            onPhoto?(stampImage(filteredImage))
        }
    }
}
