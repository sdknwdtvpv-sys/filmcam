import SwiftUI

// MARK: - 主题标识

enum ThemeID: String, CaseIterable, Identifiable {
    case rangefinder
    case cineRig
    case labUnit

    var id: String { rawValue }

    var tokens: ThemeTokens {
        switch self {
        case .rangefinder: return .rangefinder
        case .cineRig:     return .cineRig
        case .labUnit:     return .labUnit
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

// MARK: - 三台机身

extension ThemeTokens {

    /// A · 机加工测距仪：铝上盖 + 黑蒙皮 + 顶部两个滚花盘
    static let rangefinder = ThemeTokens(
        id: .rangefinder,
        name: "测距仪",
        blurb: "铝盖黑皮机身，顶部滚花盘",
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

    /// B · 模块化摄影机：碳纤 + 铝框 + 红色标记
    static let cineRig = ThemeTokens(
        id: .cineRig,
        name: "摄影机",
        blurb: "碳纤机身，铝框快装，红色录制",
        material: .carbon,
        background: Color(hex: 0x07080A),
        panel: Color(hex: 0x14171B),
        elevated: Color(hex: 0x1F2429),
        faceTop: Color(hex: 0x272D33),
        faceBottom: Color(hex: 0x0D1013),
        wellTop: Color(hex: 0x040506),
        wellBottom: Color(hex: 0x090B0D),
        ink: Color(hex: 0xECEEF1),
        inkDim: Color(hex: 0xECEEF1, opacity: 0.46),
        accent: Color(hex: 0xE23A2E),
        accentDeep: Color(hex: 0x8C1C14),
        accentGlow: Color(hex: 0xFF6A5E),
        glow: Color(hex: 0xFF4A3D),
        hairline: Color(hex: 0xFFFFFF, opacity: 0.12),
        recRed: Color(hex: 0xFF3B2F),
        radius: 8,
        hairWidth: 1,
        inset: 13,
        displayFont: { size, _ in .custom("HelveticaNeue-CondensedBold", size: size) },
        labelFont: { size, _ in .custom("HelveticaNeue-Medium", size: size) },
        monoFont: { size, weight in .system(size: size, weight: weight, design: .monospaced) }
    )

    /// C · 实验室仪器：半透壳 + 可见电路板 + 荧光绿读数
    static let labUnit = ThemeTokens(
        id: .labUnit,
        name: "实验室",
        blurb: "半透外壳，看得见电路板",
        material: .graphite,
        background: Color(hex: 0xDDE3DF),
        panel: Color(hex: 0xEFF3F0),
        elevated: Color(hex: 0xCFD6D1),
        faceTop: Color(hex: 0xFFFFFF),
        faceBottom: Color(hex: 0xC8D0CA),
        wellTop: Color(hex: 0x0A1410),
        wellBottom: Color(hex: 0x050C09),
        ink: Color(hex: 0x1A221E),
        inkDim: Color(hex: 0x1A221E, opacity: 0.5),
        accent: Color(hex: 0x12A56F),
        accentDeep: Color(hex: 0x0A6B47),
        accentGlow: Color(hex: 0x4DFFA6),
        glow: Color(hex: 0x4DFFA6),
        hairline: Color(hex: 0x1A221E, opacity: 0.18),
        recRed: Color(hex: 0xD6452F),
        radius: 10,
        hairWidth: 1,
        inset: 15,
        displayFont: { size, _ in .custom("Menlo-Bold", size: size) },
        labelFont: { size, _ in .custom("Futura-Medium", size: size) },
        monoFont: { size, weight in .system(size: size, weight: weight, design: .monospaced) }
    )
}

// MARK: - 当前主题

enum ThemeStore {
    nonisolated(unsafe) static var current: ThemeTokens = .rangefinder
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
