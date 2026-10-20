import SwiftUI
import UIKit

// MARK: - 拉丝铝纹理

/// 纹理只生成一次，之后按 pt 平铺 —— 每帧用 Canvas 重画满屏细纹会掉帧。
enum TextureFactory {

    nonisolated(unsafe) private static var cache: [String: UIImage] = [:]

    static func cached(_ key: String, _ make: () -> UIImage) -> UIImage {
        if let hit = cache[key] { return hit }
        let image = make()
        cache[key] = image
        return image
    }

    /// 拉丝：横向 1pt 明暗细纹
    static func brushed() -> UIImage { cached("brushed") {
        let size = CGSize(width: 48, height: 220)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func next() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double((seed >> 33) & 0xFFFF) / 65535.0
            }
            var y: CGFloat = 0
            while y < size.height {
                let v = next()
                let alpha = 0.035 + 0.075 * v
                let color = v > 0.52
                    ? UIColor(white: 1, alpha: alpha)
                    : UIColor(white: 0, alpha: alpha * 0.9)
                cg.setFillColor(color.cgColor)
                cg.fill(CGRect(x: 0, y: y, width: size.width, height: 1))
                y += 1
            }
        }
    } }
}

/// 铝面板：底色渐变 + 拉丝纹理
struct AluminumFace: View {
    let tokens: ThemeTokens

    var body: some View {
        ZStack {
            LinearGradient(colors: [tokens.faceTop, tokens.faceBottom],
                           startPoint: .top, endPoint: .bottom)
            Image(uiImage: TextureFactory.brushed())
                .resizable(resizingMode: .tile)
                .blendMode(.softLight)
                .opacity(0.85)
        }
    }
}

// MARK: - 构件

/// 凹陷井：读数窗、帧数窗，顶边暗、底边亮
struct InsetWell<Content: View>: View {
    let tokens: ThemeTokens
    var radius: CGFloat? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        let r = radius ?? tokens.radius
        content()
            .background(
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .fill(LinearGradient(colors: [tokens.wellTop, tokens.wellBottom],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.black.opacity(0.85),
                                                .black.opacity(0.2),
                                                .white.opacity(0.22)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
    }
}

/// 机加工接缝：一条暗 + 一条亮
struct GrooveLine: View {
    var horizontal = true

    var body: some View {
        Group {
            if horizontal {
                VStack(spacing: 0) {
                    Rectangle().fill(.black.opacity(0.45)).frame(height: 1)
                    Rectangle().fill(.white.opacity(0.22)).frame(height: 1)
                }
            } else {
                HStack(spacing: 0) {
                    Rectangle().fill(.black.opacity(0.45)).frame(width: 1)
                    Rectangle().fill(.white.opacity(0.22)).frame(width: 1)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// 沉头螺丝
struct ScrewHead: View {
    var size: CGFloat = 9

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [.white.opacity(0.3), .black.opacity(0.5)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().strokeBorder(.black.opacity(0.55), lineWidth: 0.6)
            Rectangle()
                .fill(.black.opacity(0.6))
                .frame(width: size * 0.72, height: 1.2)
                .rotationEffect(.degrees(-28))
        }
        .frame(width: size, height: size)
    }
}

/// 指示灯：带辉光与高光点
struct LEDDot: View {
    let color: Color
    var size: CGFloat = 6
    var dimmed = false

    var body: some View {
        Circle()
            .fill(dimmed ? color.opacity(0.25) : color)
            .frame(width: size, height: size)
            .overlay(
                Circle().fill(.white.opacity(dimmed ? 0.15 : 0.6))
                    .frame(width: size * 0.32, height: size * 0.32)
                    .offset(x: -size * 0.16, y: -size * 0.16)
            )
            .shadow(color: dimmed ? .clear : color.opacity(0.9), radius: size * 0.75)
    }
}

/// 滚花环：逐齿绘制的机加工纹
struct KnurledRing: View {
    let tokens: ThemeTokens
    var teeth: Int = 96
    var inner: CGFloat = 0.72

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [tokens.faceTop, tokens.faceBottom],
                                     startPoint: .top, endPoint: .bottom))
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let outer = min(size.width, size.height) / 2
                let innerR = outer * inner
                for i in 0..<teeth {
                    let angle = Double(i) / Double(teeth) * 2 * .pi
                    var path = Path()
                    path.move(to: CGPoint(x: center.x + cos(angle) * innerR,
                                          y: center.y + sin(angle) * innerR))
                    path.addLine(to: CGPoint(x: center.x + cos(angle) * outer,
                                             y: center.y + sin(angle) * outer))
                    context.stroke(path,
                                   with: .color(.black.opacity(i % 2 == 0 ? 0.38 : 0.14)),
                                   lineWidth: 1)
                }
            }
            .clipShape(Circle())
            Circle()
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.5), .black.opacity(0.55)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
        }
    }
}

// MARK: - 按键

/// 物理按键：凸起 → 按下时渐变翻转、投影收紧
struct PhysicalButton<Content: View>: View {
    let tokens: ThemeTokens
    var radius: CGFloat? = nil
    var action: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            content()
        }
        .buttonStyle(PhysicalButtonStyle(tokens: tokens, radius: radius))
    }
}

struct PhysicalButtonStyle: ButtonStyle {
    let tokens: ThemeTokens
    var radius: CGFloat? = nil

    func makeBody(configuration: Configuration) -> some View {
        let r = radius ?? tokens.radius
        let pressed = configuration.isPressed
        return configuration.label
            .background(
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .fill(LinearGradient(
                        colors: pressed ? [tokens.faceBottom, tokens.faceTop]
                                        : [tokens.faceTop, tokens.faceBottom],
                        startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: r, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: pressed
                                        ? [.black.opacity(0.5), .white.opacity(0.15)]
                                        : [.white.opacity(0.5), .black.opacity(0.42)],
                                    startPoint: .top, endPoint: .bottom),
                                lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(pressed ? 0.18 : 0.38),
                            radius: pressed ? 1 : 4,
                            x: 0, y: pressed ? 0 : 2)
            )
            .scaleEffect(pressed ? 0.985 : 1)
    }
}

/// 只负责按下缩放的样式（快门盘用）
struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.965
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7),
                       value: configuration.isPressed)
    }
}
