import CoreImage
#if canImport(UIKit)
import UIKit
#endif

/// 胶片预设（照片滤镜 & 视频 LUT 共用的风格定义）
enum FilmPreset: String, CaseIterable, Identifiable {
    /// 原生：不过 LUT、不加暗角漏光、不加颗粒。排最前，作为调色的干净底子
    case neutral
    case kodakGold       // 琥珀 200
    case fuji400         // 松石 400
    case classicBnw      // 银盐 400
    case fadedCinema     // 褪色电影
    case cinematic       // 钴蓝 200
    // 以下是自造 LUT（Tools/make_luts.py 生成，无第三方数据）
    case duskGold
    case slate
    case mint
    case rust
    case frost
    case ochre
    case abyss
    // 以下 4 个来自公开调色配方，翻译成参数化调色层（不用 LUT）
    case clear
    case nightStreet
    case fresh
    case moody
    case glowSkin
    case cream
    case warmSoft
    case glowField
    case sunsetFilm
    case forestGreen
    case snow
    case vintageFilm

    var id: String { rawValue }

    /// 胶片：决定介质（LUT + 暗角 + 漏光 + 颗粒 + 张数）
    /// 调色：只做参数化调色，可以叠在任意胶片上
    enum Kind { case film, look }
    var kind: Kind {
        switch self {
        case .clear, .nightStreet, .fresh, .moody,
             .glowSkin, .cream, .warmSoft, .glowField,
             .sunsetFilm, .forestGreen, .snow, .vintageFilm:
            return .look
        default: return .film
        }
    }

    static var films: [FilmPreset] { allCases.filter { $0.kind == .film } }
    static var looks: [FilmPreset] { allCases.filter { $0.kind == .look } }

    /// 全部自造名：不出现任何胶片厂商的注册商标
    var label: String {
        switch self {
        case .kodakGold:   return "琥珀 200"
        case .fuji400:     return "松石 400"
        case .classicBnw:  return "银盐 400"
        case .fadedCinema: return "褪色电影"
        case .cinematic:   return "钴蓝 200"
        case .duskGold:    return "暮金 100"
        case .slate:       return "石板 800"
        case .mint:        return "薄荷 400"
        case .rust:        return "铁锈 400"
        case .frost:       return "霜白 400"
        case .ochre:       return "赭石 200"
        case .abyss:       return "深潭 1600"
        case .clear:       return "清透 100"
        case .nightStreet: return "夜街 800"
        case .fresh:       return "晴野 200"
        case .moody:       return "暗涌 400"
        case .neutral:     return "原生"
        case .glowSkin:    return "冷白 200"
        case .cream:       return "奶油 400"
        case .warmSoft:    return "暖柔 200"
        case .glowField:   return "夏日 400"
        case .sunsetFilm:  return "落日 200"
        case .forestGreen: return "森野 400"
        case .snow:        return "雪原 100"
        case .vintageFilm: return "复古 200"
        }
    }

    /// 自检用：临时覆盖 LUT 占比（不影响 App 内行为）
    func withLutOverride(_ mix: CGFloat) -> FilmPreset {
        let key = "_lutOverride_\(mix)"
        _lutOverrides[rawValue + key] = mix
        return self
    }

    /// 这一卷的胶片性格（色调映射 / 分离色调 / halation / 柔化 / LUT 占比）
    var character: FilmCharacter {
        var base = characterBase
        if let override = _lutOverrides[rawValue + "_lutOverride_0.0"]
            ?? _lutOverrides[rawValue + "_lutOverride_0.35"]
            ?? _lutOverrides[rawValue + "_lutOverride_0.6"] {
            base.lutMix = override
        }
        return base
    }

