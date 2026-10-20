#if DEBUG
import Foundation
import UIKit
import CoreImage

/// 仅 Debug 构建的开发自检口子：模拟器没有相机、也没法脚本点击，
/// 靠启动参数直达某个界面 / 塞一帧合成预览，方便截图检查布局。
///
///     -fcScreen album|albumDetail|film|settings
///     -fcMode video|double|photo   启动即切到某个拍摄模式（检查快门键模式符号）
///     -fcStubPreview        合成一帧假预览（仅用于布局自检，绝不能用于商店截图）
///
/// Release 构建里整个文件不参与编译。
enum DebugHarness {

    private static var arguments: [String] { ProcessInfo.processInfo.arguments }

    /// 取 `-fcScreen xxx` 的值
    static func screenArgument() -> String? {
        guard let index = arguments.firstIndex(of: "-fcScreen"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static var shouldStubPreview: Bool { arguments.contains("-fcStubPreview") }

    /// 取 `-fcMode xxx` 的值
    static func modeArgument() -> String? {
        guard let index = arguments.firstIndex(of: "-fcMode"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// `-fcShowHUD`：启动即浮出参数读数，方便截图检查（模拟器没法脚本拖动）
    static var shouldShowHUD: Bool { arguments.contains("-fcShowHUD") }

    /// `-fcShowDeveloping`：启动即弹显影层（用合成图），方便截图检查
    static var shouldShowDeveloping: Bool { arguments.contains("-fcShowDeveloping") }

    /// `-fcTestEXIF`：用真实编码器写一张带 EXIF 的样片到 Documents，供外部核对元数据
    static var shouldTestEXIF: Bool { arguments.contains("-fcTestEXIF") }

    /// `-fcPull 0.6`：把撕拉片定格在拉出 60%，方便截图检查
    static var pullArgument: Double? {
        guard let index = arguments.firstIndex(of: "-fcPull"), index + 1 < arguments.count else { return nil }
        return Double(arguments[index + 1])
    }

    static func writeEXIFSample() {
        guard let image = stubPreviewFrame() else { return }
        let metadata: [String: Any] = [
            kCGImagePropertyTIFFDictionary as String: [
                kCGImagePropertyTIFFMake as String: "Apple",
                kCGImagePropertyTIFFModel as String: "iPhone 18 Pro",
            ],
            kCGImagePropertyExifDictionary as String: [
                kCGImagePropertyExifISOSpeedRatings as String: [200],
                kCGImagePropertyExifExposureTime as String: 1.0 / 60,
                kCGImagePropertyExifFNumber as String: 1.78,
                kCGImagePropertyExifLensModel as String: "iPhone 18 Pro back camera 6.86mm f/1.78",
                kCGImagePropertyExifDateTimeOriginal as String: "2026:10:21 01:20:00",
            ],
        ]
        guard let data = PhotoEncoding.jpeg(image, metadata: metadata) else { return }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("exif-sample.jpg")
        try? data.write(to: url)
        print("[FutureCam] EXIF sample written:", url.path)
    }

    /// 启动时按参数切到指定界面
    @MainActor
    static func applyLaunchState(_ manager: CameraManager) {
        switch modeArgument() {
        case "photo": manager.mode = .photo
        case "double": manager.mode = .doubleExposure
        case "video": manager.mode = .video
        default: break
        }

        guard let screen = screenArgument() else { return }
        switch screen {
        case "album", "albumDetail", "albumPhoto": manager.showAlbum = true
        case "film": manager.showFilmSheet = true
        case "settings": manager.showSettingsSheet = true
        default: break
        }
    }

    /// 合成一张 1080×1920 的竖版"场景"：天空渐变 + 太阳 + 地面 + 剪影树。
    /// 只是给没有相机的模拟器垫一张底图，用来检查叠加层可读性。
    static func stubPreviewFrame() -> UIImage? {
        let size = CGSize(width: 1080, height: 1920)
        var image = CIImage(color: CIColor(red: 0.35, green: 0.45, blue: 0.55))
            .cropped(to: CGRect(origin: .zero, size: size))

        if let gradient = CIFilter(name: "CILinearGradient") {
            gradient.setValue(CIVector(x: 0, y: size.height), forKey: "inputPoint0")
            gradient.setValue(CIVector(x: 0, y: size.height * 0.35), forKey: "inputPoint1")
            gradient.setValue(CIColor(red: 0.16, green: 0.24, blue: 0.38), forKey: "inputColor0")
            gradient.setValue(CIColor(red: 0.84, green: 0.64, blue: 0.42), forKey: "inputColor1")
            if let out = gradient.outputImage {
                image = out.cropped(to: CGRect(origin: .zero, size: size))
            }
        }

        if let sun = CIFilter(name: "CIRadialGradient") {
            sun.setValue(CIVector(x: size.width * 0.68, y: size.height * 0.62), forKey: "inputCenter")
            sun.setValue(NSNumber(value: 0), forKey: "inputRadius0")
            sun.setValue(NSNumber(value: 190), forKey: "inputRadius1")
            sun.setValue(CIColor(red: 1.0, green: 0.92, blue: 0.72, alpha: 1.0), forKey: "inputColor0")
            sun.setValue(CIColor(red: 1.0, green: 0.92, blue: 0.72, alpha: 0.0), forKey: "inputColor1")
            if let out = sun.outputImage, let blend = CIFilter(name: "CIScreenBlendMode") {
                blend.setValue(out.cropped(to: image.extent), forKey: kCIInputImageKey)
                blend.setValue(image, forKey: kCIInputBackgroundImageKey)
                if let merged = blend.outputImage { image = merged }
            }
        }

        if let shade = CIFilter(name: "CIConstantColorGenerator") {
            shade.setValue(CIColor(red: 0.09, green: 0.10, blue: 0.09), forKey: "inputColor")
            if let out = shade.outputImage?.cropped(to: CGRect(x: 0, y: 0,
                                                              width: size.width,
                                                              height: size.height * 0.28)),
               let over = CIFilter(name: "CISourceOverCompositing") {
                over.setValue(out, forKey: kCIInputImageKey)
                over.setValue(image, forKey: kCIInputBackgroundImageKey)
                if let merged = over.outputImage { image = merged }
            }
        }

        let context = CIContext()
        guard let cg = context.createCGImage(image, from: CGRect(origin: .zero, size: size)) else { return nil }
        return UIImage(cgImage: cg)
    }
}
#endif
