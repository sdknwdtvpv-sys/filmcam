import SwiftUI
import CoreImage

/// 自制胶卷：用户自己调的"色彩 + 颗粒 + 暗角"，存在本机，可复用可删。
/// 它不是 LUT，而是一组参数，所以在任何底片上都能重新算一遍。
struct CustomFilm: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var grade: GradientGrade
    var grain: Double = 0.35       // 0…1 叠加颗粒的强度
    var vignette: Double = 0.0     // 0…1
    var createdAt: Date = Date()

    /// GradeSettings 的可编码镜像（GradeSettings 本身不带 Codable）
    struct GradientGrade: Codable, Equatable {
        var exposure: Double = 0
        var highlight: Double = 0
        var shadow: Double = 0
        var contrast: Double = 1
        var saturation: Double = 1
        var temperature: Double = 0
        var tint: Double = 0
        var vibrance: Double = 0
        var blackPoint: Double = 0

        var asGrade: GradeSettings {
            GradeSettings(exposure: exposure, highlight: highlight, shadow: shadow,
                          contrast: contrast, blackPoint: blackPoint, saturation: saturation,
                          vibrance: vibrance, temperature: temperature, tint: tint,
                          vignette: 0, sharpness: 0, clarity: 0)
        }
    }
}

/// 本机存储：UserDefaults 里一段 JSON，跟着 App 一起删
@MainActor
final class CustomFilmStore: ObservableObject {
    static let shared = CustomFilmStore()

    @Published private(set) var films: [CustomFilm] = []
    private let key = "futurecam.customFilms.v1"

    init() { load() }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([CustomFilm].self, from: data)
        else { films = []; return }
        films = decoded
    }

    func save(_ film: CustomFilm) {
        if let index = films.firstIndex(where: { $0.id == film.id }) {
            films[index] = film
        } else {
            films.insert(film, at: 0)
        }
        persist()
    }

    func delete(_ film: CustomFilm) {
        films.removeAll { $0.id == film.id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(films) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

/// 调色的统一身份：内置配方 / 自制胶卷 / 原色
enum LookChoice: Identifiable, Equatable {
    case none
    case builtin(FilmPreset)
    case custom(CustomFilm)

    var id: String {
        switch self {
        case .none: return "none"
        case .builtin(let p): return "b." + p.rawValue
        case .custom(let f): return "c." + f.id.uuidString
        }
    }

    var label: String {
        switch self {
        case .none: return "原色"
        case .builtin(let p): return p.label
        case .custom(let f): return f.name
        }
    }

    var color: Color {
        switch self {
        case .none: return .white.opacity(0.25)
        case .builtin(let p): return canisterColor(p)
        case .custom(let f): return Color(hex: Self.swatch(f))
        }
    }

    /// 按参数给自制款一个稳定的色标
    private static func swatch(_ film: CustomFilm) -> UInt32 {
        let warm = max(0, film.grade.temperature) > 0.05
        let cool = min(0, film.grade.temperature) < -0.05
        if warm { return 0xB98A5E }
        if cool { return 0x5C7A94 }
        if film.grade.saturation < 0.6 { return 0x7A7A7A }
        return 0x6E8A5A
    }

    /// 施加到画面：先参数化调色，再叠颗粒与暗角
    func apply(to image: CIImage, seed: UInt64 = 20_261_021) -> CIImage {
        switch self {
        case .none:
            return image
        case .builtin(let preset):
            guard let grade = preset.grade else { return image }
            return FilmFilter.applyGrade(image, grade)
        case .custom(let film):
            var out = FilmFilter.applyGrade(image, film.grade.asGrade)
            if film.grain > 0.01 {
                let settings = GrainSettings.make(iso: 400 * film.grain * 2, traits: RollTraits(seed: seed), seed: seed)
                out = FilmFilter.applyGrain(out, settings: settings)
            }
            if film.vignette > 0.01, let f = CIFilter(name: "CIVignette") {
                f.setValue(out, forKey: kCIInputImageKey)
                f.setValue(film.vignette * 2.2, forKey: "inputIntensity")
                f.setValue(1.2, forKey: "inputRadius")
                out = f.outputImage ?? out
            }
            return out.cropped(to: image.extent)
        }
    }
}
