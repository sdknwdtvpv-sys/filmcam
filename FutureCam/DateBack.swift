import UIKit

/// 日期背印：老式胶卷机后背那块 LED 打出来的橙色日期，烧在画面右下角。
/// 显影完成后的成片才会有，所以它是「这张照片的一部分」，不是叠加层。
enum DateBack {

    /// 橙色 LED 感：主字 + 一圈柔光
    private static let amber = UIColor(red: 1.0, green: 0.47, blue: 0.10, alpha: 1.0)

    static func apply(to image: UIImage, date: Date = Date()) -> UIImage {
        let w = image.size.width
        let h = image.size.height
        guard w > 20, h > 20 else { return image }

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let text = String(format: "'%02d %02d %02d",
                          (parts.year ?? 2000) % 100,
                          parts.month ?? 1,
                          parts.day ?? 1) as NSString

        let fontSize = max(9, w * 0.034)
        let font = UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold)
        let spacing: CGFloat = fontSize * 0.18
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: amber,
            .kern: spacing
        ]
        let textSize = text.size(withAttributes: attrs)
        let margin = w * 0.045
        let point = CGPoint(x: w - textSize.width - margin, y: h - textSize.height - margin)

        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { ctx in
            image.draw(at: .zero)

            // 三层柔光叠出 LED 的晕
            let cg = ctx.cgContext
            cg.setShadow(offset: .zero, blur: fontSize * 0.85,
                         color: amber.withAlphaComponent(0.85).cgColor)
            text.draw(at: point, withAttributes: attrs)
            cg.setShadow(offset: .zero, blur: fontSize * 0.30,
                         color: amber.withAlphaComponent(0.95).cgColor)
            text.draw(at: point, withAttributes: attrs)
            cg.setShadow(offset: .zero, blur: 0, color: nil)
            text.draw(at: point, withAttributes: attrs)
        }
    }
}
