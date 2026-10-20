import SwiftUI
import UIKit

/// 分享卡片：照片下面压一条铝色信息栏。
/// 铝面 + 丝印 + 红点，和机身同一套语言，不加水印也不挡画面。
enum ShareCard {

    static func render(_ image: UIImage,
                       film: String,
                       roll: String,
                       frame: String,
                       date: Date) -> UIImage {
        let w = image.size.width
        guard w > 10 else { return image }
        let barH = max(56, w * 0.135)
        let size = CGSize(width: w, height: image.size.height + barH)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            // 照片
            image.draw(in: CGRect(x: 0, y: 0, width: w, height: image.size.height))

            // 铝面信息栏
            let bar = CGRect(x: 0, y: image.size.height, width: w, height: barH)
            let colors = [UIColor(red: 0.93, green: 0.94, blue: 0.95, alpha: 1).cgColor,
                          UIColor(red: 0.69, green: 0.71, blue: 0.73, alpha: 1).cgColor]
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: colors as CFArray, locations: [0, 1]) {
                cg.saveGState()
                cg.clip(to: bar)
                cg.drawLinearGradient(g, start: CGPoint(x: 0, y: bar.minY),
                                      end: CGPoint(x: 0, y: bar.maxY), options: [])
                // 极细拉丝
                var y = bar.minY
                var seed: UInt64 = 0x9E3779B97F4A7C15
                while y < bar.maxY {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    let v = Double((seed >> 33) & 0xFFFF) / 65535.0
                    cg.setFillColor(UIColor(white: v > 0.5 ? 1 : 0, alpha: 0.04 + 0.05 * v).cgColor)
                    cg.fill(CGRect(x: 0, y: y, width: w, height: 1))
                    y += 1.5
                }
                cg.restoreGState()
            }
            // 顶边高光
            cg.setFillColor(UIColor(white: 1, alpha: 0.7).cgColor)
            cg.fill(CGRect(x: 0, y: bar.minY, width: w, height: 1.5))

            // 文字
            let mono = { (size: CGFloat, weight: UIFont.Weight) in
                UIFont.monospacedSystemFont(ofSize: size, weight: weight)
            }
            let ink = UIColor(white: 0.11, alpha: 1)
            let dim = UIColor(white: 0.11, alpha: 0.52)

            let pad = w * 0.05
            let titleY = bar.minY + barH * 0.30
            (film as NSString).draw(at: CGPoint(x: pad, y: titleY), withAttributes: [
                .font: mono(w * 0.042, .semibold), .foregroundColor: ink,
                .kern: w * 0.002
            ])

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy.MM.dd"
            let sub = "\(roll) · \(frame) · \(formatter.string(from: date))" as NSString
            sub.draw(at: CGPoint(x: pad, y: bar.minY + barH * 0.60), withAttributes: [
                .font: mono(w * 0.028, .regular), .foregroundColor: dim,
                .kern: w * 0.0012
            ])

            // 右侧红点
            let dot = max(5, w * 0.014)
            let cx = w - pad - dot
            cg.setFillColor(UIColor(red: 0.75, green: 0.22, blue: 0.17, alpha: 1).cgColor)
            cg.fillEllipse(in: CGRect(x: cx, y: bar.midY - dot, width: dot * 2, height: dot * 2))
        }
    }
}

/// 分享面板：可分享成片卡，也可分享原图
struct ShareCardSheet: View {
    let item: AlbumItem
    let image: UIImage
    let film: String
    let rollText: String
    let frameText: String

    @Environment(\.dismiss) private var dismiss
    @State private var card: UIImage?
    @State private var shareItems: [Any]?

    var body: some View {
        let t = ThemeStore.current
        ZStack {
            Color.black.opacity(0.94).ignoresSafeArea()
            VStack(spacing: 18) {
                Silkscreen(text: "SHARE", color: .white.opacity(0.55), size: 7, tracking: 2.4)
                    .padding(.top, 18)

                if let card {
                    Image(uiImage: card)
                        .resizable()
                        .scaledToFit()
                        .padding(.horizontal, 18)
                        .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
                } else {
                    ProgressView().tint(.white)
                }

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    Button {
                        dismiss()
                    } label: {
                        Text("取消")
                            .font(t.monoFont(12, .medium))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.07)))
                    }
                    .buttonStyle(.plain)

                    Button {
                        shareItems = [item.url]
                    } label: {
                        Text("原图")
                            .font(t.monoFont(12, .semibold))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)

                    Button {
                        if let card { shareItems = [card] }
                    } label: {
                        Text("卡片")
                            .font(t.monoFont(12, .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(RoundedRectangle(cornerRadius: 7).fill(t.accent))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
        }
        .task {
            guard card == nil else { return }
            card = ShareCard.render(image, film: film, roll: rollText, frame: frameText, date: item.createdAt)
        }
        .sheet(item: Binding(get: { shareItems.map(SharePayload.init) },
                             set: { if $0 == nil { shareItems = nil } })) { payload in
            ShareSheet(items: payload.items)
        }
    }
}

private struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
    init(_ items: [Any]) { self.items = items }
}
