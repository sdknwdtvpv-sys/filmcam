import SwiftUI
import UIKit
import CoreMotion
import AVKit

struct PermissionGate: View {
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    private var locked: Bool { title.contains("关闭") }

    var body: some View {
        let t = ThemeStore.current

        ZStack {
            LeatherPanel().ignoresSafeArea()
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(spacing: 20) {
                // 镜头盖
                ZStack {
                    KnurledRing(tokens: t, teeth: 96, inner: 0.88)
                        .frame(width: 156, height: 156)
                        .shadow(color: .black.opacity(0.65), radius: 18, y: 10)
                    Circle()
                        .fill(RadialGradient(colors: [Color(hex: 0x35383B), Color(hex: 0x141517)],
                                             center: .topLeading, startRadius: 4, endRadius: 90))
                        .frame(width: 136, height: 136)
                        .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                    Circle()
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                        .frame(width: 104, height: 104)
                    VStack(spacing: 2) {
                        Text("FUTURE CAM")
                            .font(.custom("Futura-Medium", size: 11))
                            .tracking(3)
                            .foregroundColor(.white.opacity(0.32))
                        Text(locked ? "LOCKED" : "LENS CAP")
                            .font(.system(size: 6, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(.white.opacity(0.22))
                    }
                    // 侧边捏手
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(colors: [Color(hex: 0x3A3D40), Color(hex: 0x17191B)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 14, height: 30)
                        .offset(x: 84)
                        .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
                }
                .rotationEffect(.degrees(locked ? 0 : -6))

                VStack(spacing: 7) {
                    Text(title)
                        .font(t.labelFont(17, .medium))
                        .foregroundColor(.white)
                    Text(message)
                        .font(t.monoFont(11, .regular))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 280)
                }

                PhysicalButton(tokens: t, radius: 6, action: {
                    Haptics.impact(.medium)
                    action()
                }) {
                    HStack(spacing: 8) {
                        LEDDot(color: t.glow, size: 5)
                        Text(buttonTitle)
                            .font(t.labelFont(13, .medium))
                            .tracking(0.8)
                            .foregroundColor(t.ink)
                    }
                    .padding(.horizontal, 22)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(buttonTitle)
            }
            .padding(.horizontal, 30)
        }
    }
}

// MARK: - Toast

/// 底部提示条底座：图标 + 文案 + 右侧动作。
/// 视频/照片/双曝三条提示原本各写一份同样的底板，样式一改就漏改，统一到这里。
