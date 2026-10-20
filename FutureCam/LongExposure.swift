import CoreImage
import Vision

/// 长曝光积分器：把许多短帧对齐后平均，等效于一次更长曝光。
/// 设备单帧上限约 1 秒，超过就只能靠堆栈——顺便把噪点也平均掉。
final class LongExposureIntegrator {
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private var accumulator: CIImage?
    private var reference: CIImage?
    private var referenceCG: CGImage?
    private(set) var frames = 0
    /// 因抖动过大被丢弃的帧数（三脚架提示用）
    private(set) var rejected = 0

    var frameCount: Int { frames }

    func begin() {
        accumulator = nil
        reference = nil
        referenceCG = nil
        frames = 0
        rejected = 0
    }

    /// 喂一帧。返回是否被采纳。
    @discardableResult
    func add(_ frame: CIImage) -> Bool {
        let cropped = frame.cropped(to: frame.extent)

        guard let acc = accumulator, let refCG = referenceCG else {
            // 第一帧作为对齐基准
            accumulator = cropped
            reference = cropped
            referenceCG = context.createCGImage(cropped, from: cropped.extent)
            frames = 1
            return true
        }

        // 平移对齐到第一帧：手持长曝光的糊主要是平移
        let aligned = align(cropped, to: refCG) ?? cropped
        frames += 1
        // 以 1/n 的权重把新帧并进去，等价于算术平均
        accumulator = blend(acc, aligned, weight: 1.0 / CGFloat(frames))
        return true
    }

    /// 收工，返回平均后的画面
    func finish() -> CIImage? {
        accumulator
    }

    // MARK: - 内部

    private func blend(_ a: CIImage, _ b: CIImage, weight: CGFloat) -> CIImage {
        guard let f = CIFilter(name: "CIDissolveTransition") else { return b }
        f.setValue(a, forKey: kCIInputImageKey)
        f.setValue(b, forKey: kCIInputTargetImageKey)
        f.setValue(weight, forKey: kCIInputTimeKey)
        return (f.outputImage ?? b).cropped(to: a.extent)
    }

    private func align(_ image: CIImage, to reference: CGImage) -> CIImage? {
        guard let cg = context.createCGImage(image, from: image.extent) else { return nil }
        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: reference, options: [:])
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first as? VNImageTranslationAlignmentObservation
        else { return nil }
        let t = observation.alignmentTransform
        // 变换是把当前帧对齐到参考帧；画面本身反向平移回去
        return image.transformed(by: t.inverted()).cropped(to: image.extent)
    }
}

/// 三脚架检测：手持长曝光会糊，靠陀螺仪方差判断
final class StabilityMonitor {
    private let motion = CMMotionManagerShim()
    private(set) var isSteady = true

    func start() {
        motion.start { [weak self] magnitude in
            // 小幅度抖动（呼吸、手抖）容许，超过阈值的算没架稳
            self?.isSteady = magnitude < 0.22
        }
    }

    func stop() { motion.stop() }
}
