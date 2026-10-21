#if DEBUG
import Foundation
import UIKit
import SwiftUI
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

    /// `-fcShowGuide`：强制显示首跑引导，方便截图（模拟器里没有相机授权）
    static var shouldShowGuide: Bool { arguments.contains("-fcShowGuide") }

    /// `-fcSkipGuide`：把引导标记为已看过，方便截其它界面
    static var shouldSkipGuide: Bool { arguments.contains("-fcSkipGuide") }

    /// `-fcLaunchStyle noise|engraved`：切换开机页刻字的出场方式
    static var launchStyle: LaunchIntroStyle? {
        guard let index = arguments.firstIndex(of: "-fcLaunchStyle"),
              index + 1 < arguments.count else { return nil }
        switch arguments[index + 1] {
        case "noise": return .noise
        case "engraved": return .engraved
        default: return nil
        }
    }

    /// `-fcLaunchT 0.4`：把开机页进度钉死，方便逐帧截图
    static var launchProgress: CGFloat? {
        guard let index = arguments.firstIndex(of: "-fcLaunchT"),
              index + 1 < arguments.count,
              let value = Double(arguments[index + 1]) else { return nil }
        return CGFloat(value)
    }

    /// `-fcSimulateShot 5`：直接记 5 张，用来验证张数/满卷，不需要真相机
    static var simulateShots: Int? {
        guard let index = arguments.firstIndex(of: "-fcSimulateShot"),
              index + 1 < arguments.count else { return nil }
        return Int(arguments[index + 1])
    }

    /// `-fcLanguage en|zh`：启动时切界面语言（走和设置里同一个入口）
    static var languageArgument: AppLanguage? {
        guard let value = value(for: "-fcLanguage") else { return nil }
        switch value {
        case "en": return .english
        case "zh", "zh-Hans": return .chinese
        case "system": return .system
        default: return nil
        }
    }

    /// `-fcResetRollNumber`：把当前这卷的卷号复位成 1
    static var shouldResetRollNumber: Bool { arguments.contains("-fcResetRollNumber") }

    /// `-fcDateStampProbe`：把成片写到沙盒，用于像素级检查日期背印
    static func value(for flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    static var shouldProbeDateStamp: Bool { arguments.contains("-fcDateStampProbe") }

    /// `-fcGrainCard`：颗粒对照卡（同一张底片在三个 ISO 下过一遍滤镜）
    static var shouldShowGrainCard: Bool { arguments.contains("-fcGrainCard") }

    /// `-fcSeedAlbum`：造两卷示范成片，验证相册按卷分组
    static var shouldSeedAlbum: Bool { arguments.contains("-fcSeedAlbum") }

    /// `-fcHoldLaunch`：开机页停在最后一帧，方便截图
    static var shouldHoldLaunch: Bool { arguments.contains("-fcHoldLaunch") }

    /// `-fcGuideStep 3`：引导直接从第 3 步开始，方便逐步截图
    static var guideStep: Int {
        guard let index = arguments.firstIndex(of: "-fcGuideStep"),
              index + 1 < arguments.count,
              let value = Int(arguments[index + 1]) else { return 0 }
        return max(0, value - 1)
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
        if shouldSkipGuide {
            UserDefaults.standard.set(true, forKey: "futurecam.seenGuide.v2")
        }
        if shouldShowGuide {
            UserDefaults.standard.set(false, forKey: "futurecam.seenGuide.v2")
        }

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
        case "privacy": manager.showPrivacyPolicy = true
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

/// 颗粒对照卡：同一张底片在三个 ISO 下过一遍真实滤镜链，1:1 显示以便看清颗粒
struct GrainTestCard: View {
    @State private var images: [UIImage] = []
    @State private var sigmas: [String] = []

    private let isos: [Double] = [100, 800, 3200]

    var body: some View {
        ZStack {
            Color(white: 0.12).ignoresSafeArea()
            VStack(spacing: 8) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                    HStack(spacing: 8) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("ISO \(Int(isos[index]))")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.7))
                            Text(sigmas.count > index ? sigmas[index] : "--")
                                .font(.system(size: 8, weight: .regular, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .frame(width: 62, alignment: .trailing)
                        Image(uiImage: image)
                            .interpolation(.none)
                    }
                }
            }
            .padding(.vertical, 20)
        }
        .task {
            let rendered = isos.map(render(iso:))
            images = rendered
            sigmas = rendered.map(Self.grainSigma)
        }
    }

    private func render(iso: Double) -> UIImage {
        let size = CGSize(width: 300, height: 300)
        guard let base = Self.scene(size: size) else { return UIImage() }
        let traits = RollTraits(seed: 42)
        let grain = GrainSettings.make(iso: iso, traits: traits, seed: 42)
        let out = FilmFilter.apply(base, preset: .kodakGold, traits: traits, grain: grain)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cg = context.createCGImage(out, from: out.extent) else { return UIImage() }
        return UIImage(cgImage: cg)
    }

    /// 局部标准差：颗粒越强，σ 越大。用来在没有肉眼判断的情况下确认颗粒真的存在
    private static func grainSigma(_ image: UIImage) -> String {
        guard let cg = image.cgImage else { return "--" }
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return "--" }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        // 相邻像素差：渐变本身几乎是常数，只有颗粒才会让差值跳动
        let x0 = w / 4, x1 = w * 3 / 4, y0 = h / 4, y1 = h * 3 / 4
        var sum = 0.0, n = 0.0
        for y in y0..<y1 {
            for x in x0..<(x1 - 1) {
                sum += abs(Double(pixels[y * w + x + 1]) - Double(pixels[y * w + x]))
                n += 1
            }
        }
        guard n > 0 else { return "--" }
        return String(format: "d%.2f", sum / n)
    }

    /// 一张有平滑渐变和中间调的底片，颗粒最容易被看出来
    private static func scene(size: CGSize) -> CIImage? {
        let extent = CGRect(origin: .zero, size: size)
        guard let grad = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: size.height),
            "inputPoint1": CIVector(x: size.width, y: 0),
            "inputColor0": CIColor(red: 0.55, green: 0.42, blue: 0.28),
            "inputColor1": CIColor(red: 0.22, green: 0.32, blue: 0.40)
        ])?.outputImage else { return nil }

        guard let radial = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: size.width * 0.62, y: size.height * 0.58),
            "inputRadius0": 10,
            "inputRadius1": size.width * 0.55,
            "inputColor0": CIColor(red: 0.95, green: 0.86, blue: 0.70, alpha: 0.55),
            "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        ])?.outputImage else { return nil }

        guard let blend = CIFilter(name: "CISoftLightBlendMode", parameters: [
            kCIInputImageKey: radial,
            kCIInputBackgroundImageKey: grad
        ])?.outputImage else { return nil }

        return blend.cropped(to: extent)
    }
}

#endif
