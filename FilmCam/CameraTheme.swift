import SwiftUI

/// 设计系统：复古机顶 · 琥珀（Retro camera-top · Amber）
///
/// 统一承载 FilmCam 的视觉令牌（配色 / 字体 / 仪表质感），
/// 让所有界面元素从「占位橙黑」升级为一致的机顶仪表风格。
enum CameraTheme {

    // MARK: - 配色

    /// 取景器后方最深的底（暖调近黑）
    static let bgDeep     = Color(hex: 0x0E0E0C)
    /// 暖炭灰面板（机顶铭牌 / 控件底）
    static let bgPanel    = Color(hex: 0x1A1815)
    /// 控件 / 胶片标签的抬升面
    static let bgElevated = Color(hex: 0x23201B)
    /// 按压态
    static let bgPressed  = Color(hex: 0x2E2A23)

    /// 主琥珀色（读数 / 描边 / 选中态）
    static let amber      = Color(hex: 0xE8A030)
    /// 琥珀辉光（用于铭牌 / REC 的发光感）
    static let amberGlow  = Color(hex: 0xF6C067)
    /// 琥珀暗部（径向渐变用）
    static let amberDeep  = Color(hex: 0xC77F1E)

    /// 暖白正文
    static let ink        = Color(hex: 0xF3ECE0)
    /// 次级文字
    static let inkDim     = Color(hex: 0xF3ECE0).opacity(0.55)
    /// 琥珀细发丝线（机顶接缝 / 描边）
    static let hairline   = Color(hex: 0xE8A030).opacity(0.22)

    /// 通用危险/录制红（REC、录制态快门）
    static let recRed     = Color(hex: 0xE5484D)

    // MARK: - 字体

    /// 等宽字体（仪表读数的灵魂）
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
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
