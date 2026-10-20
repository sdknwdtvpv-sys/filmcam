import SwiftUI
import UIKit
import CoreMotion
import AVKit

struct FilmSheet: View {
    @EnvironmentObject var manager: CameraManager

    /// 顶盖胶片键在屏幕上的位置（全局坐标）
    var anchor: CGRect

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

            // 仓内：暗盒导轨
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(FilmPreset.allCases) { preset in
                        FilmCanister(preset: preset,
                                     loaded: manager.selectedPreset == preset,
                                     tokens: t) {
                            // 点另一卷 = 装新卷：当前这卷会被收起来，成片仍按卷归档
                            if manager.selectedPreset == preset {
                                manager.showFilmSheet = false
                            } else {
                                manager.loadRoll(preset)
                                manager.showFilmSheet = false
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .background(LeatherPanel())

            // 当前这卷：型号 · 张数
            HStack(spacing: 6) {
                Silkscreen(text: manager.roll.numberText, color: .white.opacity(0.38),
                           size: 5.5, tracking: 1.4)
                Rectangle().fill(.white.opacity(0.16)).frame(width: 1, height: 7)
                Silkscreen(text: manager.roll.isFull ? "本卷拍完 · 换一卷" : "还剩 \(manager.roll.remaining) 张",
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

struct FilmCanister: View {
    let preset: FilmPreset
    let loaded: Bool
    let tokens: ThemeTokens
    let action: () -> Void

    private var labelColor: Color {
        switch preset {
        case .kodakGold:   return Color(hex: 0xC8912B)
        case .fuji400:     return Color(hex: 0x2E7D53)
        case .classicBnw:  return Color(hex: 0x4A4A4A)
        case .fadedCinema: return Color(hex: 0xB0706A)
        case .cinematic:   return Color(hex: 0x2A6E7A)
        }
    }

    private var iso: String {
        switch preset {
        case .kodakGold:   return "ISO 200"
        case .fuji400:     return "ISO 400"
        case .classicBnw:  return "ISO 400"
        case .fadedCinema: return "ISO 200"
        case .cinematic:   return "ISO 500"
        }
    }

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
                                Text(preset.label)
                                    .font(.custom("Futura-Medium", size: 9))
                                    .foregroundColor(.white.opacity(0.95))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                    .padding(.horizontal, 4)
                            )
                        Text(iso)
                            .font(.system(size: 6, weight: .bold, design: .monospaced))
                            .foregroundColor(.black.opacity(0.55))
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

struct SettingsSheet: View {
    @EnvironmentObject var manager: CameraManager

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraTheme.bgDeep.opacity(0.6).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { manager.showSettingsSheet = false }

            VStack(alignment: .leading, spacing: 0) {
                // 服务面板：螺丝 + 丝印标题，和机身同一套语言
                HStack(spacing: 8) {
                    ScrewHead(size: 7)
                    Silkscreen(text: "SERVICE PANEL", color: CameraTheme.ink.opacity(0.55),
                               size: 7, tracking: 2)
                    Spacer()
                    Text("设置")
                        .font(CameraTheme.mono(11, weight: .bold))
                        .foregroundColor(CameraTheme.ink.opacity(0.6))
                    ScrewHead(size: 7)
                }
                .padding(.vertical, 12)
                GrooveLine()

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
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)

                GrooveLine()

                settingsToggle(title: "预览网格", subtitle: "三分构图辅助线", isOn: $manager.showGrid)
                GrooveLine()
                settingsToggle(title: "水平指示", subtitle: "取景器内显示横滚水平仪", isOn: $manager.showLevel)
                GrooveLine()
                settingsToggle(title: "存储提示", subtitle: "取景器右上角显示可用空间", isOn: $manager.showStorage)

                Color.clear.frame(height: 34)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AluminumFace(tokens: ThemeStore.current))
            .clipShape(TopRounded(radius: 14))
            .overlay(TopRoundedBorder(radius: 14).stroke(.black.opacity(0.45), lineWidth: 1))
            .transition(.move(edge: .bottom))
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func settingsToggle(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(CameraTheme.mono(13, weight: .medium)).foregroundColor(CameraTheme.ink)
                Text(subtitle).font(CameraTheme.mono(11)).foregroundColor(CameraTheme.inkDim)
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
