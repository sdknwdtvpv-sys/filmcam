import SwiftUI

/// A · 机加工测距仪
///
/// 整屏就是一台机器的背面：铝制顶盖 + 黑色蒙皮机身 + 铝制底盖。
/// 取景器是嵌在蒙皮里的一块 LCD，顶盖上有两个滚花盘，快门是右下的大滚花盘。
struct RangefinderCameraView: View {
    @EnvironmentObject var manager: CameraManager

    /// 拖动快门环时的基准值 / 盘面角度 / 上一次触感所在的档位
    @State private var collarBase: Double?
    @State private var collarAngle: Double = 0
    @State private var lastBucket: Double = .nan
    /// 上一次触感所在的齿
    @State private var lastTooth: Double = .nan

    /// 快门键：按住不松手往左右拖就换模式
    @State private var shutterPressed = false
    @State private var shiftArmed = false
    @State private var shiftStart: CameraMode?
    @State private var shiftTarget: CameraMode?

    /// 滚花盘画了 96 颗齿，拖动 0.45°/pt，所以一颗齿 = 8.333pt 位移
    private let toothPitch: Double = 360.0 / 96.0 / 0.45
    /// 参数浮层（调参时在取景器里浮出）
    @State private var hud: (title: String, value: String, progress: Double)?
    @State private var hudToken = UUID()

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
        .onAppear {
            DetentFeedback.shared.prepare()
            #if DEBUG
            if DebugHarness.shouldShowHUD { announceArmed() }
            #endif
        }
    }

    // MARK: 铝制顶盖

    private func topPlate(_ t: ThemeTokens) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                ScrewHead(size: 7)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 1) {
                    Text("FUTURE CAM")
                        .font(t.labelFont(16, .medium))
                        .tracking(3.4)
                        .foregroundColor(t.ink)
                    Silkscreen(text: "M-01 RANGEFINDER", color: t.ink.opacity(0.55),
                               size: 6, tracking: 1.6)
                }
                .padding(.top, 2)

                Spacer(minLength: 2)

                // 闪光/补光：关 → 自动 → 开，视频模式下"开"同时点着手电
                VStack(spacing: 2) {
                    PhysicalButton(tokens: t, radius: 4, action: { manager.cycleFlash() }) {
                        Image(systemName: manager.flashState.symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(manager.flashState == .off ? t.inkDim : t.accent)
                            .frame(width: 34, height: 26)
                            .contentShape(Rectangle())
                    }
                    Silkscreen(text: "FLASH \(manager.flashState.label)",
                               color: t.ink.opacity(0.5), size: 5, tracking: 0.5)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("闪光 \(manager.flashState.label)，点按切换，当前模式 \(manager.mode.label)")
                .accessibilityAddTraits(.isButton)

                // 胶片型号窗：和闪光键同一套按键质感，液晶窗嵌在键面里
                VStack(spacing: 2) {
                    PhysicalButton(tokens: t, radius: 4, action: {
                        manager.showFilmSheet = true
                    }) {
                        HStack(spacing: 4) {
                            InsetWell(tokens: t, radius: 2) {
                                Text(manager.selectedPreset.label)
                                    .font(t.monoFont(8, .bold))
                                    .foregroundColor(lcdInk)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.62)
                                    .frame(width: 58, height: 16)
                            }
                            Image(systemName: "chevron.down")
                                .font(.system(size: 6, weight: .bold))
                                .foregroundColor(t.inkDim)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    Silkscreen(text: "FILM", color: t.ink.opacity(0.5), size: 5, tracking: 0.9)
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: FilmAnchorKey.self,
                                               value: proxy.frame(in: .global))
                    }
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("当前胶片 \(manager.selectedPreset.label)，点按更换")
                .accessibilityAddTraits(.isButton)

                ScrewHead(size: 7)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 10)

            GrooveLine()
        }
        .background(AluminumFace(tokens: t))
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
            .overlay {
                if let hud {
                    ParameterHUD(title: hud.title, value: hud.value,
                                 progress: hud.progress, tokens: t)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .task(id: hudToken) {
                            try? await Task.sleep(nanoseconds: 1_200_000_000)
                            guard !Task.isCancelled else { return }
                            withAnimation(.easeOut(duration: 0.25)) { self.hud = nil }
                        }
                        .allowsHitTesting(false)
                }
            }

            Color.clear.frame(height: 12)
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

            HStack(alignment: .bottom, spacing: 14) {
                VStack(spacing: 3) {
                    albumWindow(t)
                    Silkscreen(text: "相册", color: t.inkDim, size: 6, tracking: 0.8)
                }
                Spacer(minLength: 0)
                shutterDial(t)
                Spacer(minLength: 0)
                flipKey(t)
            }
            .padding(.horizontal, 18)
            .padding(.top, 2)

            HStack {
                Spacer()
                Silkscreen(text: "SER. \(String(format: "%05d", manager.frameCount))",
                           color: t.ink.opacity(0.45), size: 5.5, tracking: 1.2)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)
        }
        .background(AluminumFace(tokens: t))
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
                Button {
                    manager.selectParam(key)
                    announceArmed()
                    Haptics.impact(.light)
                } label: {
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
                    .overlay(alignment: .top) {
                        if manager.activeParam == key {
                            Rectangle().fill(t.accent).frame(height: 2)
                        }
                    }
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
        ZStack {
            // 外圈：滚花快门速度环（大目标、跟手、有棘轮触感）
            KnurledRing(tokens: t, teeth: 128, inner: 0.82)
                .frame(width: 120, height: 120)
                .rotationEffect(.degrees(collarAngle))
                .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
                .overlay(alignment: .top) {
                    // 红色索引
                    Rectangle()
                        .fill(t.accent)
                        .frame(width: 2, height: 8)
                        .offset(y: 1)
                        .rotationEffect(.degrees(collarAngle))
                }
                .contentShape(Circle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            turnCollar(value.translation.width)
                            collarAngle = Double(value.translation.width) * 0.45
                        }
                        .onEnded { _ in
                            collarBase = nil
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                collarAngle = 0
                            }
                        }
                )
                .accessibilityLabel("快门速度 \(shutterLabel(manager.shutterSeconds))")
                .accessibilityAdjustableAction { direction in
                    nudgeShutter(direction == .increment ? -1 : 1)
                }

            // 中心：快门 —— 原地松开是拍，按住左右拖是换模式
            shutterButton(t)
        }
    }

    private func shutterButton(_ t: ThemeTokens) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [t.faceTop, t.faceBottom],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(Circle().strokeBorder(.black.opacity(0.35), lineWidth: 1))
                .shadow(color: .black.opacity(shutterPressed ? 0.16 : 0.4),
                        radius: shutterPressed ? 1 : 4,
                        y: shutterPressed ? 0 : 2)
            shutterGlyph(t)
        }
        .frame(width: 82, height: 82)
        .contentShape(Circle())
        .scaleEffect(shutterPressed ? 0.95 : 1)
        .animation(.easeOut(duration: 0.12), value: shutterPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !shutterPressed { shutterPressed = true }
                    handleShutterDrag(value.translation.width)
                }
                .onEnded { _ in
                    shutterPressed = false
                    finishShutterDrag()
                }
        )
        .accessibilityElement()
        .accessibilityLabel(shutterVerb(manager))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            Haptics.impact(.heavy)
            if manager.mode == .video { manager.toggleRecording() } else { manager.capturePhoto() }
        }
    }

    /// 快门键面上的符号同时当模式指示：照片=点，双曝=点套环，视频=方框
    @ViewBuilder
    private func shutterGlyph(_ t: ThemeTokens) -> some View {
        if manager.mode == .video {
            RoundedRectangle(cornerRadius: 3)
                .fill(manager.isRecording ? t.recRed : .clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(t.recRed.opacity(manager.isRecording ? 0 : 0.9), lineWidth: 2)
                )
                .frame(width: 16, height: 16)
                .shadow(color: manager.isRecording ? t.recRed.opacity(0.6) : .clear, radius: 4)
        } else if manager.mode == .doubleExposure {
            ZStack {
                Circle().strokeBorder(t.accent.opacity(0.85), lineWidth: 1.8)
                    .frame(width: 22, height: 22)
                Circle().fill(t.accent).frame(width: 7, height: 7)
            }
            .shadow(color: t.accent.opacity(0.5), radius: 4)
        } else {
            Circle()
                .fill(t.accent)
                .frame(width: 9, height: 9)
                .shadow(color: t.accent.opacity(0.7), radius: 4)
        }
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

    /// 当前选中的参数 —— 滚花轮盘驱动它
    private var armed: ParamKey { manager.activeParam ?? .shutter }

    private var armedTitle: String {
        switch armed {
        case .iso: return "ISO"
        case .shutter: return "SHUTTER"
        case .bias: return "EXPOSURE"
        case .temperature: return "TEMP"
        case .tint: return "TINT"
        }
    }

    private func value(of key: ParamKey) -> Double {
        switch key {
        case .iso: return manager.iso
        case .shutter: return manager.shutterSeconds
        case .bias: return manager.bias
        case .temperature: return manager.temperature
        case .tint: return manager.tint
        }
    }

    /// 一盘多用：拖动滚花环，驱动当前选中的那一个参数
    private func turnCollar(_ dx: CGFloat) {
        if collarBase == nil {
            collarBase = value(of: armed)
            lastBucket = .nan
            lastTooth = .nan
        }
        let base = collarBase ?? value(of: armed)

        switch armed {
        case .shutter:
            let v = min(max(base * exp(Double(dx) / 130), 1.0 / 4000), 0.25)
            manager.shutterSeconds = v
            manager.applyExposure()
            feedback(dx: dx, key: log2(1 / v), step: 1.0 / 3.0)
            showHUD("SHUTTER", CameraMath.shutterLabel(v), CameraMath.shutterProgress(v))

        case .iso:
            let stops: [Double] = [100, 200, 400, 800, 1600]
            let index0 = stops.firstIndex(of: base) ?? 1
            let index = min(max(index0 + Int((dx / 26).rounded()), 0), stops.count - 1)
            let v = stops[index]
            manager.iso = v
            manager.applyExposure()
            feedback(dx: dx, key: Double(index), step: 1)
            showHUD("ISO", "\(Int(v))", Double(index) / Double(stops.count - 1))

        case .bias:
            let raw = base + Double(dx) / 50 * 0.3
            let v = min(max(CameraMath.quantize(raw, step: 0.3), -2), 2)
            manager.bias = v
            manager.applyExposure()
            feedback(dx: dx, key: v, step: 0.3)
            showHUD("EXPOSURE", CameraMath.evLabel(v), CameraMath.progress(v, in: -2...2))

        case .temperature:
            let raw = base + Double(dx) / 5 * 100
            let v = min(max(CameraMath.quantize(raw, step: 100), 3000), 8000)
            manager.temperature = v
            manager.applyWhiteBalance()
            feedback(dx: dx, key: v, step: 100)
            showHUD("TEMP", "\(Int(v))K", CameraMath.progress(v, in: 3000...8000))

        case .tint:
            let raw = base + Double(dx) / 4 * 10
            let v = min(max(CameraMath.quantize(raw, step: 10), -150), 150)
            manager.tint = v
            manager.applyWhiteBalance()
            feedback(dx: dx, key: v, step: 10)
            showHUD("TINT", "\(v >= 0 ? "+" : "")\(Int(v))", CameraMath.progress(v, in: -150...150))
        }
    }

    // MARK: 快门键上的模式切换

    /// 横拖超过 22pt 才算换模式，避免按快门时手抖误切
    private let shiftGate: CGFloat = 22
    /// 之后每 26pt 换一档
    private let shiftStep: CGFloat = 26

    private func handleShutterDrag(_ dx: CGFloat) {
        if !shiftArmed {
            guard !manager.isRecording, abs(dx) > shiftGate else { return }
            shiftArmed = true
            shiftStart = manager.mode
            shiftTarget = manager.mode
            Haptics.impact(.medium)
            showModeHUD(manager.mode)
            return
        }

        guard let start = shiftStart else { return }
        let target = start.cycled(steps: Int((dx / shiftStep).rounded()))
        guard target != shiftTarget else { return }
        shiftTarget = target
        Haptics.impact(.light)
        showModeHUD(target)
    }

    private func finishShutterDrag() {
        defer {
            shiftArmed = false
            shiftStart = nil
            shiftTarget = nil
        }

        if shiftArmed {
            if let target = shiftTarget, target != manager.mode {
                withAnimation(.easeInOut(duration: 0.15)) { manager.mode = target }
                Haptics.impact(.medium)
            }
            return
        }

        Haptics.impact(.heavy)
        if manager.mode == .video { manager.toggleRecording() } else { manager.capturePhoto() }
    }

    private func showModeHUD(_ mode: CameraMode) {
        let all = CameraMode.allCases
        let index = all.firstIndex(of: mode) ?? 0
        showHUD("MODE", mode.label,
                Double(index) / Double(max(all.count - 1, 1)))
    }

    /// 每帧最多给一次反馈：档位跳了就用「档」的力度，只划过了细牙就用「牙」的力度。
    /// 齿的密度对齐滚花画出来的 96 齿，所以手上和眼里是同一套齿。
    private func feedback(dx: CGFloat, key: Double, step: Double) {
        let bucket = (key / step).rounded()
        let tooth = (Double(dx) / toothPitch).rounded()

        // 落指第一帧只对位，不当作跳档，只轻咬一颗齿
        if lastBucket.isNaN {
            lastBucket = bucket
            lastTooth = tooth
            DetentFeedback.shared.fire(.tooth)
            return
        }

        if bucket != lastBucket {
            lastBucket = bucket
            lastTooth = tooth
            DetentFeedback.shared.fire(.detent)
        } else if tooth != lastTooth {
            lastTooth = tooth
            DetentFeedback.shared.fire(.tooth)
        }
    }

    /// 点选参数时先报一次当前值和它在轮盘上的位置
    private func announceArmed() {
        let v = value(of: armed)
        switch armed {
        case .shutter: showHUD("SHUTTER", CameraMath.shutterLabel(v), CameraMath.shutterProgress(v))
        case .iso: showHUD("ISO", "\(Int(v))", CameraMath.isoProgress(v))
        case .bias: showHUD("EXPOSURE", CameraMath.evLabel(v), CameraMath.progress(v, in: -2...2))
        case .temperature: showHUD("TEMP", "\(Int(v))K", CameraMath.progress(v, in: 3000...8000))
        case .tint: showHUD("TINT", "\(v >= 0 ? "+" : "")\(Int(v))", CameraMath.progress(v, in: -150...150))
        }
    }

    /// 无障碍微调：按 1/3 档进位
    private func nudgeShutter(_ direction: Int) {
        let step = pow(2.0, 1.0 / 3.0)
        let value = min(max(manager.shutterSeconds * (direction > 0 ? step : 1 / step),
                            1.0 / 4000), 0.25)
        manager.shutterSeconds = value
        manager.applyExposure()
        DetentFeedback.shared.fire(.detent)
        showHUD("SHUTTER", shutterLabel(value), CameraMath.shutterProgress(value))
    }

    private func showHUD(_ title: String, _ value: String, _ progress: Double) {
        hud = (title, value, progress)
        hudToken = UUID()
    }

    /// ISO 盘点一下切档
    private func cycleISO() {
        let steps: [Double] = [100, 200, 400, 800, 1600]
        let index = steps.firstIndex(of: manager.iso) ?? 1
        manager.iso = steps[(index + 1) % steps.count]
        manager.applyExposure()
        Haptics.impact(.light)
        showHUD("ISO", "\(Int(manager.iso))", CameraMath.isoProgress(manager.iso))
    }
}

