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

/// 实时胶片滤镜引擎（Core Image 链：色温 + 色彩控制 + 暗角 + 漏光 + 可插拔 3D LUT）
struct FilmFilter {
    static func apply(_ image: CIImage, preset: FilmPreset) -> CIImage {
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
            let center = CIVector(x: img.extent.midX, y: img.extent.midY)
            grad.setValue(center, forKey: "inputCenter")
            grad.setValue(NSNumber(value: Double(min(img.extent.width, img.extent.height) * 0.2)),
                          forKey: "inputRadius0")
            grad.setValue(NSNumber(value: Double(max(img.extent.width, img.extent.height))),
                          forKey: "inputRadius1")
            grad.setValue(CIColor(red: p.leakColor.r, green: p.leakColor.g, blue: p.leakColor.b,
                                 alpha: p.leakAlpha), forKey: "inputColor1")
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

        return img.cropped(to: image.extent)
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
