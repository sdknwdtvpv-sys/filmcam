import SwiftUI

/// C · 模块机架
///
/// 碳纤机身 + 机加工铝框：顶部铝制导轨、厚边框取景窗、里程表式帧计数器，
/// 右下一个大镜头环 —— 按下去就是快门。
struct RigCameraView: View {
    @EnvironmentObject var manager: CameraManager
    @State private var ringPressed = false

    var body: some View {
        let t = ThemeStore.current

        ZStack {
            MetalSurface(tokens: t).ignoresSafeArea()

            // 机加工边框
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.34), .white.opacity(0.05),
                                            .black.opacity(0.6)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 2)
                .padding(6)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                topRail(t)
                viewfinderBezel(t)
                counterDrum(t)
                tuningTray(t)
                bottomDeck(t)
            }

            // 边框螺丝
            VStack {
                HStack { ScrewHead(tokens: t, size: 8); Spacer(); ScrewHead(tokens: t, size: 8) }
                Spacer()
                HStack { ScrewHead(tokens: t, size: 8); Spacer(); ScrewHead(tokens: t, size: 8) }
            }
            .padding(14)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
    }

    // MARK: 铝制导轨

    private func topRail(_ t: ThemeTokens) -> some View {
        HStack(spacing: 8) {
            Text("FILMCAM")
                .font(t.labelFont(11, .semibold))
                .tracking(3)
                .foregroundColor(Color(hex: 0x1A1C1F))
            Rectangle().fill(Color(hex: 0x1A1C1F, opacity: 0.25))
                .frame(width: 1, height: 10)
            Text("RIG-02")
                .font(t.monoFont(8, .bold))
                .tracking(1.4)
                .foregroundColor(Color(hex: 0x1A1C1F, opacity: 0.6))
            Spacer()
            LEDDot(color: t.glow, size: 5)
            Text(manager.isRecording ? "REC" : "ARMED")
                .font(t.monoFont(8, .bold))
                .tracking(1.2)
                .foregroundColor(Color(hex: 0x1A1C1F, opacity: 0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            LinearGradient(colors: [Color(hex: 0xD8DBDE), Color(hex: 0x9FA5AA)],
                           startPoint: .top, endPoint: .bottom)
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(.black.opacity(0.55)).frame(height: 1)
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
    }

    // MARK: 取景窗（厚边框）

    private func viewfinderBezel(_ t: ThemeTokens) -> some View {
        InsetWell(tokens: t, radius: 6) {
            PreviewSurface(showsScrim: true)
                .overlay(alignment: .top) {
                    Rectangle().fill(t.accent).frame(height: 1.5).opacity(0.55)
                }
                .overlay(alignment: .topLeading) { bracket(t, 0) }
                .overlay(alignment: .topTrailing) { bracket(t, 90) }
                .overlay(alignment: .bottomTrailing) { bracket(t, 180) }
                .overlay(alignment: .bottomLeading) { bracket(t, 270) }
                .padding(4)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.28), .black.opacity(0.55)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1.5)
                .padding(1)
                .allowsHitTesting(false)
        )
        .padding(.horizontal, t.inset)
        .padding(.top, 12)
        .frame(maxHeight: .infinity)
    }

    private func bracket(_ t: ThemeTokens, _ angle: Double) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 14))
            p.addLine(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: 14, y: 0))
        }
        .stroke(t.accent.opacity(0.75), lineWidth: 2)
        .frame(width: 15, height: 15)
        .rotationEffect(.degrees(angle))
        .padding(8)
        .allowsHitTesting(false)
    }

    // MARK: 帧计数鼓

    private func counterDrum(_ t: ThemeTokens) -> some View {
        let digits = Array(String(format: "%03d", manager.frameCount))
        return HStack(spacing: 10) {
            HStack(spacing: 3) {
                ForEach(Array(digits.enumerated()), id: \.offset) { _, ch in
                    ZStack {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(colors: [Color(hex: 0x0A0B0D),
                                                          Color(hex: 0x22262A),
                                                          Color(hex: 0x0A0B0D)],
                                                 startPoint: .top, endPoint: .bottom))
                        // 轴
                        VStack {
                            Circle().fill(t.ink.opacity(0.25)).frame(width: 2, height: 2)
                            Spacer()
                            Circle().fill(t.ink.opacity(0.25)).frame(width: 2, height: 2)
                        }
                        .padding(.vertical, 3)
                        Text(String(ch))
                            .font(t.displayFont(22, .regular))
                            .foregroundColor(Color(hex: 0xF4F5F7))
                            .monospacedDigit()
                    }
                    .frame(width: 26, height: 38)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(LinearGradient(colors: [.black.opacity(0.9),
                                                                  .white.opacity(0.2)],
                                                         startPoint: .top, endPoint: .bottom),
                                          lineWidth: 1)
                    )
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("FRAMES")
                    .font(t.monoFont(7, .bold))
                    .tracking(2)
                    .foregroundColor(t.inkDim)
                Button { manager.showFilmSheet = true } label: {
                    HStack(spacing: 4) {
                        Text(manager.selectedPreset.label)
                            .font(t.labelFont(12, .semibold))
                            .foregroundColor(t.ink)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(t.accent)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(Int(manager.iso)) · \(shutterLabel(manager.shutterSeconds))")
                    .font(t.monoFont(9, .medium))
                    .foregroundColor(t.inkDim)
                Button { manager.setParamMode(manager.paramMode == .exposure ? .whiteBalance : .exposure) } label: {
                    Text(manager.paramMode == .exposure ? "EXP" : "WB")
                        .font(t.monoFont(7, .bold))
                        .tracking(1)
                        .foregroundColor(t.accent)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .overlay(RoundedRectangle(cornerRadius: 2)
                            .stroke(t.accent.opacity(0.55), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, t.inset)
        .padding(.top, 12)
    }

    private func tuningTray(_ t: ThemeTokens) -> some View {
        Group {
            if manager.activeParam != nil {
                ParamTuningPanel()
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(LinearGradient(colors: [t.wellTop, t.wellBottom],
                                                 startPoint: .top, endPoint: .bottom))
                    )
                    .padding(.horizontal, t.inset)
            }
        }
    }

    // MARK: 底舱

    private func bottomDeck(_ t: ThemeTokens) -> some View {
        HStack(alignment: .center) {
            PhysicalButton(tokens: t, radius: 8, action: { manager.openAlbum() }) {
                Group {
                    if let latest = manager.albumItems.first {
                        MediaThumbnail(item: latest, maxPixel: 220, fill: true)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(t.inkDim)
                    }
                }
                .frame(width: 44, height: 50)
                .padding(4)
            }
            .accessibilityLabel("打开相册")

            Spacer(minLength: 0)

            LensRingShutter(tokens: t,
                            isRecording: manager.isRecording,
                            mode: manager.mode,
                            action: shoot)
                .frame(width: 104, height: 104)
                .accessibilityLabel(shutterVerb(manager))

            Spacer(minLength: 0)

            PhysicalButton(tokens: t, radius: 8, action: { manager.switchCamera() }) {
                VStack(spacing: 2) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(manager.isRecording ? t.inkDim.opacity(0.35) : t.ink)
                        .rotationEffect(.degrees(manager.isFrontCamera ? 180 : 0))
                        .animation(.easeInOut(duration: 0.28), value: manager.isFrontCamera)
                    Text(manager.isFrontCamera ? "F" : "R")
                        .font(t.monoFont(7, .bold))
                        .foregroundColor(t.inkDim)
                }
                .frame(width: 44, height: 50)
                .padding(4)
            }
            .disabled(manager.isRecording)
            .accessibilityLabel(manager.isFrontCamera ? "切换到后置摄像头" : "切换到前置摄像头")
        }
        .padding(.horizontal, t.inset)
        .padding(.bottom, 6)
    }

    // MARK: 动作

    private func shoot() {
        Haptics.impact(.heavy)
        if manager.mode == .video { manager.toggleRecording() } else { manager.capturePhoto() }
    }
}

// MARK: - 镜头环快门

struct LensRingShutter: View {
    let tokens: ThemeTokens
    let isRecording: Bool
    let mode: CameraMode
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.impact(.heavy)
            action()
        } label: {
            ZStack {
                // 外环（机加工）
                Circle()
                    .fill(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.12),
                                                  .black.opacity(0.7)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: .black.opacity(0.65), radius: 12, y: 6)

                // 滚花环
                KnurledRing(tokens: tokens, teeth: 120, inner: 0.8)
                    .padding(6)

                // 内筒
                Circle()
                    .fill(LinearGradient(colors: [tokens.faceTop, tokens.faceBottom],
                                         startPoint: .top, endPoint: .bottom))
                    .padding(17)
                    .overlay(
                        Circle()
                            .strokeBorder(LinearGradient(
                                colors: [.white.opacity(0.4), .black.opacity(0.6)],
                                startPoint: .top, endPoint: .bottom), lineWidth: 1)
                            .padding(17)
                    )

                // 镜芯
                Circle()
                    .fill(RadialGradient(colors: [tokens.elevated, tokens.background],
                                         center: .topLeading, startRadius: 2, endRadius: 40))
                    .padding(30)

                if isRecording && mode == .video {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(tokens.recRed)
                        .frame(width: 16, height: 16)
                } else {
                    Circle()
                        .fill(tokens.accent)
                        .frame(width: 9, height: 9)
                        .shadow(color: tokens.glow.opacity(0.9), radius: 6)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.962))
    }
}
