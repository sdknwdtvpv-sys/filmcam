import SwiftUI

/// B · 驾驶舱
///
/// 喷砂石墨仪表台：四角沉头螺丝、顶部 LED 读数条、凹陷玻璃取景井、
/// 一块刻字的仪表集群，快门是一整块压板。
struct CockpitCameraView: View {
    @EnvironmentObject var manager: CameraManager

    var body: some View {
        let t = ThemeStore.current

        ZStack {
            MetalSurface(tokens: t).ignoresSafeArea()

            VStack(spacing: 0) {
                statusStrip(t)
                gaugeWell(t)
                cluster(t)
                tuningTray(t)
                switchRow(t)
                platen(t)
            }
            .padding(.horizontal, 0)

            // 四角螺丝
            VStack {
                HStack { ScrewHead(tokens: t, size: 10); Spacer(); ScrewHead(tokens: t, size: 10) }
                Spacer()
                HStack { ScrewHead(tokens: t, size: 10); Spacer(); ScrewHead(tokens: t, size: 10) }
            }
            .padding(10)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
    }

    // MARK: 顶部状态条

    private func statusStrip(_ t: ThemeTokens) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                LEDDot(color: manager.isRecording ? t.recRed : t.glow,
                       size: 6)
                Text(manager.isRecording ? "REC" : "STANDBY")
                    .font(t.monoFont(9, .bold))
                    .tracking(1.6)
                    .foregroundColor(manager.isRecording ? t.recRed : t.ink)
                Text("FILMCAM")
                    .font(t.monoFont(9, .bold))
                    .tracking(2.4)
                    .foregroundColor(t.inkDim)
                Spacer()
                Text("1080P·30")
                    .font(t.monoFont(8, .medium))
                    .tracking(1)
                    .foregroundColor(t.inkDim)
            }

