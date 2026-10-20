import SwiftUI

/// B · 模块化摄影机
///
/// 碳纤机身套在铝框里：顶部横提手、四角内六角螺丝、侧边散热槽。
/// 取景器是机身上的一块监看屏，顶部一条红色 Tally，底部是录制盘。
struct CineRigCameraView: View {
    @EnvironmentObject var manager: CameraManager

    var body: some View {
        let t = ThemeStore.current

        ZStack {
            MetalSurface(tokens: t).ignoresSafeArea()

            VStack(spacing: 0) {
                topBar(t)
                monitor(t)
                dataStrip(t)
                deck(t)
            }

            frameRails(t)
        }
    }

    // MARK: 顶部提手

    private func topBar(_ t: ThemeTokens) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HexScrew(size: 10)
                Text("RIG-02")
                    .font(t.monoFont(9, .bold))
                    .tracking(2)
                    .foregroundColor(t.ink.opacity(0.72))
                Rectangle().fill(t.ink.opacity(0.2)).frame(width: 1, height: 10)
                Text("A-CAM")
                    .font(t.monoFont(8, .medium))
                    .tracking(1.4)
                    .foregroundColor(t.inkDim)
                Spacer()
                LEDDot(color: manager.isRecording ? t.recRed : t.glow, size: 6)
                Text(manager.isRecording ? "REC" : "STBY")
                    .font(t.monoFont(8, .bold))
                    .tracking(1.2)
                    .foregroundColor(manager.isRecording ? t.recRed : t.ink.opacity(0.7))
                HexScrew(size: 10)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(
                LinearGradient(colors: [t.faceTop, t.faceBottom], startPoint: .top, endPoint: .bottom)
            )
            .overlay(alignment: .bottom) {
                Rectangle().fill(.black.opacity(0.65)).frame(height: 1)
            }
            .overlay(alignment: .top) {
                Rectangle().fill(.white.opacity(0.28)).frame(height: 1)
            }
            .padding(.horizontal, 10)
            .padding(.top, 12)

