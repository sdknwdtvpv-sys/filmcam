import SwiftUI
import ImageIO

/// 本地成片缩略图加载：ImageIO 下采样 + 内存缓存。
///
/// 旧实现直接用 `UIImage(contentsOfFile:)` 读原图，一张 12MP 的成片解码后约占 48MB，
/// 网格里十几张就能把 App 顶到被系统杀掉。这里统一按下采样尺寸解码，并复用缓存。
enum MediaThumbnailLoader {

    /// NSCache 自身线程安全；这里只是绕开「非 Sendable 静态存储」的编译限制
    nonisolated(unsafe) private static let cache = NSCache<NSString, UIImage>()

    private static func cacheKey(_ url: URL, _ maxPixel: CGFloat) -> String {
        "\(url.path)#\(Int(maxPixel))"
    }

    /// 异步取缩略图（在主线程回调）
    static func load(url: URL, maxPixel: CGFloat,
                     completion: @escaping @Sendable (UIImage?) -> Void) {
        let key = cacheKey(url, maxPixel)
        if let hit = cache.object(forKey: key as NSString) {
            DispatchQueue.main.async { completion(hit) }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let image = downsample(url: url, maxPixel: maxPixel)
            if let image { cache.setObject(image, forKey: key as NSString) }
            DispatchQueue.main.async { completion(image) }
        }
    }

    /// async 版本，配合 SwiftUI 的 .task 使用
    static func thumbnail(url: URL, maxPixel: CGFloat) async -> UIImage? {
        await withCheckedContinuation { continuation in
            load(url: url, maxPixel: maxPixel) { image in
                continuation.resume(returning: image)
            }
        }
    }

    /// 同步下采样（仅在后台线程调用）
    static func downsample(url: URL, maxPixel: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }

    /// 照片被删除后清空缓存，避免已删的图还留在内存里
    static func evictAll() {
        cache.removeAllObjects()
    }
}

/// 从本地文件异步加载的缩略图视图（带占位底色）
struct MediaThumbnail: View {
    let url: URL
    let maxPixel: CGFloat
    /// true = 铺满裁切（小方图用）；false = 完整显示（网格用）
    var fill: Bool = false

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.white.opacity(0.06)
            if let image {
                if fill {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
            }
        }
        .clipped()
        .task(id: url) {
            image = nil
            image = await MediaThumbnailLoader.thumbnail(url: url, maxPixel: maxPixel)
        }
    }
}
