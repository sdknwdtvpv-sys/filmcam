import Foundation
import UIKit

/// 应用内相册的本地存储层：照片与视频各占 Documents 下一个目录。
/// 全部方法都是同步的，调用方负责放到后台线程。
enum AlbumStore {

    static let photosFolder = "futurecam_photos"
    static let videosFolder = "futurecam_videos"

    private static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var photosURL: URL { documentsURL.appendingPathComponent(photosFolder, isDirectory: true) }
    static var videosURL: URL { documentsURL.appendingPathComponent(videosFolder, isDirectory: true) }

    // MARK: - 读取

    /// 旧版本（FilmCam 时期）的沙盒目录迁移，避免改名后老照片消失
    private static func migrateLegacyFoldersIfNeeded() {
        let fm = FileManager.default
        let pairs = [("filmcam_photos", photosFolder), ("filmcam_videos", videosFolder)]
        for (old, new) in pairs {
            let from = documentsURL.appendingPathComponent(old, isDirectory: true)
            let to = documentsURL.appendingPathComponent(new, isDirectory: true)
            guard fm.fileExists(atPath: from.path),
                  !fm.fileExists(atPath: to.path) else { continue }
            try? fm.moveItem(at: from, to: to)
        }
    }

    /// 扫描两个目录，按时间倒序返回（最新在前）
    static func loadAll() -> [AlbumItem] {
        migrateLegacyFoldersIfNeeded()
        let photos = items(in: photosURL, ext: "jpg") { name, url in
            AlbumItem(id: name, url: url, kind: .photo,
                      createdAt: timestamp(from: name, fallback: url), rollID: rollID(from: name))
        }
        let videos = items(in: videosURL, ext: "mov") { name, url in
            AlbumItem(id: name, url: url, kind: .video,
                      createdAt: timestamp(from: name, fallback: url), rollID: rollID(from: name))
        }
        return (photos + videos).sorted { $0.createdAt > $1.createdAt }
    }

    private static func items(in dir: URL, ext: String,
                              make: (String, URL) -> AlbumItem) -> [AlbumItem] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        return files
            .filter { $0.pathExtension.lowercased() == ext }
            .map { make($0.lastPathComponent, $0) }
    }

    /// 文件名里带毫秒时间戳（fc_r1a2b_1740000000000.jpg），取最后一段数字；
    /// 解析失败则退回文件修改时间
    private static func timestamp(from name: String, fallback url: URL) -> Date {
        let stem = (name as NSString).deletingPathExtension
        let trailing = stem.reversed().prefix { $0.isNumber }.reversed()
        if let ms = Double(String(trailing)), ms > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: ms / 1000)
        }
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? .distantPast
    }

    /// 从文件名里取卷 id：fc_<rollID>_<毫秒>.jpg / .mov
    static func rollID(from name: String) -> String? {
        let parts = name.split(separator: "_")
        guard parts.count >= 3, parts[0] == "fc" else { return nil }
        return String(parts[1])
    }

    static func fileURL(id: String, kind: AlbumMediaKind) -> URL {
        let dir = kind == .photo ? photosURL : videosURL
        return dir.appendingPathComponent(id)
    }

    // MARK: - 写入

    @discardableResult
    static func savePhoto(_ image: UIImage, jpeg: Data? = nil, rollID: String? = nil) -> AlbumItem? {
        try? FileManager.default.createDirectory(at: photosURL, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let name = rollID.map { "fc_\($0)_\(stamp).jpg" } ?? "futurecam_\(stamp).jpg"
        let url = photosURL.appendingPathComponent(name)
        guard let data = jpeg ?? image.jpegData(compressionQuality: 0.9) else { return nil }
        do {
            try data.write(to: url)
            return AlbumItem(id: name, url: url, kind: .photo, createdAt: Date(), rollID: rollID)
        } catch {
            return nil
        }
    }

    /// 把录制完成的临时文件复制进相册目录（tmp 文件随时可能被系统清掉）
    @discardableResult
    static func saveVideo(from tmpURL: URL, rollID: String? = nil) -> AlbumItem? {
        try? FileManager.default.createDirectory(at: videosURL, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let name = rollID.map { "fc_\($0)_\(stamp).mov" } ?? "futurecam_\(stamp).mov"
        let url = videosURL.appendingPathComponent(name)
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.copyItem(at: tmpURL, to: url)
            return AlbumItem(id: name, url: url, kind: .video, createdAt: Date(), rollID: rollID)
        } catch {
            NSLog("[FutureCam] 视频落地失败: \(error.localizedDescription)")
            return nil
        }
    }

    /// 用新的 JPEG 覆盖同一张（换调色后重写，不产生第二张）
    @discardableResult
    static func overwrite(_ item: AlbumItem, jpeg: Data) -> Bool {
        do {
            try jpeg.write(to: item.url, options: .atomic)
            return true
        } catch {
            NSLog("[FutureCam] 覆盖成片失败: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - 删除

    /// 只删本地沙盒里的文件；系统「照片」App 里的副本不受影响（写入是 addOnly 权限）
    static func delete(_ item: AlbumItem) {
        try? FileManager.default.removeItem(at: item.url)
    }
}
