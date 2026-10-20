import SwiftUI

/// 方向一 · 暗房工单
///
/// 把界面当成一张暗房工单：取景器是纸面上开的一扇深色窗，
/// 左侧是竖排工单脊，底部一条齿孔撕线把「读数」和「快门」分开，
/// 快门本身是一条要按下去的纸质封条。
struct DarkroomCameraView: View {
    @EnvironmentObject var manager: CameraManager

    @State private var sealPressed = false

    var body: some View {
        let t = ThemeStore.current

        ZStack {
            t.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header(t)
                Rectangle().fill(t.ink.opacity(0.55)).frame(height: 1)
                windowRow(t)
                tearLine(t)
                paramStamps(t)
                ParamTuningPanel()
                modeStamps(t)
                toolRow(t)
                sealRow(t)
            }
        }
    }

    // MARK: 页眉 —— 品牌 + 胶卷号 + 帧号

    private func header(_ t: ThemeTokens) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("FILMCAM")
                .font(t.labelFont(13, .bold))
                .tracking(3.6)
                .foregroundColor(t.ink)
            Text("暗房")
                .font(t.labelFont(9, .medium))
                .tracking(2.2)
                .foregroundColor(t.inkDim)

            Spacer(minLength: 6)

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(String(format: "%02d", manager.frameCount % 36 + 1))
                    .font(t.displayFont(27, .regular))
                    .foregroundColor(t.accent)
                Text("/36")
                    .font(t.monoFont(9, .medium))
                    .foregroundColor(t.inkDim)
            }
        }
        .padding(.horizontal, t.inset)
        .padding(.top, 4)
        .padding(.bottom, 7)
    }

    // MARK: 取景窗 + 工单脊

    private func windowRow(_ t: ThemeTokens) -> some View {
        HStack(alignment: .top, spacing: 8) {
            spine(t)

            PreviewSurface(showsScrim: false)
                .overlay(Rectangle().stroke(t.ink.opacity(0.85), lineWidth: 1.2))
                .overlay(alignment: .topLeading) { cornerMark(t) }
                .overlay(alignment: .bottomTrailing) { cornerMark(t).rotationEffect(.degrees(180)) }
                .shadow(color: t.ink.opacity(0.16), radius: 0, x: 3, y: 3)
        }
        .padding(.horizontal, t.inset)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity)
    }

    private func spine(_ t: ThemeTokens) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(t.accent)
                .frame(width: 6, height: 6)
            Spacer(minLength: 6)
            Text(manager.selectedPreset.label.uppercased())
                .font(t.monoFont(8, .medium))
                .tracking(2.4)
                .foregroundColor(t.inkDim)
                .fixedSize()
                .rotationEffect(.degrees(-90))
                .frame(width: 14, height: 118)
            Spacer(minLength: 6)
            Text("ISO \(Int(manager.iso))")
                .font(t.monoFont(7, .medium))
                .tracking(1.2)
                .foregroundColor(t.inkDim)
                .fixedSize()
                .rotationEffect(.degrees(-90))
                .frame(width: 14, height: 54)
            Rectangle()
                .fill(t.hairline)
                .frame(width: 1, height: 22)
            Spacer(minLength: 6)
        }
        .frame(width: 18)
        .overlay(alignment: .trailing) {
            Rectangle().fill(t.hairline).frame(width: 1)
        }
    }

    private func cornerMark(_ t: ThemeTokens) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 9))
            p.addLine(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: 9, y: 0))
        }
        .stroke(t.panel, lineWidth: 1.5)
        .frame(width: 10, height: 10)
        .padding(5)
    }

    // MARK: 齿孔撕线

    private func tearLine(_ t: ThemeTokens) -> some View {
        HStack(spacing: 3) {
            Text("撕开")
                .font(t.monoFont(7, .semibold))
                .tracking(1.6)
                .foregroundColor(t.inkDim)
                .padding(.trailing, 2)
            ForEach(0..<44, id: \.self) { _ in
                Circle()
                    .fill(t.ink.opacity(0.28))
                    .frame(width: 2.4, height: 2.4)
            }
        }
        .padding(.horizontal, t.inset)
        .padding(.vertical, 6)
    }

    // MARK: 参数戳记

    private func paramStamps(_ t: ThemeTokens) -> some View {
        let keys = visibleParams(manager)
        return HStack(spacing: 0) {
            ForEach(Array(keys.enumerated()), id: \.element) { index, key in
                if index > 0 {
                    Rectangle().fill(t.hairline).frame(width: 1, height: 22)
                }
                Button { manager.toggleParam(key) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(paramTitle(key))
                            .font(t.monoFont(7.5, .medium))
                            .tracking(1.3)
                            .foregroundColor(manager.activeParam == key ? t.panel.opacity(0.8) : t.inkDim)
                        Text(paramValue(key, manager))
                            .font(t.displayFont(19, .regular))
                            .foregroundColor(manager.activeParam == key ? t.panel : t.ink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(manager.activeParam == key ? t.ink : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(paramTitle(key)) \(paramValue(key, manager))")
            }

            Button { toggleGroup() } label: {
                Text(manager.paramMode == .exposure ? "曝光" : "白平衡")
                    .font(t.monoFont(8, .semibold))
                    .tracking(1)
                    .foregroundColor(t.accent)
                    .padding(.horizontal, 8)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("切换参数分组")
        }
        .frame(height: 34)
        .padding(.horizontal, t.inset)
    }

    // MARK: 模式戳

    private func modeStamps(_ t: ThemeTokens) -> some View {
        HStack(spacing: 5) {
            ForEach(CameraMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { manager.mode = mode }
                } label: {
                    Text(mode.label)
                        .font(t.labelFont(11, .semibold))
                        .tracking(1.6)
                        .foregroundColor(manager.mode == mode ? t.panel : t.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(manager.mode == mode ? t.ink : Color.clear)
                        .overlay(
                            Rectangle().stroke(t.ink.opacity(manager.mode == mode ? 0 : 0.3),
                                               style: StrokeStyle(lineWidth: 1, dash: manager.mode == mode ? [] : [3, 2]))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, t.inset)
        .padding(.top, 8)
    }

    // MARK: 小工具行

    private func toolRow(_ t: ThemeTokens) -> some View {
        HStack(spacing: 14) {
            Button { manager.showFilmSheet = true } label: {
                microLabel("胶片 · \(manager.selectedPreset.label)", t, active: false)
            }
            Button { manager.showGrid.toggle() } label: {
                microLabel("网格", t, active: manager.showGrid)
            }
            Button { manager.showSettingsSheet = true } label: {
                microLabel("设置", t, active: false)
            }
            Spacer(minLength: 0)
            Button { manager.showLevel.toggle() } label: {
                microLabel("水平", t, active: manager.showLevel)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, t.inset)
        .padding(.top, 6)
    }

    private func microLabel(_ text: String, _ t: ThemeTokens, active: Bool) -> some View {
        Text(text)
            .font(t.monoFont(9, .medium))
            .tracking(0.4)
            .foregroundColor(active ? t.accent : t.inkDim)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(active ? t.accent : t.hairline)
                    .frame(height: 1)
                    .offset(y: 2)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
    }

    // MARK: 封条快门

    private func sealRow(_ t: ThemeTokens) -> some View {
        HStack(alignment: .center, spacing: 10) {
            albumStamp(t)

            Button { shoot() } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(shutterVerb(manager))
                            .font(t.displayFont(21, .regular))
                            .foregroundColor(t.ink)
                        Text(shutterHint(manager))
                            .font(t.monoFont(7.5, .medium))
                            .tracking(1.6)
                            .foregroundColor(t.inkDim)
                    }
                    Spacer(minLength: 0)
                    Text("▸")
                        .font(t.monoFont(13, .medium))
                        .foregroundColor(t.accent)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .frame(height: 62)
                .background(t.panel)
                .overlay(
                    Rectangle().strokeBorder(t.ink.opacity(0.5),
                                             style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                )
                .overlay(alignment: .leading) {
                    Rectangle().fill(t.accent).frame(width: 3)
                }
                .shadow(color: t.ink.opacity(0.14), radius: 0, x: 2, y: 2)
                .scaleEffect(sealPressed ? 0.975 : 1)
                .opacity(sealPressed ? 0.75 : 1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(shutterVerb(manager))
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !sealPressed { withAnimation(.easeOut(duration: 0.1)) { sealPressed = true } } }
                    .onEnded { _ in withAnimation(.easeOut(duration: 0.12)) { sealPressed = false } }
            )

            flipStamp(t)
        }
        .padding(.horizontal, t.inset)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private func albumStamp(_ t: ThemeTokens) -> some View {
        Button { manager.openAlbum() } label: {
            ZStack {
                Rectangle()
                    .fill(t.panel)
                    .frame(width: 52, height: 62)
                    .overlay(Rectangle().stroke(t.ink.opacity(0.4), lineWidth: 1))
                if let latest = manager.albumItems.first {
                    MediaThumbnail(item: latest, maxPixel: 200, fill: true)
                        .frame(width: 42, height: 52)
                } else {
                    Text("空")
                        .font(t.monoFont(9, .medium))
                        .foregroundColor(t.inkDim)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开相册")
    }

    private func flipStamp(_ t: ThemeTokens) -> some View {
        Button { manager.switchCamera() } label: {
            VStack(spacing: 2) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(manager.isRecording ? t.inkDim.opacity(0.35) : t.ink)
                    .rotationEffect(.degrees(manager.isFrontCamera ? 180 : 0))
                    .animation(.easeInOut(duration: 0.28), value: manager.isFrontCamera)
                Text(manager.isFrontCamera ? "前" : "后")
                    .font(t.monoFont(7, .medium))
                    .foregroundColor(t.inkDim)
            }
            .frame(width: 44, height: 62)
            .overlay(Rectangle().stroke(t.ink.opacity(0.4), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(manager.isRecording)
        .accessibilityLabel(manager.isFrontCamera ? "切换到后置摄像头" : "切换到前置摄像头")
    }

    // MARK: 动作

    private func shoot() {
        Haptics.impact(.medium)
        if manager.mode == .video { manager.toggleRecording() } else { manager.capturePhoto() }
    }

    private func toggleGroup() {
        manager.setParamMode(manager.paramMode == .exposure ? .whiteBalance : .exposure)
    }
}
