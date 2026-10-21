import SwiftUI

/// 首次进入的三步引导：先问「你拍什么」，再推荐一卷，最后直接开拍。
/// 原来的 8 步控件教学太重，且用户拍完才会关心那些细节；
/// 控件说明挪到「我的 → 使用提示」。
struct OnboardingFlow: View {
    var onFinish: () -> Void

    @EnvironmentObject var manager: CameraManager
    @State private var page = DebugHarness.onbPage
        ?? UserDefaults.standard.object(forKey: "futurecam.debugOnbPage") as? Int ?? 0
    @State private var picked: FilmPreset.FilmCollection? =
        (DebugHarness.onbPage != nil
         || UserDefaults.standard.object(forKey: "futurecam.debugOnbPage") != nil) ? .daily : nil

    private var recommended: FilmPreset {
        guard let picked else { return .kodakGold }
        return FilmPreset.films.first { $0.collection == picked } ?? .kodakGold
    }

    var body: some View {
        let t = ThemeStore.current
        ZStack {
            Color(hex: 0x111213).ignoresSafeArea()

            VStack(spacing: 0) {
                // 顶部卷号一样的进度刻度
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule()
                            .fill(i <= page ? t.accentGlow : .white.opacity(0.18))
                            .frame(width: i == page ? 22 : 10, height: 3)
                    }
                    Spacer()
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)

                Spacer(minLength: 0)

                switch page {
                case 0: scenePage(t)
                case 1: filmPage(t)
                default: readyPage(t)
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: 第一步：问场景

    private func scenePage(_ t: ThemeTokens) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Silkscreen(text: "STEP 1", color: .white.opacity(0.4), size: 6, tracking: 2)
                Text("你常拍什么？")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Text("我们会先给你装一卷适合它的")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
            }

            VStack(spacing: 8) {
                ForEach(FilmPreset.FilmCollection.allCases) { collection in
                    let active = picked == collection
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { picked = collection }
                        Haptics.impact(.light)
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(collection.rawValue)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                                Text(collection.hint)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                            Spacer(minLength: 0)
                            if active {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(t.accentGlow)
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(active ? Color.white.opacity(0.10) : Color.white.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(active ? t.accentGlow.opacity(0.7) : Color.white.opacity(0.08),
                                              lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                guard picked != nil else { return }
                withAnimation(.easeOut(duration: 0.2)) { page = 1 }
                Haptics.impact(.rigid)
            } label: {
                Text("下一步")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.black.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(picked == nil ? Color.white.opacity(0.10) : t.accent))
            }
            .buttonStyle(.plain)
            .disabled(picked == nil)
        }
        .padding(.horizontal, 22)
    }

    // MARK: 第二步：推荐一卷

    private func filmPage(_ t: ThemeTokens) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Silkscreen(text: "STEP 2", color: .white.opacity(0.4), size: 6, tracking: 2)
                Text("先给你装这卷")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Text("\(picked?.rawValue ?? "") · \(recommended.scene)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
            }

            HStack(spacing: 16) {
                MiniCanister(color: canisterColor(recommended),
                             iso: recommended.nominalISO, scale: 1.1)

                VStack(alignment: .leading, spacing: 6) {
                    Text(recommended.label)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Text("ISO \(recommended.nominalISO)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.45))
                    Text("拍完 36 张才会换卷，一卷一卷来")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)

            Button {
                manager.loadRoll(recommended)
                withAnimation(.easeOut(duration: 0.2)) { page = 2 }
                Haptics.impact(.medium)
            } label: {
                Text("装卷")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 8).fill(t.accent))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
    }

    // MARK: 第三步：三句话说完怎么拍

    private func readyPage(_ t: ThemeTokens) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Silkscreen(text: "READY", color: .white.opacity(0.4), size: 6, tracking: 2)
                Text("可以拍了")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 14) {
                tip("轻点快门就拍", "按住左右拖，左双曝右录像")
                tip("右上角是片仓", "点它换卷，一卷 36 张")
                tip("拍完往下拉", "显影之后才能看，胶片就是这样")
            }

            Spacer(minLength: 0)

            Button {
                UserDefaults.standard.set(picked?.rawValue, forKey: "futurecam.preferredCollection")
                onFinish()
                Haptics.impact(.heavy)
            } label: {
                Text("开始")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.black.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 8).fill(t.accent))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
    }

    private func tip(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(Color.white.opacity(0.35)).frame(width: 4, height: 4).padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                Text(detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
    }
}