    private var characterBase: FilmCharacter {
        switch self {
        case .neutral:
            return .none
        case .kodakGold:      // 琥珀 200：暖、宽容、轻微晕
            return FilmCharacter(blackLift: 0.032, highlightRoll: 0.950, midContrast: 0.24,
                                 shadowTint: (0.20, 0.22, 0.26), highlightTint: (0.66, 0.50, 0.32),
                                 splitStrength: 0.0, halation: 0.0, soften: 0.20,
                                 lutMix: 0.60, grainScale: 1.0)
        case .fuji400:        // 松石 400：偏绿、高对比、颗粒明显
            return FilmCharacter(blackLift: 0.026, highlightRoll: 0.945, midContrast: 0.28,
                                 shadowTint: (0.14, 0.28, 0.28), highlightTint: (0.58, 0.52, 0.40),
                                 splitStrength: 0.0, halation: 0.0, soften: 0.16,
                                 lutMix: 0.62, grainScale: 1.15)
        case .classicBnw:     // 银盐 400：黑白，靠曲线吃饭
            return FilmCharacter(blackLift: 0.040, highlightRoll: 0.940, midContrast: 0.34,
                                 shadowTint: (0.5, 0.5, 0.5), highlightTint: (0.5, 0.5, 0.5),
                                 splitStrength: 0.0, halation: 0.0, soften: 0.18,
                                 lutMix: 0.70, grainScale: 1.25)
        case .fadedCinema:    // 褪色电影：大抬黑、低对比
            return FilmCharacter(blackLift: 0.060, highlightRoll: 0.930, midContrast: 0.12,
                                 shadowTint: (0.24, 0.26, 0.28), highlightTint: (0.58, 0.50, 0.44),
                                 splitStrength: 0.0, halation: 0.0, soften: 0.26,
                                 lutMix: 0.55, grainScale: 1.0)
        case .cinematic:      // 钴蓝 200：冷调风光
            return FilmCharacter(blackLift: 0.030, highlightRoll: 0.950, midContrast: 0.26,
                                 shadowTint: (0.12, 0.24, 0.34), highlightTint: (0.54, 0.52, 0.44),
                                 splitStrength: 0.0, halation: 0.0, soften: 0.18,
                                 lutMix: 0.62, grainScale: 0.95)
        case .duskGold:       // 暮金 100：日落
            return FilmCharacter(blackLift: 0.034, highlightRoll: 0.945, midContrast: 0.22,
                                 shadowTint: (0.22, 0.22, 0.28), highlightTint: (0.70, 0.52, 0.30),
                                 splitStrength: 0.0, halation: 0.0, soften: 0.22,
                                 lutMix: 0.58, grainScale: 0.85)
        case .slate:          // 石板 800：阴天街拍
            return FilmCharacter(blackLift: 0.036, highlightRoll: 0.940, midContrast: 0.24,
                                 shadowTint: (0.16, 0.20, 0.24), highlightTint: (0.52, 0.50, 0.46),
                                 splitStrength: 0.0, halation: 0.0, soften: 0.20,
                                 lutMix: 0.60, grainScale: 1.1)
        case .mint:           // 薄荷 400：绿调
            return FilmCharacter(blackLift: 0.034, highlightRoll: 0.950, midContrast: 0.20,
                                 shadowTint: (0.16, 0.28, 0.26), highlightTint: (0.56, 0.54, 0.42),
                                 splitStrength: 0.0, halation: 0.0, soften: 0.18,
                                 lutMix: 0.62, grainScale: 1.0)
        case .rust:           // 铁锈 400：暖褐
            return FilmCharacter(blackLift: 0.038, highlightRoll: 0.940, midContrast: 0.26,
                                 shadowTint: (0.26, 0.20, 0.18), highlightTint: (0.66, 0.48, 0.32),
                                 splitStrength: 0.0, halation: 0.0, soften: 0.20,
                                 lutMix: 0.60, grainScale: 1.1)
        case .frost:          // 霜白 400：冷白
            return FilmCharacter(blackLift: 0.030, highlightRoll: 0.960, midContrast: 0.18,
                                 shadowTint: (0.16, 0.22, 0.30), highlightTint: (0.54, 0.56, 0.56),
                                 splitStrength: 0.0, halation: 0.0, soften: 0.16,
                                 lutMix: 0.58, grainScale: 0.95)
        case .ochre:          // 赭石 200：土黄
            return FilmCharacter(blackLift: 0.036, highlightRoll: 0.945, midContrast: 0.24,
                                 shadowTint: (0.24, 0.22, 0.18), highlightTint: (0.68, 0.52, 0.34),
                                 splitStrength: 0.0, halation: 0.0, soften: 0.20,
                                 lutMix: 0.60, grainScale: 1.0)
        case .abyss:          // 深潭 1600：夜空，溢出最强
            return FilmCharacter(blackLift: 0.044, highlightRoll: 0.930, midContrast: 0.30,
                                 shadowTint: (0.10, 0.18, 0.34), highlightTint: (0.70, 0.52, 0.36),
                                 splitStrength: 0.0, halation: 0.0, soften: 0.20,
                                 lutMix: 0.62, grainScale: 1.35)
        default:
            // 配方类（调色派）不走胶片性格，由 applyGrade 负责
            return .none
        }
    }

    /// 原生底子不加颗粒（它要当调色的干净底）
    var hasGrain: Bool { self != .neutral }

    /// 参数化调色（来自公开的滑块配方，按各自意图重新标定）。
    /// 注意：那些数值是相对 iPhone 照片 App 基线做的增量，直接照搬会走样，
    /// 这里按本 App 的基线重新给了量；名字一律自造，不引用任何厂商或人名。
    var grade: GradeSettings? {
        switch self {
        case .clear:
            // 清透：压高光、提阴影、略降饱和、偏冷、加清晰度
            return GradeSettings(exposure: 0.04, highlight: -0.32, shadow: 0.28,
                                 contrast: 0.96, saturation: 0.91, temperature: -0.09,
                                 sharpness: 0.22, clarity: 0.12)
        case .nightStreet:
            // 夜街：更狠地压高光、抬阴影、降饱和、更冷
            return GradeSettings(exposure: 0.03, highlight: -0.45, shadow: 0.38,
                                 contrast: 0.94, blackPoint: 0.08, saturation: 0.86,
                                 temperature: -0.14, sharpness: 0.20)
        case .fresh:
            // 晴野：大幅提亮阴影、提饱和、偏冷偏绿
            return GradeSettings(exposure: 0.05, highlight: -0.30, shadow: 0.55,
                                 contrast: 0.88, brightness: 0.04, saturation: 1.12,
                                 temperature: -0.10, tint: -0.08,
                                 sharpness: 0.18, clarity: 0.16)
        case .moody:
            // 暗涌：压整体亮度、降饱和、偏暖、加对比
            return GradeSettings(exposure: -0.16, highlight: -0.20, shadow: 0.24,
                                 contrast: 1.10, brightness: -0.05, saturation: 0.82,
                                 tint: 0.14, vignette: 0.18, clarity: 0.14)
        case .glowSkin:
            // 冷白透光肌：提亮高光、压阴影、偏冷，皮肤发亮
            return GradeSettings(exposure: 0.06, highlight: 0.30, shadow: -0.18,
                                 contrast: 0.90, brightness: 0.05, tint: -0.14,
                                 clarity: 0.08)
        case .cream:
            // 奶油淡颜：整体提亮、奶感偏暖、低对比
            return GradeSettings(exposure: 0.06, shadow: 0.20, contrast: 0.90,
                                 brightness: 0.05, temperature: 0.05, tint: 0.14,
                                 sharpness: 0.10)
        case .warmSoft:
            // 暖柔氛围：大提亮、暖、压黑点
            return GradeSettings(exposure: 0.14, shadow: 0.20, contrast: 0.90,
                                 brightness: 0.05, blackPoint: -0.12,
                                 temperature: 0.08, tint: 0.14, sharpness: 0.08, clarity: 0.12)
        case .glowField:
            // 夏日发光：大幅提阴影、微暖、通透
            return GradeSettings(exposure: 0.03, highlight: -0.30, shadow: 0.60,
                                 contrast: 0.86, brightness: 0.06, saturation: 1.06,
                                 vibrance: 0.14, temperature: 0.10, tint: 0.12)
        case .sunsetFilm:
            // 落日电影：明显偏暖、压高光、提饱和
            return GradeSettings(exposure: 0.18, highlight: -0.35, contrast: 1.06,
                                 brightness: 0.03, saturation: 1.12,
                                 temperature: 0.22, tint: 0.10, sharpness: 0.10, clarity: 0.10)
        case .forestGreen:
            // 森野：提阴影、微绿、饱和略高
            return GradeSettings(exposure: 0.04, highlight: -0.24, shadow: 0.30,
                                 contrast: 0.94, saturation: 1.06,
                                 temperature: -0.05, tint: -0.06)
        case .snow:
            // 雪原：提亮、降饱和、偏冷，保住雪的层次
            return GradeSettings(exposure: 0.10, highlight: -0.20, shadow: 0.24,
                                 contrast: 0.94, saturation: 0.90,
                                 temperature: -0.10, sharpness: 0.14, clarity: 0.10)
        case .vintageFilm:
            // 复古：压曝光、加深黑点、偏冷、略降饱和、轻暗角
            return GradeSettings(exposure: -0.06, highlight: -0.08, shadow: -0.04,
                                 contrast: 1.06, brightness: -0.04, blackPoint: -0.15,
                                 saturation: 0.94, temperature: -0.16, tint: 0.06,
                                 vignette: 0.12)
        default:
            return nil
        }
    }

