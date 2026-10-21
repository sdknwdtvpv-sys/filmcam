import SwiftUI
import UIKit
import CoreMotion
import AVKit
import StoreKit

struct FilmSheet: View {
    /// 当前选中的卷（还没装）。首次进来等于手上这卷
    @State private var focused: FilmPreset
    @EnvironmentObject var manager: CameraManager

    /// 顶盖胶片键在屏幕上的位置（全局坐标）
    var anchor: CGRect

    init(anchor: CGRect, manager: CameraManager) {
        self.anchor = anchor
        _focused = State(initialValue: manager.selectedPreset)
    }



    var body: some View {
        let t = ThemeStore.current

        GeometryReader { geo in
            let width = min(geo.size.width - 28, 318)
            let top = anchor == .zero ? 62 : anchor.maxY + 7
            let trailing = anchor == .zero ? 14 : max(geo.size.width - anchor.maxX - 2, 8)

            ZStack(alignment: .topTrailing) {
                Color.black.opacity(0.34)
                    .contentShape(Rectangle())
                    .onTapGesture { manager.showFilmSheet = false }

                chamber(t, width: width)
                    .padding(.top, top)
                    .padding(.trailing, trailing)
                    .transition(.scale(scale: 0.86, anchor: .topTrailing)
                        .combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
    }

    private func chamber(_ t: ThemeTokens, width: CGFloat) -> some View {
        VStack(spacing: 0) {
            // 仓盖沿
            HStack(spacing: 8) {
                ScrewHead(size: 6)
                Silkscreen(text: "FILM CHAMBER", color: .black.opacity(0.55),
                           size: 6.5, tracking: 1.8)
                Spacer(minLength: 4)
                Button { manager.showFilmSheet = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.black.opacity(0.6))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                ScrewHead(size: 6)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(AluminumFace(tokens: t))
            .overlay(alignment: .bottom) {
                Rectangle().fill(.black.opacity(0.45)).frame(height: 1)
            }

            // 仓内：胶卷导轨
            Silkscreen(text: "胶卷 · 决定介质与张数", color: .white.opacity(0.32),
                       size: 5.5, tracking: 1.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
                .padding(.top, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(FilmPreset.films) { preset in
                        let unlocked = PurchaseStore.shared.isUnlocked(preset)
                        FilmCanister(preset: preset,
                                     loaded: manager.selectedPreset == preset,
                                     tokens: t) {
                            // 第一下只是选中：先看样片和说明，装卷要再按一次
                            withAnimation(.easeOut(duration: 0.16)) { focused = preset }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .background(LeatherPanel())

            // 这卷拍出来什么样：两张样片，选卷前先看一眼
            FilmSampleStrip(preset: focused)

            // 装卷按钮：选中不等于装了，避免误触把拍了一半的卷收起来
            FilmLoadBar(preset: focused, manager: manager)

            // 当前这卷：型号 · 张数
            HStack(spacing: 6) {
                Silkscreen(text: manager.roll.numberText, color: .white.opacity(0.38),
                           size: 5.5, tracking: 1.4)
                Rectangle().fill(.white.opacity(0.16)).frame(width: 1, height: 7)
                Silkscreen(text: manager.roll.isFull ? "本卷拍完 · 换一卷"
                                      : String(format: NSLocalizedString("还剩 %d 张", comment: ""),
                                               manager.roll.remaining),
                           color: .white.opacity(0.38), size: 5.5, tracking: 1.4)
                Spacer(minLength: 0)
                Text(manager.roll.countText)
                    .font(t.monoFont(7.5, .bold))
                    .foregroundColor(manager.roll.isFull ? t.accent : .white.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .background(LeatherPanel())

            // 仓底齿孔
            HStack(spacing: 4) {
                ForEach(0..<24, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.white.opacity(0.10))
                        .frame(width: 7, height: 4)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color(hex: 0x141516))
        }
        .frame(width: width)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(.black.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
    }
}

/// 调色导轨上的小胶囊
struct LookChip: View {
    let title: String
    let color: Color
    let selected: Bool
    let tokens: ThemeTokens
    let action: () -> Void


    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title)
                    .font(tokens.monoFont(9, .bold))
                    .foregroundColor(selected ? .white : .white.opacity(0.62))
            }
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.16) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(selected ? tokens.accent : .white.opacity(0.12),
                                  lineWidth: selected ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

/// 暗盒上的标签色（调色也能用同一套配色）
func canisterColor(_ preset: FilmPreset) -> Color {
    switch preset {
    case .kodakGold:   return Color(hex: 0xC8912B)
    case .fuji400:     return Color(hex: 0x2E7D53)
    case .classicBnw:  return Color(hex: 0x4A4A4A)
    case .fadedCinema: return Color(hex: 0xB0706A)
    case .cinematic:   return Color(hex: 0x2A6E7A)
    case .duskGold:    return Color(hex: 0xC9752F)
    case .slate:       return Color(hex: 0x5B6670)
    case .mint:        return Color(hex: 0x4E8C7A)
    case .rust:        return Color(hex: 0xA5533A)
    case .frost:       return Color(hex: 0x7C8790)
    case .ochre:       return Color(hex: 0xA8763C)
    case .abyss:       return Color(hex: 0x35485E)
    case .clear:       return Color(hex: 0x3E8FA8)
    case .nightStreet: return Color(hex: 0x2B3A55)
    case .fresh:       return Color(hex: 0x6FA84E)
    case .moody:       return Color(hex: 0x6B4A3A)
    case .glowSkin:    return Color(hex: 0xC9A9A2)
    case .cream:       return Color(hex: 0xD9C9A8)
    case .warmSoft:    return Color(hex: 0xB98A5E)
    case .glowField:   return Color(hex: 0x8FA83F)
    case .sunsetFilm:  return Color(hex: 0xD2763C)
    case .forestGreen: return Color(hex: 0x3F6B4A)
    case .snow:        return Color(hex: 0xAFC2CE)
    case .vintageFilm: return Color(hex: 0x8A6F52)
    case .neutral:     return Color(hex: 0x9BA1A6)
    }
}

struct FilmCanister: View {
    let preset: FilmPreset
    let loaded: Bool
    let tokens: ThemeTokens
    var locked: Bool = false
    var priceTag: String? = nil
    let action: () -> Void

    private var labelColor: Color { canisterColor(preset) }

    private var iso: String { "ISO \(preset.nominalISO)" }


    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                // 顶盖
                ZStack {
                    LinearGradient(colors: [Color(hex: 0x3A3D40), Color(hex: 0x1B1D1F)],
                                   startPoint: .top, endPoint: .bottom)
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { _ in
                            Capsule().fill(.white.opacity(0.18)).frame(width: 2, height: 6)
                        }
                    }
                }
                .frame(height: 11)

                // 罐身 + 标签
                ZStack {
                    LinearGradient(colors: [Color(hex: 0xCFD4D8), Color(hex: 0x8E9499)],
                                   startPoint: .top, endPoint: .bottom)
                    VStack(spacing: 3) {
                        Rectangle().fill(labelColor).frame(height: 30)
                            .overlay(
                                Text(LocalizedStringKey(preset.label))
                                    .font(.custom("Futura-Medium", size: 9))
                                    .foregroundColor(.white.opacity(0.95))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                    .padding(.horizontal, 4)
                            )
                        HStack(spacing: 3) {
                            Text(iso)
                                .font(.system(size: 6, weight: .bold, design: .monospaced))
                                .foregroundColor(.black.opacity(0.55))
                            Text(preset.scene)
                                .font(.system(size: 5.5, weight: .medium, design: .monospaced))
                                .foregroundColor(.black.opacity(0.38))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        Spacer(minLength: 0)
                        // 卷轴
                        Circle()
                            .fill(LinearGradient(colors: [Color(hex: 0x2A2C2E), Color(hex: 0x0E0F10)],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().fill(.white.opacity(0.12)).frame(width: 5, height: 5))
                    }
                    .padding(.vertical, 6)
                }
                .frame(height: 86)
                // 未拆封：压一层暗 + 一把小锁 + 价签
                .overlay {
                    if locked {
                        ZStack {
                            Color.black.opacity(0.45)
                            VStack(spacing: 3) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white.opacity(0.9))
                                if let priceTag {
                                    Text(priceTag)
                                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.85))
                                }
                            }
                        }
                    }
                }

                // 底盖
                LinearGradient(colors: [Color(hex: 0x1B1D1F), Color(hex: 0x36393C)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 9)
            }
            .frame(width: 74)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(loaded ? tokens.accent : .black.opacity(0.45),
                                  lineWidth: loaded ? 2 : 1)
            )
            .overlay(alignment: .top) {
                if loaded {
                    HStack(spacing: 3) {
                        LEDDot(color: tokens.glow, size: 4)
                        Text("LOADED")
                            .font(.system(size: 5.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(.black.opacity(0.7)))
                    .offset(y: -7)
                }
            }
            .shadow(color: .black.opacity(0.5), radius: 4, y: 3)
            .scaleEffect(loaded ? 1.0 : 0.96)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preset.label)，\(iso)\(loaded ? "，已装载" : "")")
    }
}

// MARK: - 设置弹层

/// 「我的」：机器档案 + 我的胶卷 + 胶卷包 + 设置 + 关于。
/// 不联网、不登录，所以没有账号那一层——这一页记录的是这台机器本身。
struct SettingsSheet: View {
    @EnvironmentObject var manager: CameraManager
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject private var store = PurchaseStore.shared
    @ObservedObject private var filmStore = CustomFilmStore.shared
    /// 往下拖时的位移；松手没过阈值就弹回去
    @State private var dragOffset: CGFloat = 0


    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }


    var body: some View {
        ZStack(alignment: .bottom) {
            CameraTheme.bgDeep.opacity(0.6).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    if manager.showPrivacyPolicy {
                        manager.showPrivacyPolicy = false
                    } else {
                        manager.showSettingsSheet = false
                    }
                }

            VStack(spacing: 0) {
                grabHandle
                    .contentShape(Rectangle())
                    .gesture(pullDownGesture)

                if manager.showPrivacyPolicy {
                    PrivacyPolicyView { manager.showPrivacyPolicy = false }
                } else {
                panelHeader
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        statsSection
                        sectionTitle("我的胶卷")
                        customFilmSection
                        sectionTitle("胶卷包")
                        packSection
                        sectionTitle("设置")
                        settingsSection
                        sectionTitle("关于")
                        aboutSection
                        Color.clear.frame(height: 40)
                    }
                    .padding(.horizontal, 20)
                }
                }
            }
            .frame(maxHeight: 620)
            .offset(y: dragOffset)
            .background(AluminumFace(tokens: ThemeStore.current))
            .clipShape(TopRounded(radius: 14))
            .overlay(TopRoundedBorder(radius: 14).stroke(.black.opacity(0.45), lineWidth: 1))
            .transition(.move(edge: .bottom))
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: 抽屉手势

    /// 抓手：一道带滚花的横槽，明示「可以往下拉」
    private var grabHandle: some View {
        VStack(spacing: 0) {
            ZStack {
                Capsule()
                    .fill(CameraTheme.ink.opacity(0.16))
                    .frame(width: 42, height: 4)
                // 极细的滚花，和快门盘同一套语言
                HStack(spacing: 2) {
                    ForEach(0..<11, id: \.self) { _ in
                        Rectangle()
                            .fill(CameraTheme.ink.opacity(0.10))
                            .frame(width: 1, height: 4)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 34)   // 抓手要够大，不然抓不住
            .padding(.top, 2)
        }
    }

    private var pullDownGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                // 只跟往下拉，往上不给动
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                let passed = value.translation.height > 110
                    || value.predictedEndTranslation.height > 220
                if passed {
                    Haptics.impact(.light)
                    // 在看隐私政策：先退回「我的」；否则收面板
                    if manager.showPrivacyPolicy {
                        withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }
                        manager.showPrivacyPolicy = false
                    } else {
                        withAnimation(.easeOut(duration: 0.22)) {
                            manager.showSettingsSheet = false
                            dragOffset = 0
                        }
                    }
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        dragOffset = 0
                    }
                }
            }
    }

    // MARK: 结构件

    private var panelHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ScrewHead(size: 7)
                Silkscreen(text: "SERVICE PANEL", color: CameraTheme.ink.opacity(0.55),
                           size: 7, tracking: 2)
                Spacer()
                Text("我的")
                    .font(CameraTheme.mono(11, weight: .bold))
                    .foregroundColor(CameraTheme.ink.opacity(0.6))
                ScrewHead(size: 7)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            GrooveLine()
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Silkscreen(text: text, color: CameraTheme.ink.opacity(0.45), size: 6.5, tracking: 1.8)
            .padding(.top, 16)
            .padding(.bottom, 6)
    }

    // MARK: 机器档案

    private var statsSection: some View {
        let stats = manager.machineStats
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 0) {
                statCell(value: "\(stats.shots)", unit: "张", label: "已拍")
                statDivider
                statCell(value: "\(stats.rolls)", unit: "卷", label: "用过")
                statDivider
                statCell(value: stats.firstShotAt.map { formatter.string(from: $0) } ?? "—",
                         unit: "", label: "第一卷")
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(CameraTheme.ink.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(CameraTheme.ink.opacity(0.10), lineWidth: 0.5)
            )

            if let favourite = stats.favouriteFilm {
                HStack(spacing: 5) {
                    Circle().fill(canisterColor(manager.roll.preset)).frame(width: 5, height: 5)
                    Text("最常用：\(favourite)")
                        .font(CameraTheme.mono(10))
                        .foregroundColor(CameraTheme.inkDim)
                }
            }
        }
        .padding(.top, 14)
    }

