import CoreImage
import UIKit
import os

/// 胶片预设预览图：把一张「合成场景」（天空 / 太阳 / 地面 / 树影）送进真实的
/// `FilmFilter.apply` 滤镜链渲染成小图，让胶片选择弹层里的预览是「所见即所得」，
/// 而不是凭感觉配的色块。
enum FilmPreview {

    private static let context = CIContext()
    private static let cache = OSAllocatedUnfairLock<[FilmPreset: UIImage]>(initialState: [:])

    /// 取某预设的预览图（首次生成后缓存；线程安全）
    static func image(for preset: FilmPreset) -> UIImage? {
        if let hit = cache.withLock({ $0[preset] }) { return hit }
        let scene = FilmPreview.scene()
        let filtered = FilmFilter.apply(scene, preset: preset)
        guard let cg = context.createCGImage(filtered, from: scene.extent) else { return nil }
        let image = UIImage(cgImage: cg)
        cache.withLock { $0[preset] = image }
        return image
    }

    /// 合成一张 176×132 的小场景：蓝天渐变 + 暖色太阳 + 土地 + 一棵树影，
    /// 保证色温 / 饱和度 / LUT 的差异在缩略图上能看出来。
    private static func scene() -> CIImage {
        let w: CGFloat = 176, h: CGFloat = 132
        let rect = CGRect(x: 0, y: 0, width: w, height: h)

        let sky = CIImage(color: CIColor(red: 0.30, green: 0.50, blue: 0.80))
            .cropped(to: CGRect(x: 0, y: h * 0.30, width: w, height: h * 0.70))
        let ground = CIImage(color: CIColor(red: 0.47, green: 0.39, blue: 0.28))
            .cropped(to: CGRect(x: 0, y: 0, width: w, height: h * 0.30))
        let tree = CIImage(color: CIColor(red: 0.09, green: 0.13, blue: 0.09))
            .cropped(to: CGRect(x: w * 0.16, y: h * 0.30, width: 9, height: h * 0.34))

        var image = composite(tree, over: composite(sky, over: ground))

        // 太阳：径向渐变（中心暖白不透明 → 边缘透明）
        // 注意 CIRadialGradient 的 inputColor1 会向 inputRadius1 之外无限延伸，
        // 所以「透明色」必须放在 inputColor1（外圈），否则整张图被糊上一层暖色、
        // 只剩中心一个小孔透出底色（曾因此误判成"LUT 把太阳变蓝"）。
        if let sun = CIFilter(name: "CIRadialGradient") {
            sun.setValue(CIVector(x: w * 0.72, y: h * 0.74), forKey: "inputCenter")
            sun.setValue(NSNumber(value: 0.0), forKey: "inputRadius0")
            sun.setValue(NSNumber(value: 30.0), forKey: "inputRadius1")
            sun.setValue(CIColor(red: 1.0, green: 0.86, blue: 0.46, alpha: 1.0), forKey: "inputColor0")
            sun.setValue(CIColor(red: 1.0, green: 0.86, blue: 0.46, alpha: 0.0), forKey: "inputColor1")
            if let out = sun.outputImage {
                image = composite(out.cropped(to: rect), over: image)
            }
        }
        return image.cropped(to: rect)
    }

    /// 普通源覆盖合成（top 覆盖在 bottom 之上）
    private static func composite(_ top: CIImage, over bottom: CIImage) -> CIImage {
        guard let f = CIFilter(name: "CISourceOverCompositing") else { return bottom }
        f.setValue(top, forKey: kCIInputImageKey)
        f.setValue(bottom, forKey: kCIInputBackgroundImageKey)
        return f.outputImage ?? bottom
    }
}
