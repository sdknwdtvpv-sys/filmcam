import SwiftUI
import UIKit

// MARK: - 机身纹理

extension TextureFactory {
    /// 蒙皮：深色底 + 斜向细纹 + 均匀网点（确定性，不用随机点）
    static func leather() -> UIImage { cached("leather") {
        let size = CGSize(width: 48, height: 48)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor(white: 0.09, alpha: 1).cgColor)
            cg.fill(CGRect(origin: .zero, size: size))

            cg.setStrokeColor(UIColor(white: 1, alpha: 0.02).cgColor)
            cg.setLineWidth(1)
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                cg.move(to: CGPoint(x: x, y: size.height))
                cg.addLine(to: CGPoint(x: x + size.height, y: 0))
                cg.strokePath()
                x += 3
            }

            cg.setFillColor(UIColor(white: 0, alpha: 0.13).cgColor)
            var gy: CGFloat = 0
            while gy < size.height {
                var gx: CGFloat = 0
                while gx < size.width {
                    cg.fill(CGRect(x: gx, y: gy, width: 1, height: 1))
                    gx += 3
                }
                gy += 3
            }
        }
    } }
}

/// 蒙皮纹理铺满
struct LeatherPanel: View {
    var body: some View {
        Image(uiImage: TextureFactory.leather())
            .resizable(resizingMode: .tile)
    }
}

// MARK: - 器件构件

/// 嵌入式 LCD：厚边框 + 玻璃反光 + 内阴影
struct LCDWindow<Content: View>: View {
    let tokens: ThemeTokens
    var bezel: CGFloat = 6
    var radius: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .overlay(alignment: .topLeading) {
                LinearGradient(colors: [.white.opacity(0.10), .clear],
                               startPoint: .topLeading, endPoint: .center)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius - 2, style: .continuous))
            .padding(bezel)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x1A1C1E), Color(hex: 0x0B0C0D)],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.black.opacity(0.9), .white.opacity(0.22)],
                                                 startPoint: .top, endPoint: .bottom),
                                  lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.45), radius: 3, y: 2)
    }
}

/// 丝印文字：浅色小字，略透，像印在壳上
struct Silkscreen: View {
    let text: String
    var color: Color = .white
    var size: CGFloat = 7
    var tracking: CGFloat = 1.2
    var font: (CGFloat, Font.Weight) -> Font = { s, _ in
        .custom("Futura-Medium", size: s)
    }

    var body: some View {
        Text(text)
            .font(font(size, .medium))
            .tracking(tracking)
            .foregroundColor(color.opacity(0.82))
    }
}

/// 机身侧边高光：让整块屏幕看起来有厚度
struct DeviceEdge: View {
    var radius: CGFloat = 0
    var intensity: Double = 1

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(
                LinearGradient(colors: [.white.opacity(0.55 * intensity), .clear,
                                        .clear, .black.opacity(0.45 * intensity)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 2)
            .allowsHitTesting(false)
    }
}

/// 丝印标签键：键下方一行小字，按下有行程
struct LabeledKey<Content: View>: View {
    let tokens: ThemeTokens
    let caption: String
    var captionColor: Color?
    var radius: CGFloat = 4
    var action: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 3) {
            PhysicalButton(tokens: tokens, radius: radius, action: action) {
                content()
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .contentShape(Rectangle())
            }
            Silkscreen(text: caption, color: captionColor ?? tokens.inkDim, size: 6, tracking: 0.8)
        }
    }
}

/// 调参时浮在取景画面上的读数：大字 + 刻度条，1.2 秒后淡出
struct ParameterHUD: View {
    let title: String
    let value: String
    let progress: Double
    let tokens: ThemeTokens
    /// 大白话解释，只在对小白有用的参数上出现
    var hint: String? = nil

    var body: some View {
        VStack(spacing: 9) {
            Text(title)
                .font(tokens.monoFont(9, .bold))
                .tracking(2.6)
                .foregroundColor(.white.opacity(0.55))
            Text(value)
                .font(tokens.displayFont(42, .medium))
                .monospacedDigit()
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.55), radius: 6)
            if let hint {
                Text(hint)
                    .font(tokens.labelFont(11, .medium))
                    .foregroundColor(.white.opacity(0.72))
                    .padding(.top, -4)
            }
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.16)).frame(width: 150, height: 3)
                Capsule().fill(tokens.accent)
                    .frame(width: max(4, 150 * min(max(progress, 0), 1)), height: 3)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.52))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        )
    }
}
