import SwiftUI
import CoreImage

/// 自制胶卷：把调色、颗粒、暗角调成自己的卷，存下来反复用。
/// 存的是一组参数而不是位图，所以在任何底片上都能重算。
struct FilmEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var manager: CameraManager

    @State private var name: String = ""
    @State private var exposure: Double = 0
    @State private var contrast: Double = 1
    @State private var saturation: Double = 1
    @State private var temperature: Double = 0
    @State private var grain: Double = 0.3
    @State private var vignette: Double = 0.1
    @State private var preview: UIImage?

    private let context = CIContext()
    private var store: CustomFilmStore { CustomFilmStore.shared }

    private var draft: CustomFilm {
        CustomFilm(name: name.isEmpty ? defaultName : name,
                   grade: .init(exposure: exposure, contrast: contrast,
                                saturation: saturation, temperature: temperature),
                   grain: grain, vignette: vignette)
    }

    private var defaultName: String {
        "我的卷 \(CustomFilmStore.shared.films.count + 1)"
    }

    var body: some View {
        let t = ThemeStore.current
        ZStack {
            Color.black.opacity(0.95).ignoresSafeArea()
            VStack(spacing: 0) {
                header(t)
                Spacer(minLength: 0)
                previewArea(t)
                Spacer(minLength: 0)
                controls(t)
            }
        }
        .task { name = defaultName; refresh() }
    }

    private func header(_ t: ThemeTokens) -> some View {
        HStack(spacing: 10) {
            Silkscreen(text: "CUSTOM STOCK", color: .white.opacity(0.55), size: 7, tracking: 2.2)
            TextField("", text: $name)
                .textFieldStyle(.plain)
                .font(t.monoFont(12, .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: 160)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.08)))
            Spacer()
            Button("取消") { dismiss() }
                .font(t.monoFont(12, .medium))
                .foregroundColor(.white.opacity(0.6))
            Button {
                store.save(draft)
                manager.regradeCaptured(to: .custom(draft))
                Haptics.impact(.rigid)
                dismiss()
            } label: {
                Text("保存")
                    .font(t.monoFont(12, .bold))
                    .foregroundColor(t.accentGlow)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private func previewArea(_ t: ThemeTokens) -> some View {
        Group {
            if let preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .padding(.horizontal, 20)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(colors: [.gray.opacity(0.5), .black],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(height: 220)
                    .overlay(
                        Silkscreen(text: "拍一张再看效果", color: .white.opacity(0.5),
                                   size: 7, tracking: 1.6)
                    )
                    .padding(.horizontal, 20)
            }
        }
    }

    private func controls(_ t: ThemeTokens) -> some View {
        VStack(spacing: 10) {
            slider(t, "曝光", $exposure, -0.6...0.6, String(format: "%+.2f", exposure)) { refresh() }
            slider(t, "对比", $contrast, 0.7...1.5, String(format: "%.2f", contrast)) { refresh() }
            slider(t, "饱和", $saturation, 0.2...1.6, String(format: "%.2f", saturation)) { refresh() }
            slider(t, "色温", $temperature, -0.6...0.6, String(format: "%+.2f", temperature)) { refresh() }
            slider(t, "颗粒", $grain, 0...1, String(format: "%.0f%%", grain * 100)) { refresh() }
            slider(t, "暗角", $vignette, 0...1, String(format: "%.0f%%", vignette * 100)) { refresh() }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(AluminumFace(tokens: t))
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.32)).frame(height: 1)
        }
    }

    private func slider(_ t: ThemeTokens, _ title: String, _ value: Binding<Double>,
                        _ range: ClosedRange<Double>, _ readout: String,
                        onEditingChanged: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Silkscreen(text: title, color: .white.opacity(0.5), size: 6, tracking: 1.2)
                .frame(width: 34, alignment: .leading)
            Slider(value: value, in: range) { editing in
                if !editing { onEditingChanged() }
            }
            .tint(t.accent)
            Text(readout)
                .font(t.monoFont(9, .medium))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 48, alignment: .trailing)
        }
    }

    private func refresh() {
        guard let base = manager.capturedBase, let ci = CIImage(image: base) else { return }
        let out = draft.grade.asGrade
        var image = FilmFilter.applyGrade(ci, out)
        if grain > 0.01 {
            image = FilmFilter.applyGrain(image,
                                          settings: GrainSettings.make(iso: 400 * grain * 2,
                                                                       traits: RollTraits(seed: 1),
                                                                       seed: 1))
        }
        if vignette > 0.01, let f = CIFilter(name: "CIVignette") {
            f.setValue(image, forKey: kCIInputImageKey)
            f.setValue(vignette * 2.2, forKey: "inputIntensity")
            f.setValue(1.2, forKey: "inputRadius")
            image = f.outputImage ?? image
        }
        guard let cg = context.createCGImage(image, from: image.extent) else { return }
        preview = UIImage(cgImage: cg)
    }
}
