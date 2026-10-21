import Foundation

/// 一卷胶卷：有型号、有张数上限、有自己的随机种子。
/// 种子决定这卷的“性格”——颗粒粗细、漏光方向、极其轻微的偏色，
/// 所以同一卷拍出来的照片彼此连续，换卷就换了一整套。
struct FilmRoll: Codable, Identifiable, Equatable {
    var id: String              // 短 id：成片文件名前缀，也是相册分组的键
    var presetRaw: String
    var number: Int             // 全局第几卷
    var capacity: Int
    var used: Int
    var seed: UInt64
    var startedAt: Date
    var finishedAt: Date?

    var preset: FilmPreset { FilmPreset(rawValue: presetRaw) ?? .kodakGold }
    var remaining: Int { max(0, capacity - used) }
    var isFull: Bool { used >= capacity }
    /// 如 "12/36"
    var countText: String { "\(used)/\(capacity)" }
    /// 如 "第 3 卷"
    var numberText: String { String(format: NSLocalizedString("第 %d 卷", comment: ""), number) }

    var traits: RollTraits { RollTraits(seed: seed) }
}

/// 一卷的随机性格，由种子确定，同一种子永远得到同一套参数
struct RollTraits: Equatable {
    var grainBias: Double     // 颗粒强度系数 0.75…1.30
    var grainScale: Double    // 颗粒粗细 1.15…1.70
    var leakAngle: Double     // 漏光方向（弧度）
    var leakStrength: Double  // 漏光强度系数 0.65…1.35
    var tintShift: Double     // 极轻微偏色 -1…1

    init(seed: UInt64) {
        let a = Self.unit(seed, 1)
        let b = Self.unit(seed, 2)
        let c = Self.unit(seed, 3)
        let d = Self.unit(seed, 4)
        let e = Self.unit(seed, 5)

        grainBias = 0.75 + 0.55 * a
        grainScale = 1.15 + 0.55 * b
        leakAngle = c * 2 * .pi
        leakStrength = 0.65 + 0.70 * d
        tintShift = e * 2 - 1
    }

    /// 把一个种子摊成 0…1 的伪随机数
    private static func unit(_ seed: UInt64, _ salt: UInt64) -> Double {
        var x = seed &* 0x9E37_79B9_7F4A_7C15 &+ salt &* 0xD1B5_4A32_D192_ED03
        x ^= x >> 30
        x = x &* 0xBF58_476D_1CE4_E5B9
        x ^= x >> 27
        x = x &* 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        return Double(x % 100_000) / 100_000
    }
}

/// 当前装着的这卷 + 已经拍完归档的卷
@MainActor
final class RollStore: ObservableObject {
    static let shared = RollStore()

    /// 每卷张数：真实 135 胶卷的常见长度
    static let capacity = 36

    @Published private(set) var current: FilmRoll
    @Published private(set) var archive: [FilmRoll] = []

    private let storageKey = "futurecam.rolls.v1"
    private var nextNumber: Int = 1

    private struct Payload: Codable {
        var current: FilmRoll
        var archive: [FilmRoll]
        var nextNumber: Int
    }

    private init() {
        // 首次启动：装第一卷
        let roll = FilmRoll(id: Self.makeID(), presetRaw: FilmPreset.kodakGold.rawValue,
                            number: 1, capacity: Self.capacity, used: 0,
                            seed: Self.makeSeed(), startedAt: Date(), finishedAt: nil)
        current = roll
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            current = payload.current
            archive = payload.archive
            nextNumber = payload.nextNumber
        }
    }

    /// 装一卷新的。
    /// 当前这卷一张都没拍就换型号 = 同一卷换了胶卷，卷号不进位、也不归档。
    @discardableResult
    func load(_ preset: FilmPreset) -> FilmRoll {
        // 装的还是同一型号 = 没换卷。之前这里会给同型号也建新卷，
        // 结果每次打开片仓再点自己那卷，卷号就 +1，拍了一半的卷被收进档案。
        if preset.rawValue == current.presetRaw, !current.isFull {
            return current
        }

        if current.used == 0 {
            current.presetRaw = preset.rawValue
            current.seed = Self.makeSeed()   // 换了型号就换一套性格
            current.startedAt = Date()
            persist()
            return current
        }

        if current.used > 0 {
            var finished = current
            finished.finishedAt = Date()
            archive.insert(finished, at: 0)
        }
        nextNumber = max(nextNumber, current.number + 1)
        let roll = FilmRoll(id: Self.makeID(), presetRaw: preset.rawValue,
                            number: nextNumber, capacity: Self.capacity, used: 0,
                            seed: Self.makeSeed(), startedAt: Date(), finishedAt: nil)
        current = roll
        nextNumber = roll.number + 1
        persist()
        return roll
    }

    /// 记录一张。返回 false 表示这卷已经拍满，这次不该按下快门。
    @discardableResult
    func recordShot() -> Bool {
        guard !current.isFull else { return false }
        current.used += 1
        if current.isFull { current.finishedAt = Date() }
        persist()
        return true
    }

    #if DEBUG
    /// 调试：把当前这卷的卷号复位成 1（归档保留）
    func resetNumbering(to number: Int = 1) {
        current.number = number
        current.used = 0
        current.finishedAt = nil
        nextNumber = number + 1
        persist()
    }
    #endif

    func roll(id: String) -> FilmRoll? {
        if current.id == id { return current }
        return archive.first { $0.id == id }
    }

    private func persist() {
        let payload = Payload(current: current, archive: Array(archive.prefix(60)),
                              nextNumber: max(nextNumber, current.number + 1))
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private static func makeSeed() -> UInt64 {
        UInt64.random(in: 1...UInt64.max)
    }

    private static func makeID() -> String {
        String(format: "%04x", UInt32.random(in: 0...0xFFFF))
    }
}