    /// 标称感光度：既显示在暗盒上，也决定颗粒与手动 ISO 的默认值
    var nominalISO: String {
        switch self {
        case .kodakGold:   return "200"
        case .fuji400:     return "400"
        case .classicBnw:  return "400"
        case .fadedCinema: return "200"
        case .cinematic:   return "200"
        case .duskGold:    return "100"
        case .slate:       return "800"
        case .mint:        return "400"
        case .rust:        return "400"
        case .frost:       return "400"
        case .ochre:       return "200"
        case .abyss:       return "1600"
        case .clear:       return "100"
        case .nightStreet: return "800"
        case .fresh:       return "200"
        case .moody:       return "400"
        case .neutral:     return "100"
        case .glowSkin:    return "200"
        case .cream:       return "400"
        case .warmSoft:    return "200"
        case .glowField:   return "400"
        case .sunsetFilm:  return "200"
        case .forestGreen: return "400"
        case .snow:        return "100"
        case .vintageFilm: return "200"
        }
    }
}

private struct FilterParams {
    var proceduralColor: Bool      // 是否走内置色温/色彩控制（LUT 预设一般关闭，避免与 LUT 叠加过厚）
    var neutral: CGFloat          // 色温目标
    var saturation: CGFloat
    var contrast: CGFloat
    var brightness: CGFloat
    var vignette: CGFloat
    var vignetteRadius: CGFloat
    var leakColor: (r: CGFloat, g: CGFloat, b: CGFloat)
    var leakAlpha: CGFloat
    var lutIntensity: CGFloat     // LUT 叠加强度（0 = 不使用 LUT）
}

/// 自检用的临时覆盖表（只在 macOS 接触印相里用）
nonisolated(unsafe) var _lutOverrides: [String: CGFloat] = [:]

/// 胶片性格：决定这一卷"像什么胶片"，而不是"调了什么色"。
/// 真正的质感来自这几条曲线，LUT 只负责最后那点色彩倾向。
struct FilmCharacter {
    /// 黑位抬起：胶片从不死黑
    var blackLift: CGFloat = 0.030
    /// 高光滚降：1.0 会被压到这个值
    var highlightRoll: CGFloat = 0.955
    /// 中间调 S 形强度（0 = 不压，1 = 很强）
    var midContrast: CGFloat = 0.22
    /// 暗部偏色（青绿方向）
    var shadowTint: (r: CGFloat, g: CGFloat, b: CGFloat) = (0.16, 0.26, 0.30)
    /// 高光偏色（暖方向）
    var highlightTint: (r: CGFloat, g: CGFloat, b: CGFloat) = (0.60, 0.49, 0.35)
    /// 分离色调整体强度
    var splitStrength: CGFloat = 0.16
    /// 高光溢出（halation）
    var halation: CGFloat = 0.28
    /// 光学柔化（0 = 不动）
    var soften: CGFloat = 0.22
    /// LUT 占多少（剩下的留给原图）
    var lutMix: CGFloat = 0.60
    /// 颗粒倍率（乘在卷本身的颗粒上）
    var grainScale: CGFloat = 1.0

    static let none = FilmCharacter(blackLift: 0, highlightRoll: 1, midContrast: 0,
                                    splitStrength: 0, halation: 0, soften: 0,
                                    lutMix: 0, grainScale: 0)
}

/// 参数化调色层：对应照片 App 里那套滑块（曝光/高光/阴影/对比/黑点/饱和/自然饱和/色温/色调/暗角/锐度/清晰度）。
/// 取值范围统一成 -1…1（除对比、饱和围绕 1.0），方便从配方里换算。
struct GradeSettings: Equatable {
    var exposure: Double = 0      // EV，-1…1 表示 -2…+2 档
    var highlight: Double = 0     // -1…1
    var shadow: Double = 0        // -1…1
    var contrast: Double = 1.0    // 0.6…1.6
    var brightness: Double = 0    // -0.3…0.3
    var blackPoint: Double = 0    // -1…1
    var saturation: Double = 1.0  // 0…2
    var vibrance: Double = 0      // 0…1
    var temperature: Double = 0   // -1…1，换算成 ±900K
    var tint: Double = 0          // -1…1
    var vignette: Double = 0      // 0…1
    var sharpness: Double = 0     // 0…1
    var clarity: Double = 0       // 0…1
}

