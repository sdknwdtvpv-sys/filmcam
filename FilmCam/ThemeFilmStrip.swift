import SwiftUI

/// 方向三 · 胶片带
///
/// 整屏像一条拉出来的胶片：标题带 / 带齿孔的取景带 / 巨型帧计数带 / 操作带。
/// 帧计数器是主视觉，换胶片时整条带子侧滑。
struct FilmStripCameraView: View {
    @EnvironmentObject var manager: CameraManager

    var body: some View {
        let t = ThemeStore.current

        ZStack {
            t.background.ignoresSafeArea()

            VStack(spacing: 0) {
                titleBand(t)
                previewBand(t)
                counterBand(t)
                ParamTuningPanel()
                actionBand(t)
            }
        }
    }

    // MARK: 标题带

    private func titleBand(_ t: ThemeTokens) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text("FILMCAM")
                .font(t.labelFont(12, .semibold))
                .tracking(3)
                .foregroundColor(t.ink)

            Spacer(minLength: 4)

            HStack(spacing: 14) {
                ForEach(CameraMode.allCases) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { manager.mode = mode }
                    } label: {
                        VStack(spacing: 3) {
                            Text(mode.label)
                                .font(t.labelFont(11, manager.mode == mode ? .semibold : .regular))
                                .tracking(1.2)
                                .foregroundColor(manager.mode == mode ? t.ink : t.inkDim)
                            Rectangle()
                                .fill(manager.mode == mode ? t.accent : .clear)
                                .frame(width: 16, height: 1.5)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 4)

            HStack(spacing: 12) {
                Button { manager.showGrid.toggle() } label: {
                    Image(systemName: "grid")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(manager.showGrid ? t.accent : t.inkDim)
                }
                Button { manager.showSettingsSheet = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(t.inkDim)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, t.inset)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    // MARK: 取景带（两侧齿孔）

    private func previewBand(_ t: ThemeTokens) -> some View {
        HStack(spacing: 0) {
            SprocketEdge(tokens: t)
            PreviewSurface(showsScrim: true)
            SprocketEdge(tokens: t)
        }
        .background(t.panel)
        .overlay(alignment: .top) { Rectangle().fill(t.hairline).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(t.hairline).frame(height: 1) }
        .frame(maxHeight: .infinity)
    }

    // MARK: 计数带

    private func counterBand(_ t: ThemeTokens) -> some View {
        let digits = Array(String(format: "%03d", manager.frameCount))
        return HStack(alignment: .center, spacing: 14) {
            HStack(spacing: 3) {
                ForEach(Array(digits.enumerated()), id: \.offset) { _, ch in
                    Text(String(ch))
                        .font(t.displayFont(46, .regular))
                        .foregroundColor(t.ink)
                        .frame(width: 34, height: 54)
                        .background(t.panel)
                        .overlay(Rectangle().stroke(t.hairline, lineWidth: 1))
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("FRAMES")
                    .font(t.labelFont(8, .semibold))
                    .tracking(2)
                    .foregroundColor(t.inkDim)

                Button { manager.showFilmSheet = true } label: {
                    HStack(spacing: 4) {
                        Text(manager.selectedPreset.label)
                            .font(t.labelFont(13, .semibold))
                            .foregroundColor(t.ink)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(t.accent)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text("ISO \(Int(manager.iso)) · \(shutterLabel(manager.shutterSeconds)) · \(evLabel(manager.bias))")
                    .font(t.monoFont(9, .regular))
                    .foregroundColor(t.inkDim)
            }

            Spacer(minLength: 0)

            // 右侧：参数分组切换 + 变焦读数
            VStack(alignment: .trailing, spacing: 6) {
                Button {
                    manager.setParamMode(manager.paramMode == .exposure ? .whiteBalance : .exposure)
                } label: {
                    Text(manager.paramMode == .exposure ? "曝光组" : "白平衡组")
                        .font(t.labelFont(9, .semibold))
                        .tracking(0.6)
                        .foregroundColor(t.accent)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .overlay(Capsule().stroke(t.accent.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Text(manager.zoomFactor > 1.02 ? String(format: "%.1f×", manager.zoomFactor) : "1.0×")
                    .font(t.monoFont(10, .medium))
                    .foregroundColor(t.inkDim)

                if manager.isFrontCamera {
                    Text("前置")
                        .font(t.labelFont(8, .semibold))
                        .foregroundColor(t.accent)
                }
            }
        }
        .padding(.horizontal, t.inset)
        .padding(.vertical, 12)
    }

    // MARK: 操作带

    private func actionBand(_ t: ThemeTokens) -> some View {
        HStack {
            Button { manager.openAlbum() } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: t.radius)
                        .fill(t.panel)
                        .frame(width: 54, height: 54)
                    RoundedRectangle(cornerRadius: t.radius)
                        .stroke(t.hairline, lineWidth: 1)
                        .frame(width: 54, height: 54)
                    if let latest = manager.albumItems.first {
                        MediaThumbnail(item: latest, maxPixel: 200, fill: true)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: max(t.radius - 4, 3)))
                    } else {
                        Image(systemName: "rectangle.on.rectangle")
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(t.inkDim)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开相册")

            Spacer(minLength: 0)

            FilmStripShutter(tokens: t, mode: manager.mode, isRecording: manager.isRecording) { shoot() }
                .accessibilityLabel(shutterVerb(manager))

            Spacer(minLength: 0)

            Button { manager.switchCamera() } label: {
                ZStack {
                    Circle().stroke(t.hairline, lineWidth: 1).frame(width: 46, height: 46)
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(manager.isRecording ? t.inkDim.opacity(0.4) : t.ink)
                        .rotationEffect(.degrees(manager.isFrontCamera ? 180 : 0))
                        .animation(.easeInOut(duration: 0.28), value: manager.isFrontCamera)
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(manager.isRecording)
            .accessibilityLabel(manager.isFrontCamera ? "切换到后置摄像头" : "切换到前置摄像头")
        }
        .padding(.horizontal, t.inset)
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    private func shoot() {
        Haptics.impact(.medium)
        if manager.mode == .video { manager.toggleRecording() } else { manager.capturePhoto() }
    }
}

// MARK: - 齿孔边

struct SprocketEdge: View {
    let tokens: ThemeTokens

    var body: some View {
        GeometryReader { geo in
            let slot: CGFloat = 22
            let count = max(Int(geo.size.height / slot), 1)
            VStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(tokens.background)
                        .frame(width: 9, height: 13)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 18)
        .background(tokens.panel)
        .overlay(alignment: .trailing) {
            Rectangle().fill(tokens.hairline).frame(width: 1)
        }
    }
}

// MARK: - 机械快门

struct FilmStripShutter: View {
    let tokens: ThemeTokens
    let mode: CameraMode
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(tokens.hairline, lineWidth: 1)
                    .frame(width: 84, height: 84)
                Circle()
                    .stroke(tokens.accent.opacity(0.55), lineWidth: 1)
                    .frame(width: 76, height: 76)
                Circle()
                    .fill(isRecording && mode == .video ? tokens.recRed : tokens.ink)
                    .frame(width: 64, height: 64)
                if mode == .video && isRecording {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(tokens.panel)
                        .frame(width: 18, height: 18)
                } else {
                    Circle()
                        .fill(tokens.accent)
                        .frame(width: 10, height: 10)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
