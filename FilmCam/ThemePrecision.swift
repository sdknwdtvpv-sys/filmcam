import SwiftUI

/// A · 精密仪器
///
/// 一块拉丝阳极氧化铝机身：蚀刻铭牌、凹陷读数窗、三块凸起仪表格，
/// 右下一个滚花转盘 —— 点按快门，横向拖动直接改快门速度。
struct PrecisionCameraView: View {
    @EnvironmentObject var manager: CameraManager

    @State private var dialBase: Double?

    var body: some View {
        let t = ThemeStore.current

        ZStack {
            MetalSurface(tokens: t).ignoresSafeArea()

            // 机加工外框
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.5), .clear, .black.opacity(0.35)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 2)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topPlate(t)
                GrooveLine()
                viewfinderWell(t)
                GrooveLine()
                readoutModules(t)
                ParamTuningPanel()
                modeButtons(t)
                GrooveLine()
                bottomDeck(t)
            }
        }
    }

    // MARK: 顶部铭牌

    private func topPlate(_ t: ThemeTokens) -> some View {
        HStack(spacing: 8) {
            ScrewHead(tokens: t, size: 8)
            EngravedText(text: "FILMCAM", tokens: t, size: 12, tracking: 3)
            LEDDot(color: t.glow, size: 5)
            EngravedText(text: "PRECISION", tokens: t, size: 7, weight: .regular, tracking: 1.6)

            Spacer(minLength: 6)

            EngravedText(text: "FRAME", tokens: t, size: 7, weight: .regular, tracking: 1.4)
            InsetWell(tokens: t, radius: 3) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Text(String(format: "%03d", manager.frameCount))
                        .font(t.displayFont(17, .regular))
                        .foregroundColor(Color(hex: 0xF2F4F6))
                        .monospacedDigit()
                    Spacer(minLength: 0)
                }
                .frame(width: 44, height: 20)
            }
            ScrewHead(tokens: t, size: 8)
        }
        .padding(.horizontal, t.inset)
        .padding(.top, 4)
        .padding(.bottom, 7)
    }

    // MARK: 取景窗

    private func viewfinderWell(_ t: ThemeTokens) -> some View {
        InsetWell(tokens: t, radius: 10) {
            PreviewSurface(showsScrim: false)
                .overlay(
                    // 玻璃反光
                    LinearGradient(colors: [.white.opacity(0.07), .clear, .clear],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .allowsHitTesting(false)
                )
                .padding(3)
        }
        .overlay(alignment: .topLeading) { ScrewHead(tokens: t, size: 7).offset(x: 5, y: 5) }
        .overlay(alignment: .topTrailing) { ScrewHead(tokens: t, size: 7).offset(x: -5, y: 5) }
        .overlay(alignment: .bottomLeading) { ScrewHead(tokens: t, size: 7).offset(x: 5, y: -5) }
        .overlay(alignment: .bottomTrailing) { ScrewHead(tokens: t, size: 7).offset(x: -5, y: -5) }
        .padding(.horizontal, t.inset)
        .padding(.vertical, 10)
        .frame(maxHeight: .infinity)
    }

    // MARK: 三块仪表格

    private func readoutModules(_ t: ThemeTokens) -> some View {
        let keys = visibleParams(manager)
        return HStack(spacing: 6) {
            ForEach(keys, id: \.self) { key in
                PhysicalButton(tokens: t, radius: 5, action: { manager.toggleParam(key) }) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 4) {
                            EngravedText(text: paramTitle(key), tokens: t,
                                         size: 7.5, weight: .regular, tracking: 1.4)
                            if manager.activeParam == key {
                                LEDDot(color: t.glow, size: 4)
                            }
                            Spacer(minLength: 0)
                        }
                        Text(paramValue(key, manager))
                            .font(t.displayFont(24, .regular))
                            .foregroundColor(manager.activeParam == key ? t.accent : t.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("\(paramTitle(key)) \(paramValue(key, manager))")
            }

            PhysicalButton(tokens: t, radius: 5, action: toggleGroup) {
                VStack(spacing: 1) {
                    Image(systemName: "arrow.2.squarepath")
                        .font(.system(size: 11, weight: .semibold))
                    EngravedText(text: manager.paramMode == .exposure ? "EXP" : "WB",
                                 tokens: t, size: 6.5, weight: .regular, tracking: 0.6)
                }
                .foregroundColor(t.inkDim)
                .frame(width: 40)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("切换参数分组")
        }
        .padding(.horizontal, t.inset)
        .padding(.bottom, 8)
    }

    // MARK: 模式键

    private func modeButtons(_ t: ThemeTokens) -> some View {
        HStack(spacing: 6) {
            ForEach(CameraMode.allCases) { mode in
                PhysicalButton(tokens: t, radius: 5, action: {
                    withAnimation(.easeInOut(duration: 0.16)) { manager.mode = mode }
                }) {
                    HStack(spacing: 6) {
                        LEDDot(color: manager.mode == mode ? t.glow : t.inkDim,
                               size: 5, dimmed: manager.mode != mode)
                        Text(mode.label)
                            .font(t.labelFont(11, .semibold))
                            .tracking(1)
                            .foregroundColor(manager.mode == mode ? t.ink : t.inkDim)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
            }
        }
        .padding(.horizontal, t.inset)
        .padding(.bottom, 8)
    }

    // MARK: 底部：相册 / 滚花快门盘 / 前后摄

    private func bottomDeck(_ t: ThemeTokens) -> some View {
        HStack(alignment: .center, spacing: 16) {
            albumButton(t)

            ShutterDial(tokens: t,
                        isRecording: manager.isRecording,
                        mode: manager.mode,
                        onShoot: shoot,
                        onRotate: rotateShutter,
                        onEndRotate: endRotate)
                .frame(width: 96, height: 96)
                .accessibilityLabel(shutterVerb(manager))

            flipButton(t)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, t.inset)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private func albumButton(_ t: ThemeTokens) -> some View {
        PhysicalButton(tokens: t, radius: 7, action: { manager.openAlbum() }) {
            ZStack {
                if let latest = manager.albumItems.first {
                    MediaThumbnail(item: latest, maxPixel: 220, fill: true)
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .overlay(RoundedRectangle(cornerRadius: 3)
                            .stroke(.black.opacity(0.45), lineWidth: 1))
                } else {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(t.inkDim)
                        .frame(width: 42, height: 42)
                }
            }
            .padding(5)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("打开相册")
    }

    private func flipButton(_ t: ThemeTokens) -> some View {
        PhysicalButton(tokens: t, radius: 7, action: { manager.switchCamera() }) {
            VStack(spacing: 2) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(manager.isRecording ? t.inkDim.opacity(0.4) : t.ink)
                    .rotationEffect(.degrees(manager.isFrontCamera ? 180 : 0))
                    .animation(.easeInOut(duration: 0.28), value: manager.isFrontCamera)
                EngravedText(text: manager.isFrontCamera ? "FRONT" : "REAR",
                             tokens: t, size: 6, weight: .regular, tracking: 0.8)
            }
            .frame(width: 52, height: 52)
            .contentShape(Rectangle())
        }
        .disabled(manager.isRecording)
        .accessibilityLabel(manager.isFrontCamera ? "切换到后置摄像头" : "切换到前置摄像头")
    }

    // MARK: 动作

    private func shoot() {
        Haptics.impact(.medium)
        if manager.mode == .video { manager.toggleRecording() } else { manager.capturePhoto() }
    }

    /// 转盘横向拖动 = 改快门（对数刻度）
    private func rotateShutter(_ dx: CGFloat) {
        if dialBase == nil { dialBase = manager.shutterSeconds }
        let base = dialBase ?? manager.shutterSeconds
        let factor = exp(Double(dx) / 150)
        let value = min(max(base * factor, 0.00025), 0.25)
        manager.shutterSeconds = value
        manager.applyExposure()
    }

    private func endRotate() { dialBase = nil }

    private func toggleGroup() {
        manager.setParamMode(manager.paramMode == .exposure ? .whiteBalance : .exposure)
    }
}

// MARK: - 滚花快门盘

/// 点按 = 快门；横向拖动 = 调快门速度，转盘跟着转
struct ShutterDial: View {
    let tokens: ThemeTokens
    let isRecording: Bool
    let mode: CameraMode
    let onShoot: () -> Void
    let onRotate: (CGFloat) -> Void
    let onEndRotate: () -> Void

    @State private var angle: Double = 0
    @State private var dragging = false
    @State private var pressed = false

    var body: some View {
        ZStack {
            KnurledRing(tokens: tokens, teeth: 108, inner: 0.7)
                .rotationEffect(.degrees(angle))
                .shadow(color: .black.opacity(0.45), radius: 8, y: 4)

            // 刻度索引
            VStack {
                Rectangle()
                    .fill(tokens.accent)
                    .frame(width: 2, height: 7)
                    .offset(y: 3)
                Spacer()
            }

            Circle()
                .fill(LinearGradient(colors: [tokens.faceTop, tokens.faceBottom],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 62, height: 62)
                .overlay(Circle().strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.6), .black.opacity(0.5)],
                                   startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .shadow(color: .black.opacity(pressed ? 0.2 : 0.45),
                        radius: pressed ? 2 : 5, y: pressed ? 1 : 3)
                .overlay {
                    if isRecording && mode == .video {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(tokens.recRed)
                            .frame(width: 18, height: 18)
                    } else {
                        Text(mode == .video ? "REC" : "PRESS")
                            .font(tokens.labelFont(9, .semibold))
                            .tracking(1.2)
                            .foregroundColor(tokens.accent)
                    }
                }
        }
        .scaleEffect(pressed ? 0.97 : 1)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !pressed { pressed = true }
                    if abs(value.translation.width) > 4 { dragging = true }
                    if dragging {
                        onRotate(value.translation.width)
                        angle = Double(value.translation.width) * 0.55
                    }
                }
                .onEnded { _ in
                    pressed = false
                    if !dragging { onShoot() }
                    dragging = false
                    onEndRotate()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) { angle = 0 }
                }
        )
    }
}
