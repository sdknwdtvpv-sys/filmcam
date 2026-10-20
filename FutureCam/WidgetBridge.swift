import Foundation
import WidgetKit

/// 主 App 与 Widget 之间的桥：只共享"这卷还剩几张"这类非敏感摘要。
/// App Group 没配好时 Write 会静默失败，Widget 显示占位——不影响主 App。
enum WidgetBridge {
    static let groupID = "group.com.futurecam.app"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: groupID)
    }

    struct Snapshot: Codable {
        var film: String
        var rollNumber: Int
        var used: Int
        var capacity: Int
        var colorHex: String
        var updatedAt: Date
    }

    static func publish(film: String, rollNumber: Int, used: Int,
                        capacity: Int, colorHex: String) {
        let snapshot = Snapshot(film: film, rollNumber: rollNumber, used: used,
                                capacity: capacity, colorHex: colorHex, updatedAt: Date())
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: "futurecam.roll.snapshot")
        WidgetCenter.shared.reloadAllTimelines()
    }
}
