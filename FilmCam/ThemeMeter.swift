import SwiftUI

/// 方向二 · 测光台
///
/// 整屏是一块浅色仪器面板：顶部三格读数字段，下面一条可读的刻度尺（游标指当前 EV），
/// 参数不是滑杆而是「滚到某一路」的档位，快门是一块带斜纹的压板。
struct MeterCameraView: View {
    @EnvironmentObject var manager: CameraManager

    var body: some View {
        let t = ThemeStore.current

        ZStack {
            t.background.ignoresSafeArea()

            VStack(spacing: 0) {
                brandRow(t)
                readoutBand(t)
                evScale(t)
                Rectangle().fill(t.ink.opacity(0.5)).frame(height: 1)
                previewBlock(t)
                modeRow(t)
                ParamTuningPanel()
                toolsRow(t)
                platen(t)
            }
        }
    }

    // MARK: 品牌行

    private func brandRow(_ t: ThemeTokens) -> some View {
        HStack {
            Text("FILMCAM")
                .font(t.labelFont(12, .semibold))
                .tracking(3.4)
                .foregroundColor(t.ink)
            Text("测光台")
                .font(t.labelFont(9, .regular))
                .tracking(2)
                .foregroundColor(t.inkDim)
            Spacer()
            Text(manager.isRecording ? "REC" : "1080P · 30")
                .font(t.monoFont(9, .medium))
                .tracking(1)
                .foregroundColor(manager.isRecording ? t.recRed : t.inkDim)
        }
        .padding(.horizontal, t.inset)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    // MARK: 三格读数

    private func readoutBand(_ t: ThemeTokens) -> some View {
        let keys = visibleParams(manager)
        return HStack(spacing: 0) {
            ForEach(Array(keys.enumerated()), id: \.element) { index, key in
                if index > 0 {
                    Rectangle().fill(t.ink.opacity(0.35)).frame(width: 1, height: 44)
                }
                Button { manager.toggleParam(key) } label: {
                    VStack(alignment: .leading, spacing: -2) {
                        HStack(spacing: 4) {
                            Text(paramTitle(key))
                                .font(t.labelFont(9, .regular))
                                .tracking(1.6)
                                .foregroundColor(manager.activeParam == key ? t.accent : t.inkDim)
                            if manager.activeParam == key {
                                Rectangle().fill(t.accent).frame(width: 12, height: 1.5)
                            }
                        }
                        Text(paramValue(key, manager))
                            .font(t.displayFont(31, .regular))
                            .foregroundColor(manager.activeParam == key ? t.accent : t.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(paramTitle(key)) \(paramValue(key, manager))")
            }

            Button { toggleGroup() } label: {
                VStack(spacing: 3) {
                    Text("⇄").font(t.displayFont(14, .regular))
                    Text(manager.paramMode == .exposure ? "EV" : "WB")
                        .font(t.labelFont(7, .semibold))
                }
                .foregroundColor(t.accent)
                .frame(width: 34, height: 52)
                .overlay(alignment: .leading) {
                    Rectangle().fill(t.ink.opacity(0.35)).frame(width: 1, height: 44)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("切换参数分组")
        }
        .frame(height: 62)
        .overlay(alignment: .bottom) {
            Rectangle().fill(t.ink.opacity(0.35)).frame(height: 1)
        }
    }

    // MARK: 刻度尺（主视觉）

    private func evScale(_ t: ThemeTokens) -> some View {
        VStack(spacing: 2) {
            EvTickScale(value: manager.paramMode == .exposure ? manager.bias : (manager.tint / 150),
                        t: t)
                .frame(height: 24)
            HStack {
                ForEach(["-2", "-1", "0", "+1", "+2"], id: \.self) { label in
                    Text(label)
                        .font(t.monoFont(7, .medium))
                        .foregroundColor(t.inkDim)
                    if label != "+2" { Spacer(minLength: 0) }
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(.horizontal, t.inset)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    // MARK: 取景

    private func previewBlock(_ t: ThemeTokens) -> some View {
        PreviewSurface(showsScrim: false)
            .overlay(Rectangle().stroke(t.ink.opacity(0.75), lineWidth: 1))
            .overlay(alignment: .topLeading) { cropTick(t) }
            .overlay(alignment: .topTrailing) { cropTick(t).rotationEffect(.degrees(90)) }
            .overlay(alignment: .bottomTrailing) { cropTick(t).rotationEffect(.degrees(180)) }
            .overlay(alignment: .bottomLeading) { cropTick(t).rotationEffect(.degrees(270)) }
            .padding(.horizontal, t.inset)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .frame(maxHeight: .infinity)
    }

    private func cropTick(_ t: ThemeTokens) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Rectangle().fill(t.panel).frame(width: 12, height: 1.5)
            Rectangle().fill(t.panel).frame(width: 1.5, height: 12)
        }
        .padding(6)
    }

    // MARK: 模式

    private func modeRow(_ t: ThemeTokens) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(CameraMode.allCases.enumerated()), id: \.element) { index, mode in
                if index > 0 {
                    Rectangle().fill(t.ink.opacity(0.35)).frame(width: 1, height: 32)
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) { manager.mode = mode }
                } label: {
                    Text(mode.label)
                        .font(t.labelFont(12, .semibold))
                        .tracking(2)
                        .foregroundColor(manager.mode == mode ? t.panel : t.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(manager.mode == mode ? t.ink : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(t.ink.opacity(0.35)).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(t.ink.opacity(0.35)).frame(height: 1) }
    }

    // MARK: 小工具

    private func toolsRow(_ t: ThemeTokens) -> some View {
        HStack(spacing: 12) {
            Button { manager.showFilmSheet = true } label: {
                toolLabel("胶片 · \(manager.selectedPreset.label)", t)
            }
            Button { manager.showGrid.toggle() } label: {
                toolLabel("网格", t, active: manager.showGrid)
            }
            Button { manager.showSettingsSheet = true } label: {
                toolLabel("设置", t)
            }
            Spacer(minLength: 0)
            Button { manager.openAlbum() } label: { squareTool(t, filled: manager.albumItems.isEmpty == false) }
                .accessibilityLabel("打开相册")
            Button { manager.switchCamera() } label: {
                squareTool(t, filled: false, glyph: "arrow.triangle.2.circlepath")
                    .rotationEffect(.degrees(manager.isFrontCamera ? 180 : 0))
            }
            .disabled(manager.isRecording)
            .accessibilityLabel(manager.isFrontCamera ? "切换到后置摄像头" : "切换到前置摄像头")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, t.inset)
        .padding(.vertical, 7)
    }

    private func toolLabel(_ text: String, _ t: ThemeTokens, active: Bool = false) -> some View {
        Text(text)
            .font(t.labelFont(9.5, .semibold))
            .tracking(0.8)
            .foregroundColor(active ? t.panel : t.ink)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(active ? t.ink : Color.clear)
            .overlay(Rectangle().stroke(t.ink.opacity(0.35), lineWidth: 1))
            .contentShape(Rectangle())
    }

    private func squareTool(_ t: ThemeTokens, filled: Bool, glyph: String = "photo.on.rectangle") -> some View {
        ZStack {
            Rectangle().fill(t.elevated).frame(width: 34, height: 26)
            Rectangle().stroke(t.ink.opacity(0.4), lineWidth: 1).frame(width: 34, height: 26)
            Image(systemName: glyph)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(t.ink)
        }
        .contentShape(Rectangle())
    }

    // MARK: 压板快门

    private func platen(_ t: ThemeTokens) -> some View {
        Button { shoot() } label: {
            HStack(spacing: 0) {
                HazardStripes(color: t.panel.opacity(0.5))
                    .frame(width: 34)
                    .clipped()
                VStack(spacing: 0) {
                    Text(shutterVerb(manager))
                        .font(t.displayFont(25, .regular))
                        .foregroundColor(t.panel)
                    Text(shutterHint(manager))
                        .font(t.monoFont(7.5, .medium))
                        .tracking(2.2)
                        .foregroundColor(t.panel.opacity(0.65))
                }
                .frame(maxWidth: .infinity)
                HazardStripes(color: t.panel.opacity(0.5))
                    .frame(width: 34)
                    .clipped()
            }
            .frame(height: 66)
            .background(manager.isRecording ? t.recRed : t.ink)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(shutterVerb(manager))
        .padding(.horizontal, t.inset)
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

// MARK: - 刻度与斜纹

/// 带游标的刻度尺：越界时游标变红
struct EvTickScale: View {
    let value: Double
    let t: ThemeTokens

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let count = 41
            let clamped = min(max(value, -1), 1)
            let cx = width * CGFloat((clamped + 1) / 2)

            ZStack(alignment: .topLeading) {
                ForEach(0..<count, id: \.self) { i in
                    let major = i % 10 == 0
                    let mid = i % 5 == 0
                    Rectangle()
                        .fill(t.ink.opacity(major ? 0.8 : (mid ? 0.45 : 0.22)))
                        .frame(width: major ? 1.4 : 0.8, height: major ? 12 : (mid ? 8 : 5))
                        .position(x: width * CGFloat(i) / CGFloat(count - 1), y: 6)
                }

                Triangle()
                    .fill(abs(value) > 2 ? t.recRed : t.accent)
                    .frame(width: 8, height: 6)
                    .position(x: cx, y: 1)

                Rectangle()
                    .fill(abs(value) > 2 ? t.recRed : t.accent)
                    .frame(width: 1.6, height: 17)
                    .position(x: cx, y: 12)
            }
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// 斜纹（压板两端的安全区标记）
struct HazardStripes: View {
    var color: Color

    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 9
            var x = -size.height
            while x < size.width + size.height {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(path, with: .color(color), lineWidth: 3)
                x += step
            }
        }
    }
}