    private var statDivider: some View {
        Rectangle().fill(CameraTheme.ink.opacity(0.10)).frame(width: 0.5, height: 30)
    }

    private func statCell(value: String, unit: String, label: String) -> some View {
        VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(CameraTheme.mono(15, weight: .bold))
                    .foregroundColor(CameraTheme.ink)
                if !unit.isEmpty {
                    Text(unit).font(CameraTheme.mono(9))
                        .foregroundColor(CameraTheme.inkDim)
                }
            }
            Silkscreen(text: label, color: CameraTheme.ink.opacity(0.45), size: 6, tracking: 1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 我的胶卷

    private var customFilmSection: some View {
        VStack(spacing: 0) {
            if filmStore.films.isEmpty {
                Text("还没有自制胶卷。拍完一张，在显影页点「+」就能调一卷。")
                    .font(CameraTheme.mono(10))
                    .foregroundColor(CameraTheme.inkDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(filmStore.films) { film in
                    HStack(spacing: 8) {
                        Circle().fill(LookChoice.custom(film).color).frame(width: 7, height: 7)
                        Text(film.name)
                            .font(CameraTheme.mono(12, weight: .medium))
                            .foregroundColor(CameraTheme.ink)
                        Spacer()
                        Button {
                            filmStore.delete(film)
                            Haptics.impact(.light)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(CameraTheme.inkDim)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("删除 \(film.name)")
                    }
                    .padding(.vertical, 4)
                }
            }
            GrooveLine()
        }
    }

    // MARK: 胶卷包

    private var packSection: some View {
        VStack(spacing: 0) {
            ForEach(FilmPack.allCases) { pack in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pack.title)
                            .font(CameraTheme.mono(12, weight: .medium))
                            .foregroundColor(CameraTheme.ink)
                        if !pack.hint.isEmpty {
                            Text(pack.hint)
                                .font(CameraTheme.mono(10))
                                .foregroundColor(CameraTheme.inkDim)
                        }
                    }
                    Spacer()
                    if pack.productID == nil {
                        Text("已拥有")
                            .font(CameraTheme.mono(11, weight: .medium))
                            .foregroundColor(CameraTheme.inkDim)
                    } else if store.isOpenElsewhere {
                        // 商品还没在 App Store Connect 配好：照实说，不假装已购买
                        Text("未上架")
                            .font(CameraTheme.mono(10))
                            .foregroundColor(CameraTheme.inkDim.opacity(0.7))
                    } else if store.purchased.contains(pack.productID ?? "") {
                        Text("已拥有")
                            .font(CameraTheme.mono(11, weight: .medium))
                            .foregroundColor(CameraTheme.inkDim)
                    } else if let price = store.priceText(for: pack) {
                        Button {
                            Task {
                                let ok = await store.purchase(pack)
                                if ok { Haptics.impact(.rigid) }
                            }
                        } label: {
                            Text(price)
                                .font(CameraTheme.mono(12, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .frame(height: 28)
                                .background(RoundedRectangle(cornerRadius: 5).fill(CameraTheme.amber))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("即将上架")
                            .font(CameraTheme.mono(10))
                            .foregroundColor(CameraTheme.inkDim)
                    }
                }
                .padding(.vertical, 9)
                GrooveLine()
            }

            Button {
                Task { await store.refreshEntitlements() }
            } label: {
                Text("恢复购买")
                    .font(CameraTheme.mono(11, weight: .medium))
                    .foregroundColor(CameraTheme.amber)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 设置

    private var settingsSection: some View {
        VStack(spacing: 0) {
            Button {
                manager.resetAuto()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("自动曝光与白平衡")
                            .font(CameraTheme.mono(13, weight: .medium))
                            .foregroundColor(CameraTheme.ink)
                        Text("恢复连续自动对焦 / 曝光 / 白平衡")
                            .font(CameraTheme.mono(11)).foregroundColor(CameraTheme.inkDim)
                    }
                    Spacer()
                    Text(manager.autoExposure && manager.autoWB ? "已开启" : "恢复自动")
                        .font(CameraTheme.mono(12, weight: .medium))
                        .foregroundColor(CameraTheme.amber)
                }
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            GrooveLine()
            settingsToggle(title: "预览网格", subtitle: "三分构图辅助线", isOn: $manager.showGrid)
            GrooveLine()
            settingsToggle(title: "水平指示", subtitle: "取景器内显示横滚水平仪", isOn: $manager.showLevel)
            GrooveLine()
            settingsToggle(title: "存储提示", subtitle: "取景器右上角显示可用空间", isOn: $manager.showStorage)
            GrooveLine()
            languageRow()
            GrooveLine()
            settingsToggle(title: "日期背印",
                           subtitle: "把橙色日期烧进成片右下角（老式胶卷机后背）",
                           isOn: $manager.dateStampEnabled)
        }
    }

    // MARK: 关于

    private var aboutSection: some View {
        VStack(spacing: 0) {
            aboutRow(title: "版本", detail: version, action: nil)
            GrooveLine()
            aboutRow(title: "隐私政策",
                     detail: nil,
                     action: { manager.showPrivacyPolicy = true })
            GrooveLine()
            aboutRow(title: "反馈与建议",
                     detail: PrivacyPolicyView.contactEmail,
                     action: { openURL("mailto:\(PrivacyPolicyView.contactEmail)?subject=FutureCam") })
            GrooveLine()
            aboutRow(title: "给个评分", detail: nil, action: { requestReview() })
        }
    }

    private func aboutRow(title: String, detail: String?, action: (() -> Void)?) -> some View {
        Button {
            action?()
            Haptics.impact(.light)
        } label: {
            HStack {
                Text(title)
                    .font(CameraTheme.mono(12, weight: .medium))
                    .foregroundColor(CameraTheme.ink)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(CameraTheme.mono(10))
                        .foregroundColor(CameraTheme.inkDim)
                }
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(CameraTheme.inkDim)
                }
            }
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        UIApplication.shared.open(url)
    }

    private func requestReview() {
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)
        }
    }



    /// 语言：三档，切换后重新打开生效
    private func languageRow() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("语言").font(CameraTheme.mono(13, weight: .medium))
                    .foregroundColor(CameraTheme.ink)
                Text("界面语言，重新打开 App 后生效")
                    .font(CameraTheme.mono(11))
                    .foregroundColor(CameraTheme.inkDim)
            }
            HStack(spacing: 6) {
                ForEach(AppLanguage.allCases) { languageValue in
                    let active = language.language == languageValue
                    Button {
                        language.set(languageValue)
                        Haptics.impact(.light)
                    } label: {
                        Text(languageValue.label)
                            .font(CameraTheme.mono(11, weight: active ? .bold : .medium))
                            .foregroundColor(active ? .white : CameraTheme.ink.opacity(0.65))
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(active ? CameraTheme.amber : CameraTheme.ink.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            if language.pendingRestart {
                Text("已切换，重新打开 App 后生效")
                    .font(CameraTheme.mono(10))
                    .foregroundColor(CameraTheme.amber)
            }
        }
        .padding(.vertical, 10)
    }

    private func settingsToggle(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title)).font(CameraTheme.mono(13, weight: .medium)).foregroundColor(CameraTheme.ink)
                Text(LocalizedStringKey(subtitle)).font(CameraTheme.mono(11)).foregroundColor(CameraTheme.inkDim)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(CameraTheme.amber)
                .accessibilityLabel(title)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - 权限引导层

/// 权限引导：机身上的镜头盖。点键取下盖子＝授权；被拒时盖子锁死，只能去系统设置。


/// 样片条：这一卷在人像和室内两种场景下的样子。
/// 图片是打包进 App 的（拍摄时用样片底片预渲染），不联网。
struct FilmSampleStrip: View {
    let preset: FilmPreset

    private func image(_ index: Int) -> UIImage? {
        guard let dir = Bundle.main.path(forResource: "FilmSamples", ofType: nil) else { return nil }
        return UIImage(contentsOfFile: "\(dir)/\(preset.rawValue)_\(index).jpg")
    }


    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<2, id: \.self) { i in
                if let ui = image(i) {
                    Image(uiImage: ui)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 66, height: 88)
                        .clipped()
                        .overlay(Rectangle().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Silkscreen(text: "SAMPLES", color: .white.opacity(0.35), size: 5.5, tracking: 1.2)
                Text(preset.scene)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
                Text("换卷后可对照")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}


/// 装卷条：选中不等于装卷，这里才真正换卷。
/// 之前点一下胶卷就立刻换，拍了一半的卷被默默收起来，没有任何提示。
struct FilmLoadBar: View {
    let preset: FilmPreset
    @ObservedObject var manager: CameraManager

    var body: some View {
        let t = ThemeStore.current
        let isLoaded = manager.selectedPreset == preset
        let used = manager.roll.used
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Silkscreen(text: preset.label, color: .white.opacity(0.5), size: 6, tracking: 1.2)
                Silkscreen(text: "ISO \(preset.nominalISO)", color: .white.opacity(0.32),
                           size: 5.5, tracking: 0.8)
                Spacer(minLength: 0)
                if !isLoaded && used > 0 {
                    Text(String(format: NSLocalizedString("已拍 %d 张，换卷会收起当前这卷", comment: ""), used))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.orange.opacity(0.8))
                }
            }
            Button {
                if isLoaded {
                    manager.showFilmSheet = false
                } else {
                    manager.loadRoll(preset)
                    manager.showFilmSheet = false
                    Haptics.impact(.rigid)
                }
            } label: {
                Text(isLoaded ? "当前已装" : "装这一卷")
                    .font(t.monoFont(11, .bold))
                    .foregroundColor(isLoaded ? .white.opacity(0.45) : .black.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isLoaded ? Color.white.opacity(0.06) : t.accent)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .background(LeatherPanel())
    }
}
