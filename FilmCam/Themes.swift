import SwiftUI

// MARK: - 令牌

/// 面板材质：拉丝阳极氧化铝
enum MaterialKind: Sendable {
    case brushed
}

/// 「测距仪」机身的全部可见变量
struct ThemeTokens: Sendable {
    let material: MaterialKind

    // 底色
    let background: Color
    let panel: Color
    let elevated: Color

    // 面板渐变（受光面 → 背光面）
    let faceTop: Color
    let faceBottom: Color

    // 凹陷井（取景窗、读数窗）
    let wellTop: Color
    let wellBottom: Color

    // 文字
    let ink: Color
    let inkDim: Color

    // 强调
    let accent: Color
    let accentDeep: Color
    let accentGlow: Color
    let glow: Color
    let hairline: Color
    let recRed: Color

    // 形状与密度
    let radius: CGFloat
    let hairWidth: CGFloat
    let inset: CGFloat

    // 字体
    let displayFont: @Sendable (CGFloat, Font.Weight) -> Font
    let labelFont: @Sendable (CGFloat, Font.Weight) -> Font
    let monoFont: @Sendable (CGFloat, Font.Weight) -> Font
}

extension ThemeTokens {
    /// 测距仪：铝盖 + 黑蒙皮 + 胭脂红标记
    static let rangefinder = ThemeTokens(
        material: .brushed,
        background: Color(hex: 0x1A1B1C),
        panel: Color(hex: 0xD7DBDE),
        elevated: Color(hex: 0xC2C7CB),
        faceTop: Color(hex: 0xEDF0F2),
        faceBottom: Color(hex: 0xAFB5BA),
        wellTop: Color(hex: 0x121314),
        wellBottom: Color(hex: 0x070808),
        ink: Color(hex: 0x1B1E20),
        inkDim: Color(hex: 0x1B1E20, opacity: 0.52),
        accent: Color(hex: 0xC0392B),
        accentDeep: Color(hex: 0x84241A),
        accentGlow: Color(hex: 0xFF6A5A),
        glow: Color(hex: 0xFF5C4A),
        hairline: Color(hex: 0x1B1E20, opacity: 0.2),
        recRed: Color(hex: 0xC0392B),
        radius: 6,
        hairWidth: 1,
        inset: 14,
        displayFont: { size, _ in .custom("Futura-Medium", size: size) },
        labelFont: { size, _ in .custom("Futura-Medium", size: size) },
        monoFont: { size, weight in .system(size: size, weight: weight, design: .monospaced) }
    )
}

// MARK: - 当前机身

enum ThemeStore {
    nonisolated(unsafe) static var current: ThemeTokens = .rangefinder
}
