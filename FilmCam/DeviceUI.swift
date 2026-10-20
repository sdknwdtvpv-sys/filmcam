import SwiftUI
import UIKit

// MARK: - 器件纹理

extension TextureFactory {
    /// 蒙皮：深色底 + 斜向细纹 + 均匀网点（确定性，不用随机点）
    static func leatherTile() -> UIImage { cached("leather") {
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

    /// 电路板：走线 + 过孔 + 芯片
    static func pcbTile() -> UIImage { cached("pcb") {
        let size = CGSize(width: 140, height: 140)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor(red: 0.05, green: 0.17, blue: 0.12, alpha: 1).cgColor)
            cg.fill(CGRect(origin: .zero, size: size))

            var seed: UInt64 = 0x9E3779B97F4A7C15
            func next() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double((seed >> 33) & 0xFFFF) / 65535.0
            }

            cg.setStrokeColor(UIColor(red: 0.35, green: 0.85, blue: 0.58, alpha: 0.85).cgColor)
            cg.setLineWidth(1)
            for _ in 0..<26 {
                var x = next() * size.width
                var y = next() * size.height
                cg.move(to: CGPoint(x: x, y: y))
                for _ in 0..<3 {
                    if next() > 0.5 { x += (next() - 0.5) * 70 } else { y += (next() - 0.5) * 70 }
                    x = min(max(x, 2), size.width - 2)
                    y = min(max(y, 2), size.height - 2)
                    cg.addLine(to: CGPoint(x: x, y: y))
                }
                cg.strokePath()
            }

            for _ in 0..<40 {
                let c = CGPoint(x: next() * size.width, y: next() * size.height)
                cg.setFillColor(UIColor(red: 0.68, green: 0.86, blue: 0.62, alpha: 0.9).cgColor)
                cg.fillEllipse(in: CGRect(x: c.x, y: c.y, width: 3, height: 3))
                cg.setFillColor(UIColor(red: 0.04, green: 0.10, blue: 0.07, alpha: 1).cgColor)
                cg.fillEllipse(in: CGRect(x: c.x + 0.9, y: c.y + 0.9, width: 1.4, height: 1.4))
            }

            for _ in 0..<3 {
                let w = 14 + next() * 20
                let h = 8 + next() * 10
                let rect = CGRect(x: next() * (size.width - w), y: next() * (size.height - h),
                                  width: w, height: h)
                cg.setFillColor(UIColor(white: 0.05, alpha: 1).cgColor)
                cg.fill(rect)
                cg.setStrokeColor(UIColor(white: 0.5, alpha: 0.5).cgColor)
                cg.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
            }
        }
    } }

/// 蒙皮纹理铺满（深色皮革）
struct LeatherPanel: View {
    var body: some View {
        Image(uiImage: TextureFactory.leatherTile())
            .resizable(resizingMode: .tile)
    }
}

}

/// 蒙皮纹理铺满（深色皮革）
struct LeatherPanel: View {
    var body: some View {
        Image(uiImage: TextureFactory.leatherTile())
            .resizable(resizingMode: .tile)
    }
}

/// 电路板纹理铺满
struct PcbBackdrop: View {
    var body: some View {
        Image(uiImage: TextureFactory.pcbTile())
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

/// 丝印文字：白/浅灰小字，略透，像印在塑料壳上
struct Silkscreen: View {
    let text: String
    var color: Color = .white
    var size: CGFloat = 7
    var tracking: CGFloat = 1.2
    var font: (CGFloat, Font.Weight) -> Font = { s, w in
        .custom("Futura-Medium", size: s)
    }

    var body: some View {
        Text(text)
            .font(font(size, .medium))
            .tracking(tracking)
            .foregroundColor(color.opacity(0.82))
    }
}

/// 散热槽
struct VentSlots: View {
    var count: Int = 5
    var color: Color
    var slotWidth: CGFloat = 3
    var slotHeight: CGFloat = 22

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<count, id: \.self) { _ in
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.85), color.opacity(0.25)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: slotWidth, height: slotHeight)
                    .overlay(Capsule().stroke(.black.opacity(0.45), lineWidth: 0.5))
            }
        }
    }
}

/// 内六角螺丝
struct HexScrew: View {
    var size: CGFloat = 10

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [.white.opacity(0.42), .black.opacity(0.55)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Hexagon()
                .fill(.black.opacity(0.62))
                .frame(width: size * 0.52, height: size * 0.52)
            Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.6)
        }
        .frame(width: size, height: size)
    }
}

struct Hexagon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        for i in 0..<6 {
            let a = Double(i) / 6 * 2 * .pi - .pi / 2
            let pt = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
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

/// 丝印标签键：键上方一行小字，按下有行程
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
