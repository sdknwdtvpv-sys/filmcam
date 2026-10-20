import SwiftUI

/// C · 实验室仪器
///
/// 半透明聚碳酸酯外壳，能看到里面的电路板，白色丝印 + 荧光绿读数。
/// 取景器是一块示波器式的监看屏，底部一颗大圆形执行键。
struct LabUnitCameraView: View {
    @EnvironmentObject var manager: CameraManager

    private var readout: Color { ThemeStore.current.glow }

    var body: some View {
        let t = ThemeStore.current

        ZStack {
            // 内部电路板
            PcbBackdrop().ignoresSafeArea()

            // 半透明外壳
            LinearGradient(colors: [.white.opacity(0.58), .white.opacity(0.42),
                                    .white.opacity(0.66)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            LinearGradient(colors: [.white.opacity(0.5), .clear],
                           startPoint: .topLeading, endPoint: .center)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header(t)
                scope(t)
                VStack(spacing: 0) {
                    readoutBar(t)
                    keypad(t)
                    execute(t)
                }
                .background(
                    LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.35)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .overlay(alignment: .top) {
                    Rectangle().fill(.white.opacity(0.7)).frame(height: 1)
                }
            }

            // 丝印外框
            Rectangle()
                .strokeBorder(.white.opacity(0.65), lineWidth: 1)
                .padding(7)
                .allowsHitTesting(false)
            DeviceEdge(radius: 0, intensity: 0.55)
        }
    }

    // MARK: 顶部丝印

    private func header(_ t: ThemeTokens) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text("FILMCAM")
                    .font(t.labelFont(14, .medium))
                    .tracking(3)
                    .foregroundColor(t.ink)
                Silkscreen(text: "LAB-03 · OPTICAL UNIT", color: t.ink.opacity(0.6),
                           size: 5.5, tracking: 1.4)
            }
            Spacer()
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { i in
                    LEDDot(color: i < statusLights ? t.glow : t.ink,
                           size: 5,
                           dimmed: i >= statusLights)
                }
            }
            Silkscreen(text: "PC-4", color: t.ink.opacity(0.45), size: 5.5, tracking: 1)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    /// 亮灯数量跟着"有没有画面 / 在不在录"走，不是装饰
    private var statusLights: Int {
        var n = manager.hasPreview ? 2 : 1
        if manager.isRecording { n = 5 }
        else if manager.authorizationStatus == .authorized { n += 1 }
        return n
    }

    // MARK: 示波器屏

    private func scope(_ t: ThemeTokens) -> some View {
        LCDWindow(tokens: t, bezel: 8, radius: 10) {
            ZStack {
                PreviewSurface(showsScrim: false)

                // 测量网格
                GeometryReader { geo in
                    Path { p in
                        let w = geo.size.width, h = geo.size.height
                        p.move(to: CGPoint(x: w / 2, y: 0)); p.addLine(to: CGPoint(x: w / 2, y: h))
                        p.move(to: CGPoint(x: 0, y: h / 2)); p.addLine(to: CGPoint(x: w, y: h / 2))
                        for i in 1..<4 {
                            let x = w * CGFloat(i) / 4
                            let y = h * CGFloat(i) / 4
                            p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: h))
                            p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y))
                        }
                    }
                    .stroke(readout.opacity(0.16), lineWidth: 0.5)
                }
                .allowsHitTesting(false)

                // 屏内文字
                VStack {
                    HStack {
                        Text("CH-1")
                            .font(t.monoFont(7, .bold))
                            .foregroundColor(readout.opacity(0.8))
                        Spacer()
                        Text(manager.isRecording ? "● REC" : "STANDBY")
                            .font(t.monoFont(7, .bold))
                            .foregroundColor(manager.isRecording ? t.recRed : readout.opacity(0.8))
                    }
                    Spacer()
                    HStack {
                        Text("\(Int(manager.iso)) ISO")
                            .font(t.monoFont(7, .medium))
                            .foregroundColor(readout.opacity(0.75))
                        Spacer()
                        Text(shutterLabel(manager.shutterSeconds))
                            .font(t.monoFont(7, .medium))
                            .foregroundColor(readout.opacity(0.75))
                    }
                }
                .padding(8)
                .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 16)
        .overlay(alignment: .topLeading) {
            Circle().fill(t.accent).frame(width: 5, height: 5).padding(12)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: 绿色读数条

    private func readoutBar(_ t: ThemeTokens) -> some View {
        let keys = visibleParams(manager)
        return HStack(spacing: 0) {
            ForEach(Array(keys.enumerated()), id: \.element) { index, key in
                if index > 0 {
                    Rectangle().fill(readout.opacity(0.22)).frame(width: 1, height: 20)
                }
                Button { manager.toggleParam(key) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(paramTitle(key))
                            .font(t.monoFont(6.5, .bold))
                            .tracking(0.8)
                            .foregroundColor(readout.opacity(0.55))
                        Text(paramValue(key, manager))
                            .font(t.monoFont(14, .bold))
                            .foregroundColor(manager.activeParam == key ? .white : readout)
                            .shadow(color: readout.opacity(0.6), radius: 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(paramTitle(key)) \(paramValue(key, manager))")
            }

            Button { toggleGroup() } label: {
                Text(manager.paramMode == .exposure ? "EXP" : "WB")
                    .font(t.monoFont(6.5, .bold))
                    .foregroundColor(readout)
                    .frame(width: 34, height: 28)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(readout.opacity(0.22)).frame(width: 1, height: 20)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("切换参数分组")
        }
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(LinearGradient(colors: [t.wellTop, t.wellBottom],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(readout.opacity(0.28), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    // MARK: 键区

    private func keypad(_ t: ThemeTokens) -> some View {
        HStack(spacing: 8) {
            LabeledKey(tokens: t, caption: "胶片", radius: 6, action: { manager.showFilmSheet = true }) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(t.ink)
            }
            LabeledKey(tokens: t, caption: "网格", radius: 6, action: { manager.showGrid.toggle() }) {
                Image(systemName: "grid")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(manager.showGrid ? t.accent : t.ink)
            }
            LabeledKey(tokens: t, caption: "设置", radius: 6, action: { manager.showSettingsSheet = true }) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(t.ink)
            }
            LabeledKey(tokens: t, caption: "相册", radius: 6, action: { manager.openAlbum() }) {
                Group {
                    if let latest = manager.albumItems.first {
                        MediaThumbnail(item: latest, maxPixel: 160, fill: true)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                    } else {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(t.inkDim)
                    }
                }
                .frame(width: 20, height: 20)
            }
            LabeledKey(tokens: t, caption: manager.isFrontCamera ? "前置" : "后置",
                       radius: 6, action: { manager.switchCamera() }) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(t.ink)
                    .rotationEffect(.degrees(manager.isFrontCamera ? 180 : 0))
                    .animation(.easeInOut(duration: 0.28), value: manager.isFrontCamera)
            }
            .disabled(manager.isRecording)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: 执行键

    private func execute(_ t: ThemeTokens) -> some View {
        VStack(spacing: 10) {
            ParamTuningPanel()

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 1) {
                    Silkscreen(text: "EXEC", color: t.ink.opacity(0.75), size: 7, tracking: 1.6)
                    Silkscreen(text: "SHUTTER", color: t.ink.opacity(0.5), size: 6, tracking: 1.2)
                }
                .frame(width: 54, alignment: .leading)

                Spacer(minLength: 0)

                Button {
                    Haptics.impact(.heavy)
                    if manager.mode == .video { manager.toggleRecording() } else { manager.capturePhoto() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [t.faceTop, t.faceBottom],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: 86, height: 86)
                            .overlay(Circle().strokeBorder(.black.opacity(0.35), lineWidth: 1))
                            .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                        Circle()
                            .strokeBorder(manager.isRecording ? t.recRed : t.accent, lineWidth: 2.5)
                            .frame(width: 70, height: 70)
                            .shadow(color: (manager.isRecording ? t.recRed : t.glow).opacity(0.6),
                                    radius: 8)
                        if manager.isRecording && manager.mode == .video {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(t.recRed)
                                .frame(width: 22, height: 22)
                        } else {
                            Circle()
                                .fill(t.accent)
                                .frame(width: 26, height: 26)
                                .overlay(Circle().fill(.white.opacity(0.35))
                                    .frame(width: 7, height: 7)
                                    .offset(x: -6, y: -6))
                        }
                    }
                    .contentShape(Circle())
                }
                .buttonStyle(PressScaleStyle(scale: 0.95))
                .accessibilityLabel(shutterVerb(manager))

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    ForEach(CameraMode.allCases) { mode in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { manager.mode = mode }
                        } label: {
                            Text(mode.label)
                                .font(t.labelFont(9.5, .medium))
                                .tracking(0.4)
                                .foregroundColor(manager.mode == mode ? .white : t.inkDim)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(manager.mode == mode ? t.accent : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 54, alignment: .trailing)
            }
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .padding(.bottom, 18)
        }
    }

    private func toggleGroup() {
        manager.setParamMode(manager.paramMode == .exposure ? .whiteBalance : .exposure)
    }
}
