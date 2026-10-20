import SwiftUI
import ImageIO
import AVFoundation

/// 本地媒体缩略图加载：ImageIO / AVAssetImageGenerator 下采样 + 内存缓存。
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

    /// 照片走 async 版本
    static func thumbnail(url: URL, maxPixel: CGFloat) async -> UIImage? {
        await withCheckedContinuation { continuation in
            load(url: url, maxPixel: maxPixel) { image in
                continuation.resume(returning: image)
            }
        }
    }

    /// 视频取首帧（异步 API，不阻塞主线程）
    static func videoThumbnail(url: URL, maxPixel: CGFloat) async -> UIImage? {
        let key = cacheKey(url, maxPixel)
        if let hit = cache.object(forKey: key as NSString) { return hit }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.3, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.3, preferredTimescale: 600)
        do {
            let (cg, _) = try await generator.image(at: CMTime(seconds: 0.1, preferredTimescale: 600))
            let image = UIImage(cgImage: cg)
            cache.setObject(image, forKey: key as NSString)
            return image
        } catch {
            return nil
        }
    }

    /// 按媒体类型取缩略图
    static func thumbnail(for item: AlbumItem, maxPixel: CGFloat) async -> UIImage? {
        switch item.kind {
        case .photo: return await thumbnail(url: item.url, maxPixel: maxPixel)
        case .video: return await videoThumbnail(url: item.url, maxPixel: maxPixel)
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

/// 从本地文件异步加载的缩略图视图（带占位底色，视频叠播放角标）
struct MediaThumbnail: View {
    let item: AlbumItem
    let maxPixel: CGFloat
    /// true = 铺满裁切（小方图用）；false = 完整显示（网格用）
    var fill: Bool = false

    @State private var image: UIImage?

    var body: some View {
        // 用 Color 当尺寸载体、图片放进 overlay，再在 Color 边界裁剪。
        // 直接给 scaledToFill 的图片加 .clipped() 不可靠：
        // 竖版视频按宽铺满后会撑出容器，父级没有 clipShape 的地方就会溢出。
        ZStack {
            if let image {
                if fill {
                    Color.clear
                        .overlay { Image(uiImage: image).resizable().scaledToFill() }
                        .clipped()
                } else {
                    Color.clear
                        .overlay { Image(uiImage: image).resizable().scaledToFit() }
                }
            } else {
                Color.white.opacity(0.06)
            }

            if item.kind == .video {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.5), radius: 3)
            }
        }
        .task(id: item.url) {
            image = nil
            image = await MediaThumbnailLoader.thumbnail(for: item, maxPixel: maxPixel)
        }
    }
}