            // 提手与机身之间的空隙
            HStack {
                Rectangle().fill(.black.opacity(0.55)).frame(width: 26, height: 9)
                Spacer()
                Rectangle().fill(.black.opacity(0.55)).frame(width: 26, height: 9)
            }
            .padding(.horizontal, 26)
        }
    }

    // MARK: 监看屏

    private func monitor(_ t: ThemeTokens) -> some View {
        InsetWell(tokens: t, radius: 5) {
            PreviewSurface(showsScrim: true)
                .overlay(alignment: .top) {
                    // Tally
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(manager.isRecording ? t.recRed : t.accent.opacity(0.35))
                            .frame(width: 34, height: 2)
                            .shadow(color: manager.isRecording ? t.recRed.opacity(0.9) : .clear,
                                    radius: 4)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                }
                .overlay(alignment: .topLeading) { corner(t, 0) }
                .overlay(alignment: .topTrailing) { corner(t, 90) }
                .overlay(alignment: .bottomTrailing) { corner(t, 180) }
                .overlay(alignment: .bottomLeading) { corner(t, 270) }
                .padding(4)
        }
        .padding(.horizontal, t.inset)
        .padding(.top, 12)
        .frame(maxHeight: .infinity)
    }

    private func corner(_ t: ThemeTokens, _ angle: Double) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 11))
            p.addLine(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: 11, y: 0))
        }
        .stroke(t.accent.opacity(0.7), lineWidth: 1.5)
        .frame(width: 12, height: 12)
        .rotationEffect(.degrees(angle))
        .padding(8)
        .allowsHitTesting(false)
    }

    // MARK: 数据条

    private func dataStrip(_ t: ThemeTokens) -> some View {
        let keys = visibleParams(manager)
        return HStack(spacing: 0) {
            ForEach(Array(keys.enumerated()), id: \.element) { index, key in
                if index > 0 {
                    Rectangle().fill(t.hairline).frame(width: 1, height: 24)
                }
                Button { manager.toggleParam(key) } label: {
                    VStack(alignment: .leading, spacing: -1) {
                        HStack(spacing: 3) {
                            Text(paramTitle(key))
                                .font(t.monoFont(7, .bold))
                                .tracking(1)
                                .foregroundColor(manager.activeParam == key ? t.accent : t.inkDim)
                            if manager.activeParam == key {
                                LEDDot(color: t.glow, size: 3)
                            }
                        }
                        Text(paramValue(key, manager))
                            .font(t.monoFont(15, .bold))
                            .foregroundColor(manager.activeParam == key ? t.accentGlow : t.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(paramTitle(key)) \(paramValue(key, manager))")
            }

            Button { toggleGroup() } label: {
                Text(manager.paramMode == .exposure ? "EXP" : "WB")
                    .font(t.monoFont(7, .bold))
                    .foregroundColor(t.accent)
                    .frame(width: 36, height: 34)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(t.hairline).frame(width: 1, height: 24)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("切换参数分组")
        }
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: [t.wellTop, t.wellBottom],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(LinearGradient(colors: [.black.opacity(0.9), .white.opacity(0.16)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1.2)
        )
        .padding(.horizontal, t.inset)
        .padding(.top, 10)
    }

    // MARK: 底舱

    private func deck(_ t: ThemeTokens) -> some View {
        VStack(spacing: 10) {
            ParamTuningPanel()

            HStack(spacing: 12) {
                LabeledKey(tokens: t, caption: "相册", radius: 6, action: { manager.openAlbum() }) {
                    Group {
                        if let latest = manager.albumItems.first {
                            MediaThumbnail(item: latest, maxPixel: 200, fill: true)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        } else {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(t.inkDim)
                        }
                    }
                    .frame(width: 30, height: 30)
                }
                .frame(width: 54)
                .accessibilityLabel("打开相册")

                Spacer(minLength: 0)

                recordButton(t)

                Spacer(minLength: 0)

                LabeledKey(tokens: t, caption: manager.isFrontCamera ? "前置" : "后置",
                           radius: 6, action: { manager.switchCamera() }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(t.ink)
                        .rotationEffect(.degrees(manager.isFrontCamera ? 180 : 0))
                        .animation(.easeInOut(duration: 0.28), value: manager.isFrontCamera)
                }
                .frame(width: 54)
                .disabled(manager.isRecording)
            }
            .padding(.horizontal, t.inset)

            HStack(spacing: 6) {
                ForEach(CameraMode.allCases) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { manager.mode = mode }
                    } label: {
                        HStack(spacing: 4) {
                            LEDDot(color: manager.mode == mode ? t.glow : t.inkDim,
                                   size: 4, dimmed: manager.mode != mode)
                            Text(mode.label)
                                .font(t.labelFont(9, .medium))
                                .tracking(0.6)
                                .foregroundColor(manager.mode == mode ? t.ink : t.inkDim)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(manager.mode == mode ? t.accent.opacity(0.6) : t.hairline,
                                        lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                VentSlots(count: 4, color: t.elevated, slotWidth: 2.5, slotHeight: 16)
                    .padding(.leading, 4)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, t.inset)
            .padding(.bottom, 8)
        }
    }

    private func recordButton(_ t: ThemeTokens) -> some View {
        Button {
            Haptics.impact(.heavy)
            if manager.mode == .video { manager.toggleRecording() } else { manager.capturePhoto() }
        } label: {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [t.faceTop, t.faceBottom],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 84, height: 84)
                    .overlay(Circle().strokeBorder(.black.opacity(0.5), lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
                Circle()
                    .strokeBorder(t.accent.opacity(manager.isRecording ? 1 : 0.55), lineWidth: 2)
                    .frame(width: 68, height: 68)
                if manager.isRecording && manager.mode == .video {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(t.recRed)
                        .frame(width: 26, height: 26)
                        .shadow(color: t.recRed.opacity(0.8), radius: 8)
                } else {
                    Circle()
                        .fill(t.recRed)
                        .frame(width: 34, height: 34)
                        .shadow(color: t.recRed.opacity(0.55), radius: 8)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.95))
        .accessibilityLabel(shutterVerb(manager))
    }

    // MARK: 铝框与螺丝

    private func frameRails(_ t: ThemeTokens) -> some View {
        ZStack {
            DeviceEdge(radius: 0, intensity: 0.8)
            VStack {
                HStack {
                    HexScrew(size: 9)
                    Spacer()
                    HexScrew(size: 9)
                }
                Spacer()
                HStack {
                    HexScrew(size: 9)
                    Spacer()
                    HexScrew(size: 9)
                }
            }
            .padding(8)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
    }

    private func toggleGroup() {
        manager.setParamMode(manager.paramMode == .exposure ? .whiteBalance : .exposure)
    }
}
