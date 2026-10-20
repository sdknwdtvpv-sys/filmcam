import AVFoundation
import CoreHaptics
import QuartzCore
import UIKit

// MARK: - 咔哒声采样合成

/// 一颗齿轮齿的声音：极短的噪声瞬态 + 两条非谐金属泛音 + 一点低频壳体。
///
/// 不用任何音频资源文件，启动时合成三段 WAV 塞给 AVAudioPlayer，
/// 换着放，避免高速旋转时听起来像一段循环采样。
private enum ClickSynth {
    static let sampleRate = 44_100
    static let seconds = 0.030
    /// 尾巴上的淡出，避免采样在非零处被切断产生第二记杂音
    static let release = 0.0035

    static func variants() -> [Data] {
        (0..<3).map { index in
            let gain: Float = [1.0, 0.93, 1.05][index]
            return wav(from: samples(seed: UInt64(index) * 7_919 + 13, gain: gain))
        }
    }

    private static func samples(seed: UInt64, gain: Float) -> [Float] {
        let count = Int(Double(sampleRate) * seconds)
        var out = [Float](repeating: 0, count: count)
        var rng = seed | 1
        var peak: Float = 0

        for i in 0..<count {
            let t = Double(i) / Double(sampleRate)
            rng = rng &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let white = Double(rng >> 11) / Double(UInt64(1) << 53) * 2 - 1

            let tooth = white * 0.60 * exp(-t / 0.00070)
            let metalHigh = 0.26 * sin(2 * .pi * 2_450 * t) * exp(-t / 0.0038)
            let metalEdge = 0.13 * sin(2 * .pi * 3_810 * t) * exp(-t / 0.0024)
            let body = 0.16 * sin(2 * .pi * 215 * t) * exp(-t / 0.0090)

            let tail = seconds - t
            let fade = tail < release ? Float(0.5 - 0.5 * cos(.pi * tail / release)) : 1
            let value = Float((tooth + metalHigh + metalEdge + body) * Double(gain)) * fade
            out[i] = value
            peak = max(peak, abs(value))
        }

        let scale = peak > 0 ? 0.92 / peak : 1
        return out.map { $0 * scale }
    }

    private static func wav(from samples: [Float]) -> Data {
        var pcm = Data(capacity: samples.count * 2)
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            let value = Int16(clamped * 32_000)
            withUnsafeBytes(of: value.littleEndian) { pcm.append(contentsOf: $0) }
        }

        var data = Data()
        func text(_ string: String) { data.append(contentsOf: Array(string.utf8)) }
        func u32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

        text("RIFF"); u32(UInt32(36 + pcm.count)); text("WAVE")
        text("fmt "); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        text("data"); u32(UInt32(pcm.count))
        data.append(pcm)
        return data
    }
}

// MARK: - 棘轮反馈

/// 机械棘轮：一记极短的金属咔哒声 + 一次锐利触感，同一个入口触发。
///
/// 触感走 Core Haptics 瞬态（`.light` 冲击在每秒几十次时会糊成一片，齿感全没）；
/// 硬件不支持时退回 UIImpactFeedbackGenerator。
@MainActor
final class DetentFeedback {
    static let shared = DetentFeedback()

    enum Weight {
        /// 细牙：滚花齿划过，轻
        case tooth
        /// 档位：参数真的跳了一格，重
        case detent

        var intensity: Float { self == .tooth ? 0.60 : 1.0 }
        var sharpness: Float { self == .tooth ? 0.95 : 0.62 }
        var volume: Float { self == .tooth ? 0.62 : 0.88 }
    }

    /// 录像时关掉声音，免得齿轮声被麦克风收进片子
    var soundEnabled = true

    private var players: [AVAudioPlayer] = []
    private var nextPlayer = 0
    private var lastClickAt: CFTimeInterval = 0
    /// 两次咔哒的最小间隔，约 70 次/秒，再快也只是叠成噪音
    private let minInterval: CFTimeInterval = 0.014

    private var engine: CHHapticEngine?
    private var toothHaptic: CHHapticPatternPlayer?
    private var detentHaptic: CHHapticPatternPlayer?
    private var usesFallback = false
    private var prepared = false

    private init() {}

    func prepare() {
        guard !prepared else { return }
        prepared = true
        prepareAudio()
        prepareHaptics()
    }

