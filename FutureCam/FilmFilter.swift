import CoreImage
import UIKit

/// 胶片预设（照片滤镜 & 视频 LUT 共用的风格定义）
enum FilmPreset: String, CaseIterable, Identifiable {
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

    var id: String { rawValue }

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
        }
    }

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
    static func apply(_ image: CIImage, preset: FilmPreset,
                      traits: RollTraits? = nil,
                      grain: GrainSettings = .none) -> CIImage {
        let p = params(for: preset)
        var img = image

        // 1. 内置色温 + 色彩控制（LUT 预设默认关闭，由 LUT 主导色调）
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

        // 2. 暗角
        if let f = CIFilter(name: "CIVignette") {
            f.setValue(img, forKey: kCIInputImageKey)
            f.setValue(p.vignette, forKey: "inputIntensity")
            f.setValue(p.vignetteRadius, forKey: "inputRadius")
            if let out = f.outputImage { img = out }
        }

        // 3. 漏光（径向渐变 + 滤色混合）
        if p.leakAlpha > 0,
           let grad = CIFilter(name: "CIRadialGradient") {
            // 漏光位置由这卷的种子决定，同一卷每张都在同一个角落泛光
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

        // 4. 3D LUT（CC0 HaldCLUT，强度可调，由 LUTFilter 解析并缓存）
        if p.lutIntensity > 0,
           let lut = LUTFilter.resolvedLUT(for: preset, intensity: Float(p.lutIntensity)) {
            img = LUTFilter.apply(lut, to: img)
        }

        // 5. 参数化调色（照片 App 那套滑块）
        if let grade = preset.grade {
            img = applyGrade(img, grade)
        }

        // 5b. 这卷的轻微偏色（±160K 以内，只做连续性不做风格）
        if let traits, abs(traits.tintShift) > 0.05,
           let f = CIFilter(name: "CITemperatureAndTint") {
            f.setValue(img, forKey: kCIInputImageKey)
            f.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            f.setValue(CIVector(x: 6500 - traits.tintShift * 160, y: 0), forKey: "inputTargetNeutral")
            if let out = f.outputImage { img = out }
        }

        // 6. 颗粒。
        // 必须先裁回原尺寸：漏光用的是无穷大的径向渐变，混合之后 extent 会变成 ∞，
        // 颗粒按 ∞ 尺寸生成就完全落不到画面上（这个坑让第一版颗粒彻底不可见）。
        if grain.intensity > 0.001 {
            img = applyGrain(img.cropped(to: image.extent), settings: grain)
        }

        return img.cropped(to: image.extent)
    }

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
    static func applyGrain(_ image: CIImage, settings: GrainSettings) -> CIImage {
        let extent = image.extent
        guard extent.width > 1, extent.height > 1,
              let generator = CIFilter(name: "CIRandomGenerator")?.outputImage else { return image }

        let scale = max(1.0, settings.scale)
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
            c.setValue(max(0.02, settings.intensity * 1.8), forKey: "inputContrast")
            noise = c.outputImage ?? noise
        }

        guard let blend = CIFilter(name: "CISoftLightBlendMode") else { return image }
        blend.setValue(noise.cropped(to: extent), forKey: kCIInputImageKey)
        blend.setValue(image, forKey: kCIInputBackgroundImageKey)
        return (blend.outputImage ?? image).cropped(to: extent)
    }

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
        case .clear, .nightStreet, .fresh, .moody:
            return FilterParams(proceduralColor: false, neutral: 6500, saturation: 1.0, contrast: 1.0,
                                brightness: 0.0, vignette: 0.0, vignetteRadius: 1.0,
                                leakColor: (1, 1, 1), leakAlpha: 0.0, lutIntensity: 0.0)
        }
    }
}
