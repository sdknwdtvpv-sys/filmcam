import SwiftUI

// MARK: - 主题标识

enum ThemeID: String, CaseIterable, Identifiable {
    case darkroom
    case meter
    case filmstrip

    var id: String { rawValue }

    var tokens: ThemeTokens {
        switch self {
        case .darkroom:  return .darkroom
        case .meter:     return .meter
        case .filmstrip: return .filmstrip
        }
    }
}

// MARK: - 令牌

/// 一套主题的全部可见变量。三个方向的差别不只是颜色：
/// 字体族、圆角、密度、发丝线宽都跟着换，否则切主题只会像换了个色号。
struct ThemeTokens: Sendable {
    let id: ThemeID
    let name: String
    /// 选择器里的一句话说明
    let blurb: String

    // 底色三层
    let background: Color
    let panel: Color
    let elevated: Color

    // 文字
    let ink: Color
    let inkDim: Color

    // 强调
    let accent: Color
    let accentDeep: Color
    let accentGlow: Color
    let hairline: Color
    let recRed: Color

    // 形状与密度
    let radius: CGFloat
    let hairWidth: CGFloat
    /// 卡片内边距（密集主题更小）
    let inset: CGFloat

    // 字体
    let displayFont: @Sendable (CGFloat, Font.Weight) -> Font
    let labelFont: @Sendable (CGFloat, Font.Weight) -> Font
    let monoFont: @Sendable (CGFloat, Font.Weight) -> Font

    // MARK: 预设

    /// 暗房工单：米白纸面 + 品红墨 + 迪多内衬线
    static let darkroom = ThemeTokens(
        id: .darkroom,
        name: "暗房工单",
        blurb: "纸面开一扇窗，快门是一条要撕开的封条",
        background: Color(hex: 0xE9E1D0),
        panel: Color(hex: 0xF3EDE0),
        elevated: Color(hex: 0xDCD2BC),
        ink: Color(hex: 0x241C17),
        inkDim: Color(hex: 0x241C17, opacity: 0.55),
        accent: Color(hex: 0xA3245B),
        accentDeep: Color(hex: 0x7A1743),
        accentGlow: Color(hex: 0xC8397A),
        hairline: Color(hex: 0x241C17, opacity: 0.18),
        recRed: Color(hex: 0xB3261E),
        radius: 2,
        hairWidth: 1,
        inset: 16,
        displayFont: { size, weight in
            .custom("Didot", size: size).weight(weight == .regular ? .regular : weight)
        },
        labelFont: { size, weight in
            .system(size: size, weight: weight, design: .monospaced)
        },
        monoFont: { size, weight in
            .system(size: size, weight: weight, design: .monospaced)
        }
    )

    /// 测光台：冷白仪器面板 + 红绿区间 + 窄体读数
    static let meter = ThemeTokens(
        id: .meter,
        name: "测光台",
        blurb: "整屏仪器面板，参数是刻度上的游标",
        background: Color(hex: 0xE5E7E2),
        panel: Color(hex: 0xEFF1EC),
        elevated: Color(hex: 0xD5D8D1),
        ink: Color(hex: 0x1B1F1C),
        inkDim: Color(hex: 0x1B1F1C, opacity: 0.52),
        accent: Color(hex: 0xC03325),
        accentDeep: Color(hex: 0x8B2116),
        accentGlow: Color(hex: 0xE1594A),
        hairline: Color(hex: 0x1B1F1C, opacity: 0.22),
        recRed: Color(hex: 0xC03325),
        radius: 3,
        hairWidth: 1,
        inset: 14,
        displayFont: { size, weight in
            .custom("DINCondensed-Bold", size: size)
        },
        labelFont: { size, weight in
            .custom("DINCondensed-Bold", size: size)
        },
        monoFont: { size, weight in
            .system(size: size, weight: weight, design: .monospaced)
        }
    )

    /// 胶片带：深靛蓝 + 横向分带 + 巨型帧计数
    static let filmstrip = ThemeTokens(
        id: .filmstrip,
        name: "胶片带",
        blurb: "整屏像一条拉出来的胶片，帧数最大",
        background: Color(hex: 0x0B0D1E),
        panel: Color(hex: 0x151833),
        elevated: Color(hex: 0x1E2242),
        ink: Color(hex: 0xE9E4F3),
        inkDim: Color(hex: 0xE9E4F3, opacity: 0.55),
        accent: Color(hex: 0xB79CFF),
        accentDeep: Color(hex: 0x7A5BD6),
        accentGlow: Color(hex: 0xD9C8FF),
        hairline: Color(hex: 0xB79CFF, opacity: 0.24),
        recRed: Color(hex: 0xFF5A63),
        radius: 14,
        hairWidth: 1,
        inset: 18,
        displayFont: { size, weight in
            .custom("Rockwell-Bold", size: size)
        },
        labelFont: { size, weight in
            .custom("AvenirNext-DemiBold", size: size)
        },
        monoFont: { size, weight in
            .system(size: size, weight: weight, design: .monospaced)
        }
    )
}

// MARK: - 当前主题（给历史遗留的 CameraTheme.* 调用点兜底）

/// 相册、弹层、提示条这些共享界面仍然读 `CameraTheme.xxx`，
/// 这里提供当前主题的解析。根视图在 build 之前写入。
enum ThemeStore {
    nonisolated(unsafe) static var current: ThemeTokens = .darkroom
}

// MARK: - 主题选择器

/// 顶部常驻的主题切换入口：一个色点 + 名字，点开是三选一的说明
struct ThemeSwitcher: View {
    @Binding var selection: ThemeID

    @State private var showPicker = false

    var body: some View {
        Button { showPicker = true } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(ThemeStore.current.accent)
                    .frame(width: 8, height: 8)
                Text(ThemeStore.current.name)
                    .font(ThemeStore.current.labelFont(11, .semibold))
                    .foregroundColor(ThemeStore.current.ink)
                    .tracking(0.5)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(ThemeStore.current.inkDim)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(
                Capsule().fill(ThemeStore.current.panel.opacity(0.92))
            )
            .overlay(
                Capsule().stroke(ThemeStore.current.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("切换界面主题，当前为\(ThemeStore.current.name)")
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
                Text("界面主题")
                    .font(t.displayFont(26, .regular))
                    .foregroundColor(t.ink)
                Text("同一台相机，三种界面骨架。切换后所有页面立即生效。")
                    .font(t.labelFont(12, .regular))
                    .foregroundColor(t.inkDim)

                ForEach(ThemeID.allCases) { id in
                    let item = id.tokens
                    Button {
                        selection = id
                        dismiss()
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 3) {
                                ForEach(0..<3, id: \.self) { i in
                                    Rectangle()
                                        .fill(i == 0 ? item.background
                                              : (i == 1 ? item.accent : item.ink))
                                        .frame(width: 22, height: 9)
                                }
                            }
                            .padding(.top, 3)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(t.labelFont(14, .semibold))
                                    .foregroundColor(t.ink)
                                Text(item.blurb)
                                    .font(t.labelFont(11, .regular))
                                    .foregroundColor(t.inkDim)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer()
                            if selection == id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(t.accent)
                            }
                        }
                        .padding(12)
                        .background(selection == id ? t.elevated : t.panel)
                        .clipShape(RoundedRectangle(cornerRadius: max(t.radius, 4)))
                        .overlay(
                            RoundedRectangle(cornerRadius: max(t.radius, 4))
                                .stroke(selection == id ? t.accent : t.hairline, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 8)
            }
            .padding(20)
        }
        .background(t.background.ignoresSafeArea())
    }
}
