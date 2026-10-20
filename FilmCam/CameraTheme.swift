import SwiftUI

/// 设计令牌的读取入口。
///
/// 三套主题（暗房工单 / 测光台 / 胶片带）共用同一批语义名，
/// 具体取值由 `ThemeStore.current` 决定 —— 相册、弹层、提示条这些
/// 共享界面不需要知道当前是哪套主题。
///
/// 新代码请直接用 `ThemeStore.current` 里更完整的令牌（字体族、圆角、密度）；
/// 这里保留旧名字是为了让已有页面继续工作。
enum CameraTheme {

    // MARK: - 当前主题

    static var tokens: ThemeTokens { ThemeStore.current }

    // MARK: - 配色

    /// 页面底色
    static var bgDeep: Color { tokens.background }
    /// 面板 / 弹层
    static var bgPanel: Color { tokens.panel }
    /// 抬升面（卡片、输入框）
    static var bgElevated: Color { tokens.elevated }
    /// 按压态
    static var bgPressed: Color { tokens.elevated }

    /// 主强调色（选中 / 读数 / 描边）
    static var amber: Color { tokens.accent }
    /// 强调高光
    static var amberGlow: Color { tokens.accentGlow }
    /// 强调暗部
    static var amberDeep: Color { tokens.accentDeep }

    /// 正文
    static var ink: Color { tokens.ink }
    /// 次级文字
    static var inkDim: Color { tokens.inkDim }
    /// 发丝线
    static var hairline: Color { tokens.hairline }

    /// 录制红
    static var recRed: Color { tokens.recRed }

    // MARK: - 字体

    /// 微标签 / 读数：等宽
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        tokens.monoFont(size, weight)
    }

    /// 展示字体（各主题的字族不同）
    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        tokens.displayFont(size, weight)
    }

    /// 标签字体（字距、大小写各不相同）
    static func label(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        tokens.labelFont(size, weight)
    }
}

extension Color {
    /// 由 0xRRGGBB 构造颜色（不透明）
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}
