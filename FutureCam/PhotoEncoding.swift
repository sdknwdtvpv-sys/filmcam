import UIKit
import ImageIO
import UniformTypeIdentifiers

/// 成片 JPEG 编码：把拍摄时的 EXIF/TIFF 原样带回去。
///
/// 之前直接把 UIImage 交给 Photos，重渲染后的位图没有任何元数据，
/// 系统相册里看不到机型、镜头、ISO、快门、GPS。
enum PhotoEncoding {

    /// 从已有文件里取出 EXIF / TIFF / GPS，重新编码时带回去
    static func metadata(of url: URL) -> [String: Any] {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any]
        else { return [:] }
        var out: [String: Any] = [:]
        for key in [kCGImagePropertyExifDictionary as String,
                    kCGImagePropertyTIFFDictionary as String,
                    kCGImagePropertyGPSDictionary as String] {
            if let value = props[key] { out[key] = value }
        }
        return out
    }

    static func jpeg(_ image: UIImage, metadata: [String: Any], quality: Double = 0.95) -> Data? {
        guard let cg = image.cgImage else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out,
                                                          UTType.jpeg.identifier as CFString,
                                                          1, nil) else { return nil }

        var props = metadata
        // 关掉地理标记时把 GPS 整段摘掉（隐私开关，默认开）
        if !UserDefaults.standard.bool(forKey: "futurecam.geotag.off") {
            // 保持原样
        } else {
            props.removeValue(forKey: kCGImagePropertyGPSDictionary as String)
        }
        // 像素已经转正，方向必须写 1，否则相册会再转一次
        props[kCGImagePropertyOrientation as String] = 1
        var tiff = (props[kCGImagePropertyTIFFDictionary as String] as? [String: Any]) ?? [:]
        tiff[kCGImagePropertyTIFFOrientation as String] = 1
        props[kCGImagePropertyTIFFDictionary as String] = tiff
        props[kCGImageDestinationLossyCompressionQuality as String] = quality

        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
