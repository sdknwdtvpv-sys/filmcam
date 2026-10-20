import SwiftUI
import CoreImage
import UIKit

/// 冲印：拍完之后再修一次画幅。
/// 裁剪、旋转、拉直都是真实像素变换，保存后覆盖应用内相册的那一张。
struct DevelopView: View {
    let item: AlbumItem
    let onDone: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var original: UIImage?
    @State private var preview: UIImage?
    @State private var quarter: Int = 0
    @State private var straighten: Double = 0
    @State private var ratio: CropRatio = .original
    @State private var saving = false

    private let context = CIContext()

    enum CropRatio: String, CaseIterable, Identifiable {
        case original, square, portrait, wide
        var id: String { rawValue }
        var label: String {
            switch self {
            case .original: return "原图"
            case .square: return "1:1"
            case .portrait: return "4:5"
            case .wide: return "16:9"
            }
        }
        var value: CGFloat? {
            switch self {
            case .original: return nil
            case .square: return 1
            case .portrait: return 4.0 / 5.0
            case .wide: return 16.0 / 9.0
            }
        }
    }

    var body: some View {
        let t = ThemeStore.current
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 0) {
                header(t)
                Spacer(minLength: 0)
                if let preview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFit()
                        .padding(.horizontal, 16)
                } else {
                    ProgressView().tint(.white)
                }
                Spacer(minLength: 0)
                controls(t)
            }
        }
        .task { load() }
    }

    private func header(_ t: ThemeTokens) -> some View {
        HStack(spacing: 8) {
            Silkscreen(text: "PRINT", color: .white.opacity(0.6), size: 7, tracking: 2.4)
            Spacer()
            Button("取消") { dismiss() }
                .font(t.monoFont(12, .medium))
                .foregroundColor(.white.opacity(0.65))
            Button {
                save()
            } label: {
                Text(saving ? "冲印中…" : "完成")
                    .font(t.monoFont(12, .bold))
                    .foregroundColor(saving ? .white.opacity(0.4) : t.accentGlow)
            }
            .disabled(saving || preview == nil)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private func controls(_ t: ThemeTokens) -> some View {
        VStack(spacing: 14) {
            // 比例
            HStack(spacing: 8) {
                ForEach(CropRatio.allCases) { r in
                    Button {
                        ratio = r
                        recompute()
                        Haptics.impact(.light)
                    } label: {
                        Text(r.label)
                            .font(t.monoFont(10, .semibold))
                            .foregroundColor(ratio == r ? .white : .white.opacity(0.5))
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(ratio == r ? t.accent.opacity(0.28) : .white.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(ratio == r ? t.accent : .white.opacity(0.12), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                Button {
                    quarter = (quarter + 1) % 4
                    recompute()
                    Haptics.impact(.light)
                } label: {
                    Image(systemName: "rotate.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 34, height: 28)
                        .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("旋转 90 度")
            }

            // 拉直
            HStack(spacing: 10) {
                Silkscreen(text: "拉直", color: .white.opacity(0.5), size: 6, tracking: 1.4)
                Slider(value: $straighten, in: -12...12, step: 0.5) { editing in
                    if !editing {
                        recompute()
                        Haptics.impact(.light)
                    }
                }
                .tint(t.accent)
                Text(String(format: "%+.1f°", straighten))
                    .font(t.monoFont(9, .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 42, alignment: .trailing)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(AluminumFace(tokens: t))
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.35)).frame(height: 1)
        }
    }

    // MARK: - 渲染

    private func load() {
        guard original == nil else { return }
        original = UIImage(contentsOfFile: item.url.path)
        preview = original
    }

    private func recompute() {
        guard let original else { return }
        preview = PhotoDevelop.render(original,
                                      quarterTurns: quarter,
                                      straightenDegrees: straighten,
                                      aspect: ratio.value,
                                      context: context) ?? original
    }

    private func save() {
        guard let original, !saving else { return }
        saving = true
        let rendered = PhotoDevelop.render(original,
                                           quarterTurns: quarter,
                                           straightenDegrees: straighten,
                                           aspect: ratio.value,
                                           context: context) ?? original
        let meta = PhotoEncoding.metadata(of: item.url)
        guard let data = PhotoEncoding.jpeg(rendered, metadata: meta) else {
            saving = false
            return
        }
        AlbumStore.overwrite(item, jpeg: data)
        saving = false
        onDone(rendered)
        dismiss()
    }
}

/// 真实的像素级画幅变换
enum PhotoDevelop {
    static func render(_ image: UIImage, quarterTurns: Int, straightenDegrees: Double,
                       aspect: CGFloat?, context: CIContext) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        var ci = CIImage(cgImage: cg)

        let angle = Double(quarterTurns) * .pi / 2 + straightenDegrees * .pi / 180
        if abs(angle) > 0.0001 {
            // 绕中心旋转，再把扩大的画布收回正坐标
            let center = CGPoint(x: ci.extent.midX, y: ci.extent.midY)
            let t = CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: CGFloat(angle))
                .translatedBy(x: -center.x, y: -center.y)
            ci = ci.transformed(by: t)
            let e = ci.extent
            ci = ci.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
        }

        if let aspect {
            let e = ci.extent
            var w = e.width, h = e.height
            if w / h > aspect { w = h * aspect } else { h = w / aspect }
            let rect = CGRect(x: e.midX - w / 2, y: e.midY - h / 2, width: w, height: h)
            ci = ci.cropped(to: rect)
                .transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        }

        guard let out = context.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: out)
    }
}
