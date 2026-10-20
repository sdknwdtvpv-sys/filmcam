import SwiftUI

/// A · 机加工测距仪
///
/// 整屏就是一台机器的背面：铝制顶盖 + 黑色蒙皮机身 + 铝制底盖。
/// 取景器是嵌在蒙皮里的一块 LCD，顶盖上有两个滚花盘，快门是右下的大滚花盘。
struct RangefinderCameraView: View {
    @EnvironmentObject var manager: CameraManager

    private var lcdInk: Color { Color(hex: 0xF2F4F6) }

    var body: some View {
        let t = ThemeStore.current

        ZStack {
            // 机身：黑蒙皮
            LeatherPanel().ignoresSafeArea()
            LinearGradient(colors: [.white.opacity(0.05), .clear, .black.opacity(0.25)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topPlate(t)
                waist(t)
                bottomPlate(t)
            }

            DeviceEdge(radius: 0, intensity: 1)
        }
    }

    // MARK: 铝制顶盖

    private func topPlate(_ t: ThemeTokens) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("FILMCAM")
                        .font(t.labelFont(16, .medium))
                        .tracking(3.4)
                        .foregroundColor(t.ink)
                    Silkscreen(text: "M-01 RANGEFINDER", color: t.ink.opacity(0.55),
                               size: 6, tracking: 1.6)
                }
                .padding(.top, 2)

                Spacer(minLength: 4)

                // 帧数窗
                VStack(spacing: 2) {
                    InsetWell(tokens: t, radius: 3) {
                        Text(String(format: "%02d", manager.frameCount % 36 + 1))
                            .font(t.monoFont(13, .bold))
                            .foregroundColor(lcdInk)
                            .frame(width: 26, height: 16)
                    }
                    Silkscreen(text: "FRAME", color: t.ink.opacity(0.5), size: 5.5, tracking: 0.9)
                }
                .padding(.top, 2)

