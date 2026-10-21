import SwiftUI
import UIKit

/// 分享卡片：照片下面压一条铝色信息栏。
/// 铝面 + 丝印 + 红点，和机身同一套语言，不加水印也不挡画面。
enum ShareCard {

    /// 版式：经典（照片 + 铝条）/ 胶卷（上下齿孔）/ 并排（两张，练前练后）
    enum Variant: String, CaseIterable, Identifiable {
        case classic, strip, diptych
        var id: String { rawValue }
        var title: String {
            switch self {
            case .classic: return "经典"
            case .strip:   return "胶卷"
            case .diptych: return "并排"
            }
        }
    }

    /// 统一入口：按版式出图。并排版式需要第二张，没有就自动退回经典
    static func render(_ image: UIImage,
                       variant: Variant,
                       second: UIImage? = nil,
                       film: String,
                       roll: String,
                       frame: String,
                       date: Date) -> UIImage {
        switch variant {
        case .classic:
            return render(image, film: film, roll: roll, frame: frame, date: date)
        case .strip:
            return renderStrip(image, film: film, roll: roll, frame: frame, date: date)
        case .diptych:
            guard let second else {
                return render(image, film: film, roll: roll, frame: frame, date: date)
            }
            return renderDiptych(image, second: second, film: film, roll: roll, frame: frame, date: date)
        }
    }

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

    // MARK: 版式

    /// 胶卷版式：上下齿孔 + 边缘字，像一段剪下来的底片
    static func renderStrip(_ image: UIImage,
                            film: String, roll: String, frame: String, date: Date) -> UIImage {
        let w = image.size.width
        guard w > 10 else { return image }
        let hole = max(14, w * 0.032)          // 齿孔条高度
        let foot = max(46, w * 0.10)           // 底部信息带
        let size = CGSize(width: w, height: image.size.height + hole * 2 + foot)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            // 底片基材：接近黑，但比纯黑暖一点
            cg.setFillColor(UIColor(red: 0.06, green: 0.055, blue: 0.05, alpha: 1).cgColor)
            cg.fill(CGRect(origin: .zero, size: size))

            image.draw(in: CGRect(x: 0, y: hole, width: w, height: image.size.height))

            // 上下齿孔
            let spacing = w * 0.075
            let holeW = spacing * 0.54
            var x = spacing * 0.4
            while x < w {
                let r = CGRect(x: x, y: hole * 0.22, width: holeW, height: hole * 0.56)
                cg.setFillColor(UIColor(white: 0.93, alpha: 0.92).cgColor)
                cg.addPath(UIBezierPath(roundedRect: r, cornerRadius: holeW * 0.18).cgPath)
                cg.fillPath()
                let r2 = r.offsetBy(dx: 0, dy: image.size.height + hole * 0.44)
                cg.addPath(UIBezierPath(roundedRect: r2, cornerRadius: holeW * 0.18).cgPath)
                cg.fillPath()
                x += spacing
            }

            // 底部信息：左胶卷名，右卷号帧号
            let mono = { (sz: CGFloat, wt: UIFont.Weight) in
                UIFont.monospacedSystemFont(ofSize: sz, weight: wt)
            }
            let light = UIColor(white: 0.96, alpha: 0.92)
            let dim = UIColor(white: 0.96, alpha: 0.45)
            let pad = w * 0.05
            let baseY = image.size.height + hole * 1.25
            (film as NSString).draw(at: CGPoint(x: pad, y: baseY), withAttributes: [
                .font: mono(w * 0.038, .semibold), .foregroundColor: light, .kern: w * 0.002
            ])
            let formatter = DateFormatter()
            formatter.dateFormat = "yy.MM.dd"
            let right = "\(roll)  \(frame)  \(formatter.string(from: date))" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: mono(w * 0.028, .regular), .foregroundColor: dim
            ]
            let rw = right.size(withAttributes: attrs).width
            right.draw(at: CGPoint(x: w - pad - rw, y: baseY + w * 0.006), withAttributes: attrs)
        }
    }

    /// 并排版式：两张并排（练前 / 练后），下面一条信息带
    static func renderDiptych(_ a: UIImage, second b: UIImage,
                              film: String, roll: String, frame: String, date: Date) -> UIImage {
        let totalW = max(a.size.width, b.size.width)
        guard totalW > 10 else { return a }
        let gap = max(6, totalW * 0.012)
        let colW = (totalW - gap) / 2
        // 统一高度：按第一张的比例算，第二张裁切填充
        let colH = a.size.height * (colW / a.size.width)
        let foot = max(56, totalW * 0.10)
        let size = CGSize(width: totalW, height: colH + foot)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            UIColor.white.setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            func drawFilled(_ img: UIImage, in rect: CGRect) {
                let scale = max(rect.width / img.size.width, rect.height / img.size.height)
                let w = img.size.width * scale, h = img.size.height * scale
                let r = CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
                cg.saveGState()
                cg.clip(to: rect)
                img.draw(in: r)
                cg.restoreGState()
            }
            drawFilled(a, in: CGRect(x: 0, y: 0, width: colW, height: colH))
            drawFilled(b, in: CGRect(x: colW + gap, y: 0, width: colW, height: colH))

            // 缝：一条细白线
            cg.setFillColor(UIColor.white.cgColor)
            cg.fill(CGRect(x: colW, y: 0, width: gap, height: colH))

            // 信息带
            let bar = CGRect(x: 0, y: colH, width: totalW, height: foot)
            cg.setFillColor(UIColor(white: 0.97, alpha: 1).cgColor)
            cg.fill(bar)
            cg.setFillColor(UIColor(white: 0.06, alpha: 0.10).cgColor)
            cg.fill(CGRect(x: 0, y: colH, width: totalW, height: 0.8))

            let mono = { (sz: CGFloat, wt: UIFont.Weight) in
                UIFont.monospacedSystemFont(ofSize: sz, weight: wt)
            }
            let ink = UIColor(white: 0.10, alpha: 1)
            let dim = UIColor(white: 0.10, alpha: 0.5)
            let pad = totalW * 0.05
            (film as NSString).draw(at: CGPoint(x: pad, y: colH + foot * 0.16), withAttributes: [
                .font: mono(totalW * 0.036, .semibold), .foregroundColor: ink, .kern: totalW * 0.002
            ])
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy.MM.dd"
            let sub = "\(roll) · \(frame) · \(formatter.string(from: date))" as NSString
            sub.draw(at: CGPoint(x: pad, y: colH + foot * 0.58), withAttributes: [
                .font: mono(totalW * 0.024, .regular), .foregroundColor: dim
            ])
            // 右侧红点
            let dot = max(4, totalW * 0.012)
            cg.setFillColor(UIColor(red: 0.75, green: 0.22, blue: 0.17, alpha: 1).cgColor)
            cg.fillEllipse(in: CGRect(x: totalW - pad - dot * 2, y: colH + foot * 0.42,
                                      width: dot * 2, height: dot * 2))
        }
    }
}

