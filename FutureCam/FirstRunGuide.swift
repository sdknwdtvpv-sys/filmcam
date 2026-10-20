import SwiftUI

/// 引导要指向的控件
enum GuideTarget: String, CaseIterable, Hashable {
    case strip
    case shutter
    case film
}

/// 控件位置汇总（全局坐标），引导层据此画编号点
struct GuideAnchorKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [GuideTarget: CGRect] = [:]

    static func reduce(value: inout [GuideTarget: CGRect],
                       nextValue: () -> [GuideTarget: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// 把控件在屏幕上的位置报上去
    func guideAnchor(_ target: GuideTarget) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: GuideAnchorKey.self,
                                       value: [target: proxy.frame(in: .global)])
            }
        )
    }
}

/// 首次进入的一次性引导：把三个手势讲清楚，点一下屏幕就关，之后再不出现。
struct FirstRunGuide: View {
    var anchors: [GuideTarget: CGRect]
    var onDismiss: () -> Void

    private struct Step {
        let number: Int
        let target: GuideTarget
        let title: String
        let detail: String
    }

    private let steps: [Step] = [
        // 顺序即界面从上到下的顺序
        Step(number: 1, target: .film,
             title: "换胶片", detail: "点右上角这个窗"),
        Step(number: 2, target: .strip,
             title: "选参数", detail: "点一个格子选中它"),
        Step(number: 3, target: .shutter,
             title: "调参数 / 换模式", detail: "转外圈调数值 · 按住中间左右拖换模式 · 轻点松手就是拍")
    ]

    var body: some View {
        let t = ThemeStore.current

        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.74)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)

                ForEach(steps, id: \.number) { step in
                    if let rect = anchors[step.target] {
                        marker(step.number, tokens: t)
                            .position(markerPosition(for: step.target, rect: rect))
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("这台机器怎么用")
                        .font(t.labelFont(13, .medium))
                        .tracking(1.6)
                        .foregroundColor(.white.opacity(0.55))

                    ForEach(steps, id: \.number) { step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(step.number)")
                                .font(t.monoFont(10, .bold))
                                .foregroundColor(.white)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(t.accent))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.title)
                                    .font(t.labelFont(14, .medium))
                                    .foregroundColor(.white)
                                Text(step.detail)
                                    .font(t.labelFont(11, .medium))
                                    .foregroundColor(.white.opacity(0.62))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    Text("点屏幕任意处开始")
                        .font(t.labelFont(10, .medium))
                        .tracking(0.8)
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.top, 2)
                }
                .padding(18)
                .frame(width: min(geo.size.width - 44, 336), alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.82))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                )
                .position(x: geo.size.width / 2, y: geo.size.height * 0.44)
            }
        }
        .ignoresSafeArea()
    }

    /// 编号点别压在文字上，也别被屏幕边缘切掉
    private func markerPosition(for target: GuideTarget, rect: CGRect) -> CGPoint {
        switch target {
        case .strip: return CGPoint(x: rect.minX + 30, y: rect.minY - 15)
        case .shutter: return CGPoint(x: rect.midX, y: rect.midY)
        case .film: return CGPoint(x: rect.midX, y: rect.minY - 16)
        }
    }

    private func marker(_ number: Int, tokens: ThemeTokens) -> some View {
        Text("\(number)")
            .font(tokens.monoFont(11, .bold))
            .foregroundColor(.white)
            .frame(width: 22, height: 22)
            .background(Circle().fill(tokens.accent))
            .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.5), radius: 4)
    }
}
