import SwiftUI

/// App 内语言切换。
///
/// 采用系统认的机制（写入 AppleLanguages），代价是要重新打开 App 才生效——
/// 尝试过 swizzle Bundle.localizedString，但 SwiftUI 的文本查找走的是
/// Core Foundation 的本地化路径，不经过这个 ObjC 方法，改不动。
/// 与其做一个「看似能切、其实只切一半」的假开关，不如把话说清楚。
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case chinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .chinese: return "中文"
        case .english: return "English"
        }
    }

    var code: String? {
        switch self {
        case .system: return nil
        case .chinese: return "zh-Hans"
        case .english: return "en"
        }
    }

    static let key = "futurecam.language"

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system
    }
}

@MainActor
final class LanguageStore: ObservableObject {
    static let shared = LanguageStore()

    @Published private(set) var language: AppLanguage
    /// 切过语言、还没重新打开时置位，界面上要提示
    @Published private(set) var pendingRestart = false

    private init() {
        language = AppLanguage.current
    }

    func set(_ new: AppLanguage) {
        guard new != language else { return }
        language = new
        UserDefaults.standard.set(new.rawValue, forKey: AppLanguage.key)

        // 系统认的语言覆盖：下次启动时生效
        if let code = new.code {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        pendingRestart = true
    }
}