            LEDBar(tokens: t, value: manager.bias / 2)
                .frame(height: 9)
        }
        .padding(.horizontal, t.inset)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    // MARK: 取景井

    private func gaugeWell(_ t: ThemeTokens) -> some View {
        InsetWell(tokens: t, radius: 6) {
            PreviewSurface(showsScrim: true)
                .overlay(
                    LinearGradient(colors: [.white.opacity(0.05), .clear, .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .allowsHitTesting(false)
                )
                .overlay(alignment: .topLeading) { cornerBracket(t, .topLeading) }
                .overlay(alignment: .topTrailing) { cornerBracket(t, .topTrailing) }
                .overlay(alignment: .bottomLeading) { cornerBracket(t, .bottomLeading) }
                .overlay(alignment: .bottomTrailing) { cornerBracket(t, .bottomTrailing) }
                .padding(3)
        }
        .padding(.horizontal, t.inset)
        .frame(maxHeight: .infinity)
    }

    private func cornerBracket(_ t: ThemeTokens, _ corner: Alignment) -> some View {
        let rotation: Double = {
            switch corner {
            case .topTrailing: return 90
            case .bottomTrailing: return 180
            case .bottomLeading: return 270
            default: return 0
            }
        }()
        return Path { p in
            p.move(to: CGPoint(x: 0, y: 12))
            p.addLine(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: 12, y: 0))
        }
        .stroke(t.accent.opacity(0.85), lineWidth: 1.5)
        .frame(width: 13, height: 13)
        .rotationEffect(.degrees(rotation))
        .padding(7)
        .allowsHitTesting(false)
    }

    // MARK: 仪表集群

    private func cluster(_ t: ThemeTokens) -> some View {
        let keys = visibleParams(manager)
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(keys.enumerated()), id: \.element) { index, key in
                    if index > 0 {
                        GrooveLine(horizontal: false).frame(height: 34)
                    }
                    Button { manager.toggleParam(key) } label: {
                        VStack(alignment: .leading, spacing: -1) {
                            HStack(spacing: 4) {
                                Text(paramTitle(key))
                                    .font(t.monoFont(8, .bold))
                                    .tracking(1.4)
                                    .foregroundColor(manager.activeParam == key ? t.accent : t.inkDim)
                                if manager.activeParam == key {
                                    LEDDot(color: t.glow, size: 4)
                                }
                            }
                            Text(paramValue(key, manager))
                                .font(t.displayFont(22, .regular))
                                .foregroundColor(manager.activeParam == key ? t.accentGlow : t.ink)
                                .shadow(color: manager.activeParam == key ? t.glow.opacity(0.6) : .clear,
                                        radius: 6)
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
                    VStack(spacing: 2) {
                        Image(systemName: "arrow.2.squarepath")
                            .font(.system(size: 10, weight: .bold))
                        Text(manager.paramMode == .exposure ? "EXP" : "WB")
                            .font(t.monoFont(7, .bold))
                    }
                    .foregroundColor(t.accent)
                    .frame(width: 40)
                    .frame(height: 44)
                    .overlay(alignment: .leading) { GrooveLine(horizontal: false) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("切换参数分组")
            }
            .frame(height: 46)
        }
        .background(
            RoundedRectangle(cornerRadius: t.radius)
                .fill(LinearGradient(colors: [t.wellBottom, t.wellTop],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: t.radius)
                .strokeBorder(LinearGradient(colors: [.black.opacity(0.8), .white.opacity(0.16)],
                                             startPoint: .top, endPoint: .bottom),
                              lineWidth: 1.5)
        )
        .padding(.horizontal, t.inset)
        .padding(.top, 10)
    }

    // MARK: 滑杆托盘

    private func tuningTray(_ t: ThemeTokens) -> some View {
        Group {
            if manager.activeParam != nil {
                ParamTuningPanel()
                    .background(
                        RoundedRectangle(cornerRadius: t.radius)
                            .fill(LinearGradient(colors: [t.wellBottom, t.wellTop],
                                                 startPoint: .top, endPoint: .bottom))
                    )
                    .padding(.horizontal, t.inset)
            }
        }
    }

    // MARK: 模式拨杆

    private func switchRow(_ t: ThemeTokens) -> some View {
        HStack(spacing: 8) {
            ForEach(CameraMode.allCases) { mode in
                let active = manager.mode == mode
                PhysicalButton(tokens: t, radius: 3, action: {
                    withAnimation(.easeInOut(duration: 0.15)) { manager.mode = mode }
                }) {
                    VStack(spacing: 3) {
                        // 拨杆头
                        RoundedRectangle(cornerRadius: 2)
                            .fill(LinearGradient(colors: [.white.opacity(0.35), .black.opacity(0.35)],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: 22, height: 9)
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .strokeBorder(.black.opacity(0.5), lineWidth: 0.5)
                            )
                            .offset(y: active ? -1 : 1)
                        Text(mode.label)
                            .font(t.labelFont(10, .semibold))
                            .tracking(0.6)
                            .foregroundColor(active ? t.ink : t.inkDim)
                        LEDDot(color: t.glow, size: 4, dimmed: !active)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
            }
        }
        .padding(.horizontal, t.inset)
        .padding(.top, 8)
    }

    // MARK: 压板快门

    private func platen(_ t: ThemeTokens) -> some View {
        HStack(spacing: 10) {
            PhysicalButton(tokens: t, radius: 5, action: { manager.openAlbum() }) {
                Group {
                    if let latest = manager.albumItems.first {
                        MediaThumbnail(item: latest, maxPixel: 200, fill: true)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    } else {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(t.inkDim)
                    }
                }
                .frame(width: 40, height: 40)
                .padding(4)
            }
            .accessibilityLabel("打开相册")

            PhysicalButton(tokens: t, radius: 5, action: shoot) {
                HStack(spacing: 10) {
                    LEDDot(color: manager.isRecording ? t.recRed : t.accent, size: 7)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(shutterVerb(manager))
                            .font(t.displayFont(19, .regular))
                            .foregroundColor(t.ink)
                        Text(shutterHint(manager))
                            .font(t.monoFont(7, .bold))
                            .tracking(1.8)
                            .foregroundColor(t.inkDim)
                    }
                    Spacer(minLength: 0)
                    // 右侧泄压槽
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { _ in
                            Rectangle().fill(t.ink.opacity(0.25)).frame(width: 2, height: 16)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(shutterVerb(manager))

            PhysicalButton(tokens: t, radius: 5, action: { manager.switchCamera() }) {
                VStack(spacing: 2) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(manager.isRecording ? t.inkDim.opacity(0.35) : t.ink)
                        .rotationEffect(.degrees(manager.isFrontCamera ? 180 : 0))
                        .animation(.easeInOut(duration: 0.28), value: manager.isFrontCamera)
                    Text(manager.isFrontCamera ? "FRONT" : "REAR")
                        .font(t.monoFont(6, .bold))
                        .foregroundColor(t.inkDim)
                }
                .frame(width: 40, height: 40)
                .padding(4)
            }
            .disabled(manager.isRecording)
            .accessibilityLabel(manager.isFrontCamera ? "切换到后置摄像头" : "切换到前置摄像头")
        }
        .padding(.horizontal, t.inset)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: 动作

    private func shoot() {
        Haptics.impact(.heavy)
        if manager.mode == .video { manager.toggleRecording() } else { manager.capturePhoto() }
    }

    private func toggleGroup() {
        manager.setParamMode(manager.paramMode == .exposure ? .whiteBalance : .exposure)
    }
}

// MARK: - LED 读数条

struct LEDBar: View {
    let tokens: ThemeTokens
    /// -1 ... 1，从中点向两侧点亮
    let value: Double
    var count: Int = 17

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { i in
                let p = Double(i) / Double(count - 1) * 2 - 1
                let lit = p == 0 || (abs(p) <= abs(value) && (p > 0) == (value > 0))
                let hot = abs(p) > 0.7
                RoundedRectangle(cornerRadius: 1)
                    .fill(lit ? (hot ? tokens.recRed : tokens.glow)
                              : tokens.ink.opacity(0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 1)
                            .strokeBorder(.black.opacity(lit ? 0 : 0.35), lineWidth: 0.5)
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: abs(p) > 0.7 ? 7 : 9)
                    .shadow(color: lit ? (hot ? tokens.recRed : tokens.glow).opacity(0.85) : .clear,
                            radius: 3)
            }
        }
    }
}