/// 颗粒参数：强度决定压在画面上的厚度，scale 决定粗细（ISO 越高越粗）
struct GrainSettings: Equatable {
    var intensity: Double
    var scale: Double
    var offsetX: Double
    var offsetY: Double

    static let none = GrainSettings(intensity: 0, scale: 1, offsetX: 0, offsetY: 0)

    /// 按 ISO 与这卷的颗粒系数推出一组参数
    static func make(iso: Double, traits: RollTraits, seed: UInt64) -> GrainSettings {
        let isoStops = max(0, log2(max(iso, 50) / 100))          // 100 度以上开始变粗
        let intensity = (0.10 + 0.055 * isoStops) * traits.grainBias
        let scale = traits.grainScale + 0.30 * isoStops
        let a = Double(seed % 997) / 997
        let b = Double((seed >> 11) % 991) / 991
        return GrainSettings(intensity: intensity, scale: scale, offsetX: a, offsetY: b)
    }
}

/// 实时胶片滤镜引擎（Core Image 链：色温 + 色彩控制 + 暗角 + 漏光 + 可插拔 3D LUT + 颗粒）
struct FilmFilter {
    /// 渲染质量：取景与录像用 .fast（跳过柔化与 halation，保 60fps），
    /// 成片与显影用 .full。
    enum Quality { case fast, full }