                TopDial(tokens: t, caption: "T")
                TopDial(tokens: t, caption: "ISO")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)

            GrooveLine()
        }
        .background(
            LinearGradient(colors: [t.faceTop, t.faceBottom], startPoint: .top, endPoint: .bottom)
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(.black.opacity(0.5)).frame(height: 1)
        }
    }

    // MARK: 机身腰部（蒙皮 + 取景 LCD）

    private func waist(_ t: ThemeTokens) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Silkscreen(text: manager.selectedPreset.label, color: .white.opacity(0.62),
                           size: 7, tracking: 2)
                Spacer()
                LEDDot(color: t.glow, size: 4, dimmed: !manager.hasPreview)
                Silkscreen(text: manager.hasPreview ? "READY" : "BOOT",
                           color: .white.opacity(0.5), size: 5.5, tracking: 1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)

            LCDWindow(tokens: t, bezel: 5, radius: 7) {
                PreviewSurface(showsScrim: false)
            }
            .padding(.horizontal, 14)

            HStack(spacing: 6) {
                Silkscreen(text: "35MM · F2.8", color: .white.opacity(0.42), size: 6, tracking: 1.4)
                Spacer()
                Silkscreen(text: "SER. \(String(format: "%04d", manager.frameCount))",
                           color: .white.opacity(0.32), size: 6, tracking: 1.2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: 铝制底盖

    private func bottomPlate(_ t: ThemeTokens) -> some View {
        VStack(spacing: 8) {
            GrooveLine()

            readoutStrip(t)
                .padding(.horizontal, 14)
                .padding(.top, 8)

            HStack(spacing: 6) {
                ForEach(CameraMode.allCases) { mode in
                    LabeledKey(tokens: t, caption: mode.label, radius: 4, action: {
                        withAnimation(.easeInOut(duration: 0.15)) { manager.mode = mode }
                    }) {
                        LEDDot(color: manager.mode == mode ? t.accent : t.inkDim,
                               size: 5, dimmed: manager.mode != mode)
                    }
                }
                LabeledKey(tokens: t, caption: "胶片", radius: 4, action: { manager.showFilmSheet = true }) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(t.ink)
                }
            }
            .padding(.horizontal, 14)

            HStack(alignment: .center, spacing: 14) {
                albumWindow(t)
                Spacer(minLength: 0)
                shutterDial(t)
                Spacer(minLength: 0)
                flipKey(t)
            }
            .padding(.horizontal, 18)
            .padding(.top, 2)
            .padding(.bottom, 8)
        }
        .background(
            LinearGradient(colors: [t.faceTop, t.faceBottom], startPoint: .top, endPoint: .bottom)
        )
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.35)).frame(height: 1)
        }
    }

    private func readoutStrip(_ t: ThemeTokens) -> some View {
        let keys = visibleParams(manager)
        return HStack(spacing: 0) {
            ForEach(Array(keys.enumerated()), id: \.element) { index, key in
                if index > 0 {
                    Rectangle().fill(.white.opacity(0.14)).frame(width: 1, height: 22)
                }
                Button { manager.toggleParam(key) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(paramTitle(key))
                            .font(t.monoFont(6.5, .bold))
                            .tracking(0.8)
                            .foregroundColor(manager.activeParam == key ? t.accentGlow : .white.opacity(0.45))
                        Text(paramValue(key, manager))
                            .font(t.displayFont(15, .medium))
                            .foregroundColor(manager.activeParam == key ? lcdInk : .white.opacity(0.82))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(paramTitle(key)) \(paramValue(key, manager))")
            }

            Button { toggleGroup() } label: {
                Text(manager.paramMode == .exposure ? "EXP" : "WB")
                    .font(t.monoFont(6.5, .bold))
                    .foregroundColor(t.accentGlow)
                    .frame(width: 34, height: 30)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(.white.opacity(0.14)).frame(width: 1, height: 22)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("切换参数分组")
        }
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: [t.wellTop, t.wellBottom],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(LinearGradient(colors: [.black.opacity(0.85), .white.opacity(0.2)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1.2)
        )
        .overlay(alignment: .topLeading) {
            // 玻璃反光
            Rectangle().fill(.white.opacity(0.05)).frame(height: 1).padding(.top, 1)
        }
    }

    private func albumWindow(_ t: ThemeTokens) -> some View {
        Button { manager.openAlbum() } label: {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [t.faceBottom, t.faceTop],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 50, height: 50)
                    .overlay(Circle().strokeBorder(.black.opacity(0.45), lineWidth: 1))
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                if let latest = manager.albumItems.first {
                    MediaThumbnail(item: latest, maxPixel: 200, fill: true)
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(.black.opacity(0.5), lineWidth: 1))
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(t.inkDim)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开相册")
    }

    private func shutterDial(_ t: ThemeTokens) -> some View {
        Button {
            Haptics.impact(.heavy)
            if manager.mode == .video { manager.toggleRecording() } else { manager.capturePhoto() }
        } label: {
            ZStack {
                KnurledRing(tokens: t, teeth: 90, inner: 0.72)
                    .frame(width: 92, height: 92)
                    .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
                Circle()
                    .fill(LinearGradient(colors: [t.faceTop, t.faceBottom],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 60, height: 60)
                    .overlay(Circle().strokeBorder(.black.opacity(0.35), lineWidth: 1))
                if manager.isRecording && manager.mode == .video {
                    RoundedRectangle(cornerRadius: 3).fill(t.recRed).frame(width: 16, height: 16)
                } else {
                    Circle()
                        .fill(t.accent)
                        .frame(width: 8, height: 8)
                        .shadow(color: t.accent.opacity(0.7), radius: 4)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.96))
        .accessibilityLabel(shutterVerb(manager))
    }

    private func flipKey(_ t: ThemeTokens) -> some View {
        LabeledKey(tokens: t, caption: manager.isFrontCamera ? "前置" : "后置",
                   radius: 4, action: { manager.switchCamera() }) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(t.ink)
                .rotationEffect(.degrees(manager.isFrontCamera ? 180 : 0))
                .animation(.easeInOut(duration: 0.28), value: manager.isFrontCamera)
        }
        .frame(width: 54)
        .disabled(manager.isRecording)
        .accessibilityLabel(manager.isFrontCamera ? "切换到后置摄像头" : "切换到前置摄像头")
    }

    private func toggleGroup() {
        manager.setParamMode(manager.paramMode == .exposure ? .whiteBalance : .exposure)
    }
}

/// 顶盖上的滚花盘
struct TopDial: View {
    let tokens: ThemeTokens
    let caption: String

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                KnurledRing(tokens: tokens, teeth: 54, inner: 0.62)
                    .frame(width: 40, height: 40)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 2)
                Circle()
                    .fill(LinearGradient(colors: [tokens.faceTop, tokens.faceBottom],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 25, height: 25)
                    .overlay(Circle().strokeBorder(.black.opacity(0.3), lineWidth: 0.8))
                Rectangle()
                    .fill(tokens.accent)
                    .frame(width: 1.5, height: 7)
                    .offset(y: -7)
            }
            Silkscreen(text: caption, color: tokens.ink.opacity(0.65), size: 5.5, tracking: 1)
        }
    }
}