/// 顶盖上的滚花盘：可点（切档 / 展开滑杆），T 盘还能横向拖动
struct TopDial: View {
    let tokens: ThemeTokens
    let caption: String
    var value: String? = nil
    var onTap: () -> Void
    var onRotate: ((CGFloat) -> Void)? = nil
    var onEndRotate: (() -> Void)? = nil

    @State private var angle: Double = 0
    @State private var dragging = false

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                KnurledRing(tokens: tokens, teeth: 64, inner: 0.66)
                    .frame(width: 54, height: 54)
                    .rotationEffect(.degrees(angle))
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 2)
                // 盘心数字窗
                Circle()
                    .fill(LinearGradient(colors: [tokens.faceTop, tokens.faceBottom],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 34, height: 34)
                    .overlay(Circle().strokeBorder(.black.opacity(0.3), lineWidth: 0.8))
                    .overlay(
                        Text(value ?? "")
                            .font(tokens.monoFont(10, .bold))
                            .foregroundColor(tokens.ink.opacity(0.85))
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .padding(.horizontal, 2)
                    )
                Rectangle()
                    .fill(tokens.accent)
                    .frame(width: 1.5, height: 8)
                    .offset(y: -11)
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard let onRotate else { return }
                        if abs(v.translation.width) > 3 { dragging = true }
                        guard dragging else { return }
                        onRotate(v.translation.width)
                        angle = Double(v.translation.width) * 0.8
                    }
                    .onEnded { _ in
                        if !dragging { Haptics.impact(.light); onTap() }
                        dragging = false
                        onEndRotate?()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { angle = 0 }
                    }
            )

            Silkscreen(text: caption, color: tokens.ink.opacity(0.55), size: 6, tracking: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value.map { "\(caption) \($0)" } ?? caption)
        .accessibilityAddTraits(.isButton)
    }
}
