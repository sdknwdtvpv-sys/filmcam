import SwiftUI

// MARK: - 主题标识

enum ThemeID: String, CaseIterable, Identifiable {
    case precision
    case cockpit
    case rig

    var id: String { rawValue }

    var tokens: ThemeTokens {
        switch self {
        case .precision: return .precision
        case .cockpit:   return .cockpit
        case .rig:       return .rig
        }
    }
}

/// 面板材质：决定底纹、高光走向与颗粒
enum MaterialKind: Sendable {
    /// 拉丝阳极氧化铝（横向细纹）
    case brushed
    /// 喷砂石墨（细微颗粒 + 冷光）
    case graphite
    /// 碳纤编织 + 机加工边
    case carbon
}

// MARK: - 令牌

struct ThemeTokens: Sendable {
    let id: ThemeID
    let name: String
    let blurb: String
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
    /// LED 发光色
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

// MARK: - 三套工业主题

extension ThemeTokens {

    /// A · 精密仪器：拉丝铝面板，橙色安全标记，滚花转盘
    static let precision = ThemeTokens(
        id: .precision,
        name: "精密仪器",
        blurb: "拉丝铝机身，读数窗与滚花转盘",
        material: .brushed,
        background: Color(hex: 0xB4B9BE),
        panel: Color(hex: 0xC9CED2),
        elevated: Color(hex: 0xDFE3E6),
        faceTop: Color(hex: 0xE6EAED),
        faceBottom: Color(hex: 0xADB3B9),
        wellTop: Color(hex: 0x2E3338),
        wellBottom: Color(hex: 0x1A1E22),
        ink: Color(hex: 0x1D2125),
        inkDim: Color(hex: 0x1D2125, opacity: 0.5),
        accent: Color(hex: 0xE85D1F),
        accentDeep: Color(hex: 0xA83F11),
        accentGlow: Color(hex: 0xFF8A4A),
        glow: Color(hex: 0xFF7A33),
        hairline: Color(hex: 0x1D2125, opacity: 0.22),
        recRed: Color(hex: 0xC8321F),
        radius: 7,
        hairWidth: 1,
        inset: 14,
        displayFont: { size, _ in .custom("DINAlternate-Bold", size: size) },
        labelFont: { size, weight in .custom("DINAlternate-Bold", size: size) },
        monoFont: { size, weight in .system(size: size, weight: weight, design: .monospaced) }
    )

    /// B · 驾驶舱：喷砂石墨 + 凹陷仪表井 + 青色 LED
    static let cockpit = ThemeTokens(
        id: .cockpit,
        name: "驾驶舱",
        blurb: "石墨仪表台，凹玻璃井，LED 读数条",
        material: .graphite,
        background: Color(hex: 0x0C0F11),
        panel: Color(hex: 0x171B1F),
        elevated: Color(hex: 0x242B31),
        faceTop: Color(hex: 0x262E34),
        faceBottom: Color(hex: 0x11161A),
        wellTop: Color(hex: 0x05070A),
        wellBottom: Color(hex: 0x0A0E12),
        ink: Color(hex: 0xD6DEE4),
        inkDim: Color(hex: 0xD6DEE4, opacity: 0.46),
        accent: Color(hex: 0x3FD8D2),
        accentDeep: Color(hex: 0x1B7E7A),
        accentGlow: Color(hex: 0x8AF6F1),
        glow: Color(hex: 0x5FF3EC),
        hairline: Color(hex: 0xD6DEE4, opacity: 0.14),
        recRed: Color(hex: 0xFF5A4E),
        radius: 4,
        hairWidth: 1,
        inset: 12,
        displayFont: { size, _ in .custom("Menlo-Bold", size: size) },
        labelFont: { size, weight in .system(size: size, weight: weight, design: .monospaced) },
        monoFont: { size, weight in .system(size: size, weight: weight, design: .monospaced) }
    )