/// 分享面板：可分享成片卡，也可分享原图
struct ShareCardSheet: View {
    let item: AlbumItem
    let image: UIImage
    /// 并排版式的第二张（同卷的上一张），没有就不提供并排
    var secondImage: UIImage? = nil
    let film: String
    let rollText: String
    let frameText: String

    @Environment(\.dismiss) private var dismiss
    @State private var card: UIImage?
    @State private var shareItems: [Any]?
    @State private var variant: ShareCard.Variant = .classic

    private var availableVariants: [ShareCard.Variant] {
        secondImage == nil ? [.classic, .strip] : ShareCard.Variant.allCases
    }

    var body: some View {
        let t = ThemeStore.current
        ZStack {
            Color.black.opacity(0.94).ignoresSafeArea()
            VStack(spacing: 18) {
                Silkscreen(text: "SHARE", color: .white.opacity(0.55), size: 7, tracking: 2.4)
                    .padding(.top, 18)

                // 版式切换：经典 / 胶卷 / 并排（没有第二张时并排退化为经典）
                HStack(spacing: 6) {
                    ForEach(availableVariants) { v in
                        let active = variant == v
                        Button {
                            variant = v
                            Haptics.impact(.light)
                        } label: {
                            Text(v.title)
                                .font(t.monoFont(11, active ? .bold : .medium))
                                .foregroundColor(active ? .black : .white.opacity(0.7))
                                .padding(.horizontal, 14)
                                .frame(height: 30)
                                .background(Capsule().fill(active ? t.accentGlow : Color.white.opacity(0.10)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)

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
                        // 版式切换：经典 / 胶卷 / 并排（没有第二张时并排退化为经典）
                HStack(spacing: 6) {
                    ForEach(availableVariants) { v in
                        let active = variant == v
                        Button {
                            variant = v
                            Haptics.impact(.light)
                        } label: {
                            Text(v.title)
                                .font(t.monoFont(11, active ? .bold : .medium))
                                .foregroundColor(active ? .black : .white.opacity(0.7))
                                .padding(.horizontal, 14)
                                .frame(height: 30)
                                .background(Capsule().fill(active ? t.accentGlow : Color.white.opacity(0.10)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)

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
        .task(id: variant) {
            card = nil
            let v = variant
            let img = image
            let second = secondImage
            let rendered = await Task.detached(priority: .userInitiated) {
                ShareCard.render(img, variant: v, second: second,
                                 film: film, roll: rollText, frame: frameText, date: item.createdAt)
            }.value
            card = rendered
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