    func fire(_ weight: Weight = .tooth) {
        if soundEnabled { playClick(volume: weight.volume) }
        playHaptic(weight)
    }

    /// 进后台时放掉引擎，回前台重新 prepare
    func suspend() {
        engine?.stop(completionHandler: nil)
        toothHaptic = nil
        detentHaptic = nil
        engine = nil
        players.forEach { $0.stop() }
        players = []
        prepared = false
    }

    // MARK: 声音

    private func prepareAudio() {
        players = ClickSynth.variants().compactMap { data in
            guard let player = try? AVAudioPlayer(data: data) else { return nil }
            player.prepareToPlay()
            return player
        }
        #if DEBUG
        print(players.isEmpty
              ? "[DetentFeedback] 咔哒采样加载失败"
              : "[DetentFeedback] 咔哒采样就绪：\(players.count) 段")
        #endif
    }

    private func playClick(volume: Float) {
        let now = CACurrentMediaTime()
        guard now - lastClickAt >= minInterval else { return }
        guard !players.isEmpty else { return }
        lastClickAt = now

        let player = players[nextPlayer % players.count]
        nextPlayer &+= 1
        player.volume = volume
        player.currentTime = 0
        player.play()
    }

    // MARK: 触感

    private func prepareHaptics() {
        guard engine == nil, !usesFallback else { return }
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            #if DEBUG
            print("[DetentFeedback] 硬件不支持 Core Haptics，退回 UIImpactFeedbackGenerator")
            #endif
            usesFallback = true
            return
        }

        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = false
            engine.stoppedHandler = { [weak self] _ in
                Task { @MainActor in
                    self?.toothHaptic = nil
                    self?.detentHaptic = nil
                    self?.engine = nil
                }
            }
            engine.resetHandler = { [weak self] in
                Task { @MainActor in
                    guard let engine = self?.engine else { return }
                    try? engine.start()
                }
            }
            try engine.start()

            if let pattern = Self.pattern(.tooth) {
                toothHaptic = try? engine.makePlayer(with: pattern)
            }
            if let pattern = Self.pattern(.detent) {
                detentHaptic = try? engine.makePlayer(with: pattern)
            }
            self.engine = engine
            #if DEBUG
            print("[DetentFeedback] Core Haptics 引擎已启动")
            #endif
        } catch {
            #if DEBUG
            print("[DetentFeedback] Core Haptics 启动失败：\(error)")
            #endif
            self.engine = nil
            usesFallback = true
        }
    }

    private func playHaptic(_ weight: Weight) {
        guard !usesFallback else {
            fallbackImpact(weight)
            return
        }
        if engine == nil { prepareHaptics() }
        guard let player = (weight == .tooth ? toothHaptic : detentHaptic) else {
            fallbackImpact(weight)
            return
        }

        do {
            try? player.stop(atTime: CHHapticTimeImmediate)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // 引擎被系统收走了，下次重建，这一记用 UIKit 兜底
            toothHaptic = nil
            detentHaptic = nil
            engine = nil
            fallbackImpact(weight)
        }
    }

    private func fallbackImpact(_ weight: Weight) {
        let style: UIImpactFeedbackGenerator.FeedbackStyle = weight == .tooth ? .rigid : .medium
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred(intensity: CGFloat(weight.intensity))
    }

    private static func pattern(_ weight: Weight) -> CHHapticPattern? {
        var events: [CHHapticEvent] = [
            CHHapticEvent(eventType: .hapticTransient,
                          parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity,
                                                   value: weight.intensity),
                            CHHapticEventParameter(parameterID: .hapticSharpness,
                                                   value: weight.sharpness)
                          ],
                          relativeTime: 0)
        ]

        if weight == .detent {
            // 档位多一记短促的低频「咚」，齿和档在手上能分出轻重
            events.append(CHHapticEvent(eventType: .hapticContinuous,
                                        parameters: [
                                            CHHapticEventParameter(parameterID: .hapticIntensity,
                                                                   value: 0.5),
                                            CHHapticEventParameter(parameterID: .hapticSharpness,
                                                                   value: 0.22)
                                        ],
                                        relativeTime: 0,
                                        duration: 0.013))
        }

        return try? CHHapticPattern(events: events, parameters: [])
    }
}