    static func apply(_ image: CIImage, preset: FilmPreset,
                      traits: RollTraits? = nil,
                      grain: GrainSettings = .none,
                      quality: Quality = .full) -> CIImage {
        let p = params(for: preset)
        let c = preset.character
        let extent = image.extent
        let dbg = ProcessInfo.processInfo.environment
        var img = image

        // 1. 光学柔化：数码原图太锐，胶片镜头有细微扩散
        if quality == .full, c.soften > 0.01 {
            img = soften(img, amount: c.soften)
        }

        // 2. 内置色温 + 色彩控制（LUT 预设默认关闭，由 LUT 主导色调）
        if p.proceduralColor {
            if let f = CIFilter(name: "CITemperatureAndTint") {
                f.setValue(img, forKey: kCIInputImageKey)
                f.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
                f.setValue(CIVector(x: p.neutral, y: 0), forKey: "inputTargetNeutral")
                if let out = f.outputImage { img = out }
            }
            if let f = CIFilter(name: "CIColorControls") {
                f.setValue(img, forKey: kCIInputImageKey)
                f.setValue(p.saturation, forKey: kCIInputSaturationKey)
                f.setValue(p.contrast, forKey: kCIInputContrastKey)
                f.setValue(p.brightness, forKey: kCIInputBrightnessKey)
                if let out = f.outputImage { img = out }
            }
        }

        // 3. 色调映射：黑位抬起 + 高光滚降 + 中间调 S。
        //    这一层决定"像不像胶片"，必须在 LUT 之前。
        if (c.blackLift > 0 || c.highlightRoll < 1), dbg["FC_NO_CURVE"] == nil {
            img = toneCurve(img, character: c)
        }

        // 3b. 源图是手机 JPEG，高光里带色度噪点；LUT 会把它放大成彩色雪花
        if quality == .full, let f = CIFilter(name: "CINoiseReduction") {
            f.setValue(img, forKey: kCIInputImageKey)
            f.setValue(0.02, forKey: "inputNoiseLevel")
            f.setValue(0.4, forKey: "inputSharpness")
            if let out = f.outputImage { img = out.cropped(to: extent) }
        }

        // 4. 3D LUT：只占 character.lutMix，其余留给原图的色彩关系
        let lutAmount = p.lutIntensity * c.lutMix
        if lutAmount > 0.01,
           let lut = LUTFilter.resolvedLUT(for: preset, intensity: 1.0) {
            let graded = LUTFilter.apply(lut, to: img)
            // 高光不吃 LUT：真实胶片到白场会自然去色，也让过曝的窗子不再出现彩色噪点
            let lum = luminance(img)
            let squared = lum.applyingFilter("CIMultiplyBlendMode", parameters: [
                kCIInputBackgroundImageKey: lum.cropped(to: extent)])
            let keep = squared.applyingFilter("CIColorInvert").cropped(to: extent)
            if let blend = CIFilter(name: "CIBlendWithMask") {
                let mixed = dissolve(img, graded, time: lutAmount)
                blend.setValue(mixed, forKey: kCIInputImageKey)
                blend.setValue(img, forKey: kCIInputBackgroundImageKey)
                blend.setValue(keep, forKey: kCIInputMaskImageKey)
                img = (blend.outputImage ?? mixed).cropped(to: extent)
            } else {
                img = dissolve(img, graded, time: lutAmount)
            }
        }

        // 5. 分离色调：暗部偏青、高光偏暖
        if c.splitStrength > 0.01, dbg["FC_NO_SPLIT"] == nil {
            img = splitTone(img, character: c)
        }

        // 6. Halation：高光溢出，只做成片（模糊很贵）
        if quality == .full, c.halation > 0.01, dbg["FC_NO_HALATION"] == nil {
            img = halation(img, amount: c.halation)
        }

        // 7. 参数化调色（照片 App 那套滑块，配方类预设用）
        if let grade = preset.grade {
            img = applyGrade(img, grade)
        }

        // 8. 这卷的轻微偏色（±160K 以内，只做连续性不做风格）
        if let traits, abs(traits.tintShift) > 0.05,
           let f = CIFilter(name: "CITemperatureAndTint") {
            f.setValue(img, forKey: kCIInputImageKey)
            f.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            f.setValue(CIVector(x: 6500 - traits.tintShift * 160, y: 0), forKey: "inputTargetNeutral")
            if let out = f.outputImage { img = out }
        }

        // 9. 漏光（径向渐变 + 滤色混合）
        if p.leakAlpha > 0,
           let grad = CIFilter(name: "CIRadialGradient") {
            let dx = traits.map { cos($0.leakAngle) * Double(img.extent.width) * 0.20 } ?? 0
            let dy = traits.map { sin($0.leakAngle) * Double(img.extent.height) * 0.20 } ?? 0
            let center = CIVector(x: img.extent.midX + CGFloat(dx),
                                  y: img.extent.midY + CGFloat(dy))
            grad.setValue(center, forKey: "inputCenter")
            grad.setValue(NSNumber(value: Double(min(img.extent.width, img.extent.height) * 0.2)),
                          forKey: "inputRadius0")
            grad.setValue(NSNumber(value: Double(max(img.extent.width, img.extent.height))),
                          forKey: "inputRadius1")
            let leakAlpha = p.leakAlpha * CGFloat(traits?.leakStrength ?? 1)
            grad.setValue(CIColor(red: p.leakColor.r, green: p.leakColor.g, blue: p.leakColor.b,
                                  alpha: leakAlpha), forKey: "inputColor1")
            grad.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: 0), forKey: "inputColor0")
            if let g = grad.outputImage,
               let blend = CIFilter(name: "CIScreenBlendMode") {
                blend.setValue(img, forKey: kCIInputImageKey)
                blend.setValue(g, forKey: kCIInputBackgroundImageKey)
                if let out = blend.outputImage { img = out }
            }
        }

        // 10. 颗粒：只在中间调最强（真实胶片颗粒的分布）
        if grain.intensity > 0.001 {
            img = applyGrain(img.cropped(to: extent),
                             settings: grain,
                             scale: c.grainScale,
                             midtoneMasked: true)
        }

        // 11. 自然暗角（放在最后，避免被 LUT 再压一次）
        if p.vignette > 0.001, dbg["FC_NO_VIGNETTE"] == nil, let f = CIFilter(name: "CIVignette") {
            f.setValue(img, forKey: kCIInputImageKey)
            f.setValue(p.vignette, forKey: "inputIntensity")
            f.setValue(p.vignetteRadius, forKey: "inputRadius")
            if let out = f.outputImage { img = out }
        }

        return img.cropped(to: extent)
    }

    // MARK: - 胶片响应层

    private static func dissolve(_ a: CIImage, _ b: CIImage, time: CGFloat) -> CIImage {
        guard let f = CIFilter(name: "CIDissolveTransition") else { return b }
        f.setValue(a, forKey: kCIInputImageKey)
        f.setValue(b, forKey: kCIInputTargetImageKey)
        f.setValue(time, forKey: kCIInputTimeKey)
        return (f.outputImage ?? b).cropped(to: a.extent)
    }

    private static func soften(_ image: CIImage, amount: CGFloat) -> CIImage {
        guard let blur = CIFilter(name: "CIGaussianBlur") else { return image }
        let radius = max(0.4, 1.4 * amount)
        blur.setValue(image.clampedToExtent(), forKey: kCIInputImageKey)
        blur.setValue(radius, forKey: kCIInputRadiusKey)
        guard let blurred = blur.outputImage?.cropped(to: image.extent) else { return image }
        return dissolve(image, blurred, time: amount)
    }

    /// 胶片曲线：抬黑 + 滚降 + S 形
    private static func toneCurve(_ image: CIImage, character c: FilmCharacter) -> CIImage {
        guard let f = CIFilter(name: "CIToneCurve") else { return image }
        let lift = c.blackLift
        let roll = c.highlightRoll
        let s = c.midContrast
        // 中间调两侧各抬/压一点，形成 S
        let p1y = 0.25 + lift * 0.6 - s * 0.06
        let p2y = 0.50 + lift * 0.25 + s * 0.02
        let p3y = 0.78 + (roll - 1) * 0.5 + s * 0.05
        f.setValue(image, forKey: kCIInputImageKey)
        f.setValue(CIVector(x: 0, y: lift), forKey: "inputPoint0")
        f.setValue(CIVector(x: 0.25, y: p1y), forKey: "inputPoint1")
        f.setValue(CIVector(x: 0.5, y: p2y), forKey: "inputPoint2")
        f.setValue(CIVector(x: 0.78, y: p3y), forKey: "inputPoint3")
        f.setValue(CIVector(x: 1, y: roll), forKey: "inputPoint4")
        return (f.outputImage ?? image).cropped(to: image.extent)
    }

    /// 亮度遮罩：0 = 全黑，1 = 全白
    private static func luminance(_ image: CIImage) -> CIImage {
        let m = CIFilter(name: "CIColorMatrix")!
        m.setValue(image, forKey: kCIInputImageKey)
        m.setValue(CIVector(x: 0.30, y: 0.30, z: 0.30, w: 0), forKey: "inputRVector")
        m.setValue(CIVector(x: 0.59, y: 0.59, z: 0.59, w: 0), forKey: "inputGVector")
        m.setValue(CIVector(x: 0.11, y: 0.11, z: 0.11, w: 0), forKey: "inputBVector")
        return (m.outputImage ?? image).cropped(to: image.extent)
    }

    /// 分离色调：暗部与高光分别偏色
    private static func splitTone(_ image: CIImage, character c: FilmCharacter) -> CIImage {
        let lum = luminance(image)
        var out = image

        // 暗部：把阴影层的颜色压进去
        let shadow = CIImage(color: CIColor(red: c.shadowTint.r, green: c.shadowTint.g,
                                            blue: c.shadowTint.b))
            .cropped(to: image.extent)
        if let blend = CIFilter(name: "CISoftLightBlendMode"), let mask = CIFilter(name: "CIBlendWithMask") {
            blend.setValue(shadow, forKey: kCIInputImageKey)
            blend.setValue(out, forKey: kCIInputBackgroundImageKey)
            mask.setValue(blend.outputImage, forKey: kCIInputImageKey)
            mask.setValue(out, forKey: kCIInputBackgroundImageKey)
            mask.setValue(lum.applyingFilter("CIColorInvert"), forKey: kCIInputMaskImageKey)
            out = (mask.outputImage ?? out).cropped(to: image.extent)
        }

        // 高光
        let highlight = CIImage(color: CIColor(red: c.highlightTint.r, green: c.highlightTint.g,
                                               blue: c.highlightTint.b))
            .cropped(to: image.extent)
        if let blend = CIFilter(name: "CISoftLightBlendMode"), let mask = CIFilter(name: "CIBlendWithMask") {
            blend.setValue(highlight, forKey: kCIInputImageKey)
            blend.setValue(out, forKey: kCIInputBackgroundImageKey)
            mask.setValue(blend.outputImage, forKey: kCIInputImageKey)
            mask.setValue(out, forKey: kCIInputBackgroundImageKey)
            mask.setValue(lum, forKey: kCIInputMaskImageKey)
            out = (mask.outputImage ?? out).cropped(to: image.extent)
        }

        return dissolve(image, out, time: c.splitStrength)
    }

    /// 高光溢出：亮部模糊后偏红叠回去
    private static func halation(_ image: CIImage, amount: CGFloat) -> CIImage {
        guard let matrix = CIFilter(name: "CIColorMatrix"),
              let blur = CIFilter(name: "CIGaussianBlur"),
              let tint = CIFilter(name: "CIColorMatrix"),
              let add = CIFilter(name: "CIAdditionCompositing") else { return image }

        matrix.setValue(image, forKey: kCIInputImageKey)
        matrix.setValue(CIVector(x: 1.4, y: 0, z: 0, w: 0), forKey: "inputRVector")
        matrix.setValue(CIVector(x: 0, y: 1.3, z: 0, w: 0), forKey: "inputGVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: 1.2, w: 0), forKey: "inputBVector")
        matrix.setValue(CIVector(x: -0.72, y: -0.70, z: -0.66, w: 0), forKey: "inputBiasVector")
        guard let bright = matrix.outputImage else { return image }

        blur.setValue(bright.clampedToExtent(), forKey: kCIInputImageKey)
        blur.setValue(image.extent.width * 0.018, forKey: kCIInputRadiusKey)
        guard let blurred = blur.outputImage?.cropped(to: image.extent) else { return image }

        tint.setValue(blurred, forKey: kCIInputImageKey)
        tint.setValue(CIVector(x: 1.0, y: 0, z: 0, w: 0), forKey: "inputRVector")
        tint.setValue(CIVector(x: 0, y: 0.55, z: 0, w: 0), forKey: "inputGVector")
        tint.setValue(CIVector(x: 0, y: 0, z: 0.40, w: 0), forKey: "inputBVector")
        guard let warm = tint.outputImage else { return image }

        add.setValue(warm, forKey: kCIInputImageKey)
        add.setValue(image, forKey: kCIInputBackgroundImageKey)
        guard let composed = add.outputImage else { return image }
        return dissolve(image, composed.cropped(to: image.extent), time: amount)
    }

    private static let renderContext = CIContext(options: [.useSoftwareRenderer: false])

    #if canImport(UIKit)
    /// 把 CIImage 渲染成 UIImage + JPEG（成片重渲染走这里）
    static func render(_ image: CIImage, quality: CGFloat = 0.92) -> (UIImage, Data)? {
        let extent = image.extent
        guard extent.width > 1, extent.height > 1,
              let cg = renderContext.createCGImage(image, from: extent) else { return nil }
        let ui = UIImage(cgImage: cg)
        guard let data = ui.jpegData(compressionQuality: quality) else { return nil }
        return (ui, data)
    }
    #else
    /// macOS 自检用：只出 CGImage
    static func renderCG(_ image: CIImage) -> CGImage? {
        renderContext.createCGImage(image, from: image.extent)
    }
    #endif

    /// 参数化调色：按滑块语义依次施加 Core Image 滤镜
    static func applyGrade(_ image: CIImage, _ g: GradeSettings) -> CIImage {
        var img = image.cropped(to: image.extent)   // 先裁，避免无穷 extent 里做重活

        if g.exposure != 0, let f = CIFilter(name: "CIExposureAdjust") {
            f.setValue(img, forKey: kCIInputImageKey)
            f.setValue(g.exposure * 2.0, forKey: kCIInputEVKey)
            img = f.outputImage ?? img
        }

        if g.highlight != 0 || g.shadow != 0, let f = CIFilter(name: "CIHighlightShadowAdjust") {
            f.setValue(img, forKey: kCIInputImageKey)
            // 照片 App 的高光 -100 相当于压低高光，这里正数=压
            f.setValue(1.0 + g.highlight * 0.9, forKey: "inputHighlightAmount")
            f.setValue(1.0 + g.shadow * 0.9, forKey: "inputShadowAmount")
            img = f.outputImage ?? img
        }

        if g.contrast != 1.0 || g.saturation != 1.0 || g.brightness != 0,
           let f = CIFilter(name: "CIColorControls") {
            f.setValue(img, forKey: kCIInputImageKey)
            f.setValue(g.contrast, forKey: kCIInputContrastKey)
            f.setValue(g.saturation, forKey: kCIInputSaturationKey)
            f.setValue(g.brightness, forKey: kCIInputBrightnessKey)
            img = f.outputImage ?? img
        }

        if g.vibrance > 0.001, let f = CIFilter(name: "CIVibrance") {
            f.setValue(img, forKey: kCIInputImageKey)
            f.setValue(g.vibrance, forKey: "inputAmount")
            img = f.outputImage ?? img
        }

        if g.temperature != 0 || g.tint != 0, let f = CIFilter(name: "CITemperatureAndTint") {
            f.setValue(img, forKey: kCIInputImageKey)
            f.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            f.setValue(CIVector(x: 6500 + g.temperature * 900, y: g.tint * 60),
                       forKey: "inputTargetNeutral")
            img = f.outputImage ?? img
        }

        // 黑点：用曲线把最暗端抬起来或压下去
        if abs(g.blackPoint) > 0.01, let f = CIFilter(name: "CIToneCurve") {
            f.setValue(img, forKey: kCIInputImageKey)
            let lift = max(0, g.blackPoint) * 0.25
            let crush = max(0, -g.blackPoint) * 0.10
            f.setValue(CIVector(x: 0, y: lift), forKey: "inputPoint0")
            f.setValue(CIVector(x: 0.25, y: 0.25 + lift * 0.4 - crush * 0.4), forKey: "inputPoint1")
            f.setValue(CIVector(x: 0.5, y: 0.5 + lift * 0.15 - crush * 0.1), forKey: "inputPoint2")
            f.setValue(CIVector(x: 1.0, y: 1.0), forKey: "inputPoint4")
            img = f.outputImage ?? img
        }

        if g.vignette > 0.001, let f = CIFilter(name: "CIVignette") {
            f.setValue(img, forKey: kCIInputImageKey)
            f.setValue(g.vignette * 2.0, forKey: "inputIntensity")
            f.setValue(1.2, forKey: "inputRadius")
            img = f.outputImage ?? img
        }

        if g.clarity > 0.001, let f = CIFilter(name: "CIUnsharpMask") {
            f.setValue(img, forKey: kCIInputImageKey)
            f.setValue(g.clarity * 0.8, forKey: kCIInputIntensityKey)
            f.setValue(12.0, forKey: kCIInputRadiusKey)
            img = f.outputImage ?? img
        }

        if g.sharpness > 0.001, let f = CIFilter(name: "CISharpenLuminance") {
            f.setValue(img, forKey: kCIInputImageKey)
            f.setValue(g.sharpness * 0.7, forKey: kCIInputSharpnessKey)
            img = f.outputImage ?? img
        }

        return img.cropped(to: image.extent)
    }

    /// 颗粒：随机噪声压成灰度、放大成粗颗粒，再用软光叠回画面
    static func applyGrain(_ image: CIImage,
                           settings: GrainSettings,
                           scale multiplier: CGFloat = 1,
                           midtoneMasked: Bool = false) -> CIImage {
        let extent = image.extent
        guard extent.width > 1, extent.height > 1,
              let generator = CIFilter(name: "CIRandomGenerator")?.outputImage else { return image }

        let scale = max(1.0, settings.scale * max(0.4, multiplier) * 0.72)
        let smallW = max(1, extent.width / scale)
        let smallH = max(1, extent.height / scale)
        let originX = settings.offsetX * 800
        let originY = settings.offsetY * 800

        // 取一小块噪声再放大，得到成团的颗粒而不是逐像素的数码噪点。
        // 裁剪会保留原坐标，必须先平移回原点再放大，否则整块噪声落在画面外，
        // 叠上去等于没做（这个 bug 让第一版颗粒完全看不出来）。
        let cropRect = CGRect(x: originX, y: originY, width: smallW + 2, height: smallH + 2)
        var noise = generator
            .cropped(to: cropRect)
            .transformed(by: CGAffineTransform(translationX: -originX, y: -originY))

        if let m = CIFilter(name: "CIColorMatrix") {
            m.setValue(noise, forKey: kCIInputImageKey)
            m.setValue(CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0), forKey: "inputRVector")
            m.setValue(CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0), forKey: "inputGVector")
            m.setValue(CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0), forKey: "inputBVector")
            m.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            noise = m.outputImage ?? noise
        }

        noise = noise
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .clampedToExtent()

        // 强度靠把噪声往中灰压缩实现：越薄越接近纯灰，软光几乎看不出
        if let c = CIFilter(name: "CIColorControls") {
            c.setValue(noise, forKey: kCIInputImageKey)
            c.setValue(max(0.02, settings.intensity * 1.05), forKey: "inputContrast")
            noise = c.outputImage ?? noise
        }

        guard let blend = CIFilter(name: "CISoftLightBlendMode") else { return image }
        blend.setValue(noise.cropped(to: extent), forKey: kCIInputImageKey)
        blend.setValue(image, forKey: kCIInputBackgroundImageKey)
        let grained = (blend.outputImage ?? image).cropped(to: extent)

        guard midtoneMasked, let maskFilter = CIFilter(name: "CIBlendWithMask") else {
            return grained
        }
        // 中间调遮罩：min(2L, 2-2L)，等于 1-|2L-1|。
        // 高光和暗部都趋近 0，颗粒只落在中间调（真实胶片的分布）。
        let bright = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 2, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 2, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 2, w: 0)])
        let dark = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: -2, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: -2, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: -2, w: 0),
            "inputBiasVector": CIVector(x: 2, y: 2, z: 2, w: 0)])
        var mask = bright
        if let minFilter = CIFilter(name: "CIMinimumCompositing") {
            minFilter.setValue(bright, forKey: kCIInputImageKey)
            minFilter.setValue(dark, forKey: kCIInputBackgroundImageKey)
            mask = minFilter.outputImage ?? bright
        }
        // 转灰度 + 轻微模糊，避免颗粒边缘出现硬边
        mask = mask
            .applyingFilter("CIColorClamp")
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: max(2, extent.width * 0.004)])
            .cropped(to: extent)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.30, y: 0.30, z: 0.30, w: 0),
                "inputGVector": CIVector(x: 0.59, y: 0.59, z: 0.59, w: 0),
                "inputBVector": CIVector(x: 0.11, y: 0.11, z: 0.11, w: 0)])

        maskFilter.setValue(grained, forKey: kCIInputImageKey)
        maskFilter.setValue(image, forKey: kCIInputBackgroundImageKey)
        maskFilter.setValue(mask, forKey: kCIInputMaskImageKey)
        return (maskFilter.outputImage ?? grained).cropped(to: extent)
    }

    #if canImport(UIKit)
    /// 双重曝光：把 overlay 以"滤色 + 半透明"叠加到 base 之上（拍立得双曝风格）
    static func doubleExposure(base: UIImage, overlay: UIImage) -> UIImage {
        let size = base.size
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let c = ctx.cgContext
            base.draw(in: CGRect(origin: .zero, size: size))
            c.setAlpha(0.65)
            c.setBlendMode(.screen)
            overlay.draw(in: CGRect(origin: .zero, size: size))
        }
    }
    #endif

    private static func params(for preset: FilmPreset) -> FilterParams {
        switch preset {
        case .kodakGold:
            return FilterParams(proceduralColor: false, neutral: 4500, saturation: 1.0, contrast: 1.0,
                                brightness: 0.0, vignette: 0.6, vignetteRadius: 1.1,
                                leakColor: (1.0, 0.85, 0.5), leakAlpha: 0.25, lutIntensity: 0.9)
        case .fuji400:
            return FilterParams(proceduralColor: false, neutral: 5500, saturation: 1.0, contrast: 1.0,
                                brightness: 0.0, vignette: 0.5, vignetteRadius: 1.0,
                                leakColor: (0.5, 0.8, 1.0), leakAlpha: 0.20, lutIntensity: 0.9)
        case .classicBnw:
            return FilterParams(proceduralColor: true, neutral: 6500, saturation: 0.0, contrast: 1.10,
                                brightness: 0.0, vignette: 0.7, vignetteRadius: 1.2,
                                leakColor: (1.0, 1.0, 1.0), leakAlpha: 0.0, lutIntensity: 0.0)
        case .fadedCinema:
            return FilterParams(proceduralColor: true, neutral: 6000, saturation: 0.90, contrast: 0.90,
                                brightness: 0.05, vignette: 0.55, vignetteRadius: 1.05,
                                leakColor: (1.0, 0.7, 0.6), leakAlpha: 0.18, lutIntensity: 0.0)
        case .cinematic:
            return FilterParams(proceduralColor: false, neutral: 5200, saturation: 1.0, contrast: 1.0,
                                brightness: 0.0, vignette: 0.5, vignetteRadius: 1.0,
                                leakColor: (1.0, 0.85, 0.7), leakAlpha: 0.10, lutIntensity: 0.85)
        case .duskGold:
            return FilterParams(proceduralColor: false, neutral: 5200, saturation: 1.0, contrast: 1.0,
                                brightness: 0.0, vignette: 0.62, vignetteRadius: 1.15,
                                leakColor: (1.0, 0.78, 0.42), leakAlpha: 0.26, lutIntensity: 0.95)
        case .slate:
            return FilterParams(proceduralColor: false, neutral: 6000, saturation: 1.0, contrast: 1.0,
                                brightness: 0.0, vignette: 0.55, vignetteRadius: 1.05,
                                leakColor: (0.8, 0.85, 1.0), leakAlpha: 0.10, lutIntensity: 0.95)
        case .mint:
            return FilterParams(proceduralColor: false, neutral: 5800, saturation: 1.0, contrast: 1.0,
                                brightness: 0.0, vignette: 0.5, vignetteRadius: 1.0,
                                leakColor: (0.7, 1.0, 0.85), leakAlpha: 0.14, lutIntensity: 0.92)
        case .rust:
            return FilterParams(proceduralColor: false, neutral: 5400, saturation: 1.0, contrast: 1.0,
                                brightness: 0.0, vignette: 0.58, vignetteRadius: 1.1,
                                leakColor: (1.0, 0.6, 0.35), leakAlpha: 0.22, lutIntensity: 0.92)
        case .frost:
            return FilterParams(proceduralColor: false, neutral: 6200, saturation: 1.0, contrast: 1.0,
                                brightness: 0.0, vignette: 0.6, vignetteRadius: 1.1,
                                leakColor: (1.0, 1.0, 1.0), leakAlpha: 0.0, lutIntensity: 0.95)
        case .ochre:
            return FilterParams(proceduralColor: false, neutral: 5400, saturation: 1.0, contrast: 1.0,
                                brightness: 0.0, vignette: 0.55, vignetteRadius: 1.05,
                                leakColor: (1.0, 0.82, 0.55), leakAlpha: 0.20, lutIntensity: 0.92)
        case .abyss:
            return FilterParams(proceduralColor: false, neutral: 6100, saturation: 1.0, contrast: 1.0,
                                brightness: 0.0, vignette: 0.68, vignetteRadius: 1.2,
                                leakColor: (0.75, 0.85, 1.0), leakAlpha: 0.12, lutIntensity: 0.95)
        // 配方类预设：不用 LUT、不加暗角与漏光，全部交给参数化调色层
        case .neutral, .clear, .nightStreet, .fresh, .moody,
             .glowSkin, .cream, .warmSoft, .glowField,
             .sunsetFilm, .forestGreen, .snow, .vintageFilm:
            return FilterParams(proceduralColor: false, neutral: 6500, saturation: 1.0, contrast: 1.0,
                                brightness: 0.0, vignette: 0.0, vignetteRadius: 1.0,
                                leakColor: (1, 1, 1), leakAlpha: 0.0, lutIntensity: 0.0)
        }
    }
}
