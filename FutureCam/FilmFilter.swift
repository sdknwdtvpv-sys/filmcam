import CoreImage
import UIKit

/// 胶片预设（照片滤镜 & 视频 LUT 共用的风格定义）
enum FilmPreset: String, CaseIterable, Identifiable {
    case kodakGold
    case fuji400
    case classicBnw
    case fadedCinema
    case cinematic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .kodakGold:   return "柯达金 200"
        case .fuji400:     return "富士 400"
        case .classicBnw:  return "经典黑白"
        case .fadedCinema: return "褪色电影"
        case .cinematic:   return "电影 LUT"
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

        // 5. 这卷的轻微偏色（±160K 以内，只做连续性不做风格）
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
        }
    }
}