    /// C · 模块机架：碳纤 + 机加工铝框 + 红色标记 + 大镜头环
    static let rig = ThemeTokens(
        id: .rig,
        name: "模块机架",
        blurb: "碳纤机身，铝框，镜头环快门",
        material: .carbon,
        background: Color(hex: 0x07080A),
        panel: Color(hex: 0x13161A),
        elevated: Color(hex: 0x1E2227),
        faceTop: Color(hex: 0x22272D),
        faceBottom: Color(hex: 0x0C0E11),
        wellTop: Color(hex: 0x040506),
        wellBottom: Color(hex: 0x08090C),
        ink: Color(hex: 0xECEEF1),
        inkDim: Color(hex: 0xECEEF1, opacity: 0.45),
        accent: Color(hex: 0xE23A2E),
        accentDeep: Color(hex: 0x8C1C14),
        accentGlow: Color(hex: 0xFF6A5E),
        glow: Color(hex: 0xFF4A3D),
        hairline: Color(hex: 0xFFFFFF, opacity: 0.12),
        recRed: Color(hex: 0xFF3B2F),
        radius: 10,
        hairWidth: 1,
        inset: 13,
        displayFont: { size, _ in .custom("HelveticaNeue-CondensedBold", size: size) },
        labelFont: { size, weight in .custom("HelveticaNeue-Medium", size: size) },
        monoFont: { size, weight in .system(size: size, weight: weight, design: .monospaced) }
    )
}

// MARK: - 当前主题

enum ThemeStore {
    nonisolated(unsafe) static var current: ThemeTokens = .precision
}

// MARK: - 主题选择器

struct ThemeSwitcher: View {
    @Binding var selection: ThemeID
    @State private var showPicker = false

    var body: some View {
        let t = ThemeStore.current

        Button { showPicker = true } label: {
            HStack(spacing: 6) {
                LEDDot(color: t.glow, size: 6)
                Text(t.name)
                    .font(t.labelFont(10, .semibold))
                    .tracking(1.2)
                    .foregroundColor(t.ink)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(t.inkDim)
            }
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(
                Capsule().fill(
                    LinearGradient(colors: [t.faceTop, t.faceBottom],
                                   startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                Capsule().strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.35), .black.opacity(0.4)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("切换界面主题，当前为\(t.name)")
        .sheet(isPresented: $showPicker) {
            ThemePickerSheet(selection: $selection)
        }
    }
}

struct ThemePickerSheet: View {
    @Binding var selection: ThemeID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let t = ThemeStore.current
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("机身主题")
                    .font(t.displayFont(24, .regular))
                    .foregroundColor(t.ink)
                Text("同一台相机，三种工业外壳。切换后整机立即生效。")
                    .font(t.labelFont(11, .regular))
                    .foregroundColor(t.inkDim)

                ForEach(ThemeID.allCases) { id in
                    let item = id.tokens
                    Button {
                        selection = id
                        dismiss()
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 2) {
                                LinearGradient(colors: [item.faceTop, item.faceBottom],
                                               startPoint: .top, endPoint: .bottom)
                                    .frame(width: 26, height: 20)
                                item.accent.frame(width: 26, height: 5)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .overlay(RoundedRectangle(cornerRadius: 3)
                                .stroke(item.hairline, lineWidth: 1))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name)
                                    .font(t.labelFont(13, .semibold))
                                    .foregroundColor(t.ink)
                                Text(item.blurb)
                                    .font(t.labelFont(10, .regular))
                                    .foregroundColor(t.inkDim)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer()
                            if selection == id {
                                LEDDot(color: t.glow, size: 7)
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: t.radius)
                                .fill(LinearGradient(
                                    colors: selection == id ? [t.faceTop, t.faceBottom]
                                                            : [t.panel, t.panel],
                                    startPoint: .top, endPoint: .bottom))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: t.radius)
                                .strokeBorder(selection == id ? t.accent.opacity(0.7) : t.hairline,
                                              lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 8)
            }
            .padding(20)
        }
        .background(MetalSurface(tokens: t).ignoresSafeArea())
    }
}
