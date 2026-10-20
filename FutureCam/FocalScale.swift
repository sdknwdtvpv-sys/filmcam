import SwiftUI

/// 焦段刻度：一小排光学焦段，当前那颗标红。
/// 装在取景窗左下角，像相机上印的镜头刻度，不占机身版面。
struct FocalScale: View {
    let options: [CGFloat]
    let current: CGFloat
    let tokens: ThemeTokens
    let onSelect: (CGFloat) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, value in
                if index > 0 {
                    Rectangle()
                        .fill(.white.opacity(0.22))
                        .frame(width: 0.5, height: 9)
                }
                Button {
                    onSelect(value)
                } label: {
                    Text(label(value))
                        .font(tokens.monoFont(8.5, .semibold))
                        .foregroundColor(isActive(value) ? tokens.accentGlow : .white.opacity(0.55))
                        .frame(width: 30, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("焦段 \(label(value))")
            }
        }
        .padding(.horizontal, 4)
        .background(
            Capsule().fill(.black.opacity(0.35))
                .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 0.5))
        )
    }

    private func isActive(_ value: CGFloat) -> Bool {
        abs(value - current) < abs(closestOther(value) - current) || abs(value - current) < 0.001
    }

    private func closestOther(_ value: CGFloat) -> CGFloat {
        options.filter { $0 != value }.min(by: { abs($0 - current) < abs($1 - current) }) ?? value
    }

    private func label(_ value: CGFloat) -> String {
        value == value.rounded()
            ? "\(Int(value))×"
            : String(format: "%.1f×", value)
    }
}
