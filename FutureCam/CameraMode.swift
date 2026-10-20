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

    /// 快门键横向拖拽 → 模式：往左拖是双曝，往右拖是视频。
    /// `dragSteps` 正数向右、负数向左，每 26pt 一档。
    func shifted(byDragSteps dragSteps: Int) -> CameraMode {
        cycled(steps: -dragSteps)
    }

    /// 从当前模式往前/往后数 steps 档（循环）
    func cycled(steps: Int) -> CameraMode {
        let all = CameraMode.allCases
        guard let index = all.firstIndex(of: self), !all.isEmpty else { return self }
        return all[((index + steps) % all.count + all.count) % all.count]
    }
}
