import Foundation

/// 拍摄模式
enum CameraMode: String, CaseIterable, Identifiable {
    case photo
    case doubleExposure
    case video

    var id: String { rawValue }

    var label: String {
        switch self {
        case .photo: return "照片"
        case .doubleExposure: return "双曝"
        case .video: return "视频"
        }
    }

    /// 快门键上的三档线性排列：双曝 ← 照片 → 视频。
    /// 不循环——拖到头就停在档位尽头，不会绕回另一端。
    static let strip: [CameraMode] = [.doubleExposure, .photo, .video]

    /// 在这一排里的位置：0 双曝 / 1 照片 / 2 视频
    var stripIndex: Int {
        CameraMode.strip.firstIndex(of: self) ?? CameraMode.strip.firstIndex(of: .photo) ?? 1
    }

    /// 快门键横向拖拽 → 模式：往右拖是录像，往左拖回照片（再往左才是双曝）。
    /// `dragSteps` 正数向右、负数向左，每 26pt 一档，到两端夹住。
    func shifted(byDragSteps dragSteps: Int) -> CameraMode {
        let order = CameraMode.strip
        let target = min(max(stripIndex + dragSteps, 0), order.count - 1)
        return order[target]
    }
}
