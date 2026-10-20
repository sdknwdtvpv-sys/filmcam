import AVFoundation

/// 机械声：快门两段 + 过卷棘轮，全部程序化合成，不带音频素材。
/// 会话是 .ambient（见 AudioRoute），所以静音键一拨就闭嘴，符合相机礼仪。
@MainActor
final class MechanicalSounds {
    static let shared = MechanicalSounds()

    /// 录像时关掉，免得被麦克风收进去
    var soundEnabled = true

    private var shutterPlayers: [AVAudioPlayer] = []
    private var advancePlayers: [AVAudioPlayer] = []
    private var nextShutter = 0
    private var nextAdvance = 0
    private var prepared = false

    private init() {}

    func prepare() {
        guard !prepared else { return }
        prepared = true
        shutterPlayers = Self.makePlayerPool(Self.shutterSamples())
        advancePlayers = Self.makePlayerPool(Self.advanceSamples())
    }

    /// 一拍：快门落下
    func shutter() {
        guard soundEnabled else { return }
        play(&nextShutter, shutterPlayers, volume: 0.95)
    }

    /// 一拍：过卷棘轮（拍完一张之后）
    func advance() {
        guard soundEnabled else { return }
        play(&nextAdvance, advancePlayers, volume: 0.72)
    }

    /// 快门 + 延迟过卷，最接近胶片机的节奏
    func shutterThenAdvance() {
        shutter()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            self?.advance()
        }
    }

    private func play(_ index: inout Int, _ pool: [AVAudioPlayer], volume: Float) {
        guard !pool.isEmpty else { return }
        let player = pool[index % pool.count]
        index &+= 1
        player.volume = volume
        player.currentTime = 0
        player.play()
    }

    private static func makePlayerPool(_ data: [Data]) -> [AVAudioPlayer] {
        data.compactMap { d in
            guard let p = try? AVAudioPlayer(data: d) else { return nil }
            p.prepareToPlay()
            return p
        }
    }

    // MARK: - 合成

    private static let sampleRate = 44_100

    /// 快门：先一记硬的（反光板），隔 48ms 再一记闷的（帘幕合上）
    private static func shutterSamples() -> [Data] {
        var out = [Float](repeating: 0, count: Int(Double(sampleRate) * 0.14))
        addImpact(&out, at: 0.0, gain: 1.0, decay: 0.012, body: 190, seeds: 11)
        addImpact(&out, at: 0.048, gain: 0.85, decay: 0.020, body: 132, seeds: 37)
        normalise(&out, target: 0.9)
        return [wav(from: out)]
    }

    /// 过卷：四记棘轮，间隔递减，像手指拨过卷片扳手
    private static func advanceSamples() -> [Data] {
        var out = [Float](repeating: 0, count: Int(Double(sampleRate) * 0.26))
        let gaps: [Double] = [0.0, 0.062, 0.112, 0.152]
        for (i, t) in gaps.enumerated() {
            addImpact(&out, at: t, gain: 0.55 + 0.12 * Double(i),
                      decay: 0.006, body: 260 + Double(i) * 26, seeds: UInt64(71 + i * 13))
        }
        normalise(&out, target: 0.8)
        return [wav(from: out)]
    }

    private static func addImpact(_ buffer: inout [Float], at time: Double, gain: Double,
                                  decay: Double, body: Double, seeds: UInt64) {
        let start = Int(Double(sampleRate) * time)
        var rng = seeds | 1
        var i = start
        while i < buffer.count {
            let t = Double(i - start) / Double(sampleRate)
            rng = rng &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let white = Double(rng >> 11) / Double(UInt64(1) << 53) * 2 - 1

            let noise = white * 0.55 * exp(-t / (decay * 0.55))
            let high = 0.22 * sin(2 * .pi * 3_100 * t) * exp(-t / (decay * 1.6))
            let thunk = 0.30 * sin(2 * .pi * body * t) * exp(-t / (decay * 2.4))
            buffer[i] += Float((noise + high + thunk) * gain)
            i += 1
        }
    }

    private static func normalise(_ buffer: inout [Float], target: Float) {
        let peak = buffer.reduce(Float(0)) { max($0, abs($1)) }
        guard peak > 0 else { return }
        let scale = target / peak
        for i in buffer.indices { buffer[i] *= scale }
    }

    /// 最小 WAV 包装（16-bit 单声道）
    private static func wav(from samples: [Float]) -> Data {
        var data = Data()
        let byteRate = sampleRate * 2
        let dataBytes = samples.count * 2

        func append(_ string: String) { data.append(contentsOf: Array(string.utf8)) }
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

        append("RIFF"); append32(UInt32(36 + dataBytes)); append("WAVE")
        append("fmt "); append32(16); append16(1); append16(1)
        append32(UInt32(sampleRate)); append32(UInt32(byteRate))
        append16(2); append16(16)
        append("data"); append32(UInt32(dataBytes))
        for s in samples {
            let clamped = max(-1, min(1, s))
            append16(UInt16(bitPattern: Int16(clamped * 32_767)))
        }
        return data
    }
}
