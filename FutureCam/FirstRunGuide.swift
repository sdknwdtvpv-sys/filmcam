import SwiftUI

/// 引导要逐个点亮的控件
enum GuideTarget: String, CaseIterable, Hashable {
    case title
    case film
    case flash
    case strip
    case collar
    case shutter
    case album
    case flip

    /// 圆形控件用圆洞，方键用圆角方洞
    var isRound: Bool {
        self == .collar || self == .shutter || self == .album
    }
}

/// 控件位置汇总（全局坐标），引导层据此挖洞和定位
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

/// 首次进入的逐项引导：一次只点亮一个控件，说一句话，按「下一步」往下走。
/// 八步走完才开始使用，之后不再出现。
struct FirstRunGuide: View {
    var anchors: [GuideTarget: CGRect]
    var onFinish: () -> Void
    var initialStep: Int = 0

    @State private var index = 0

    private struct Step {
        let target: GuideTarget
        let title: String
        let detail: String
    }

    /// 顺序沿机身从上到下：顶盖 → 参数条 → 快门盘 → 底部两个键
    private let steps: [Step] = [
        Step(target: .title, title: "我的",
             detail: "点机身上的铭牌，打开设置：语言、网格、水平仪、日期背印"),
        Step(target: .film, title: "换胶片",
             detail: "点这个窗开仓，换一筒胶片"),
        Step(target: .flash, title: "闪光",
             detail: "关 / 自动 / 开 三档，录像时「开」同时点着手电"),
        Step(target: .strip, title: "参数条",
             detail: "点一个格子选中它，下面的大轮盘就调它"),
        Step(target: .collar, title: "调数值",
             detail: "转这圈滚花，每过一颗齿咔哒一下"),
        Step(target: .shutter, title: "快门",
             detail: "轻点松手就是拍；按住左右拖换模式，左双曝右录像"),
        Step(target: .album, title: "相册",
             detail: "拍过的照片和视频都在这里"),
        Step(target: .flip, title: "前后摄",
             detail: "切换前置 / 后置镜头")
    ]

    var body: some View {
        let t = ThemeStore.current
        let step = steps[min(index, steps.count - 1)]

        GeometryReader { geo in
            ZStack {
                if let rect = anchors[step.target] {
                    let hole = holeRect(for: rect, in: geo.size)
                    let round = step.target.isRound

                    // 遮罩挖洞：洞外压暗，洞里保持原样
                    Path { path in
                        path.addRect(CGRect(origin: .zero, size: geo.size))
                        if round {
                            path.addEllipse(in: hole)
                        } else {
                            path.addRoundedRect(in: hole,
                                                cornerSize: CGSize(width: 12, height: 12))
                        }
                    }
                    .fill(Color.black.opacity(0.78), style: FillStyle(eoFill: true))

                    Group {
                        if round {
                            Circle().strokeBorder(t.accent.opacity(0.85), lineWidth: 1.5)
                        } else {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(t.accent.opacity(0.85), lineWidth: 1.5)
                        }
                    }
                    .frame(width: hole.width, height: hole.height)
                    .position(x: hole.midX, y: hole.midY)

                    // 先铺一层吞掉点击，别让人误触到被点亮的控件
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { }

                    callout(t, hole: hole, size: geo.size)
                } else {
                    // 位置还没测到时先压暗，避免闪一帧无遮罩的画面
                    Color.black.opacity(0.78).onTapGesture { }
                }
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.22), value: index)
        .onAppear { index = min(max(initialStep, 0), steps.count - 1) }
    }

    private func callout(_ t: ThemeTokens, hole: CGRect, size: CGSize) -> some View {
        let step = steps[min(index, steps.count - 1)]
        let below = hole.minY < size.height * 0.32

        return VStack(spacing: 0) {
            if below {
                Spacer().frame(height: hole.maxY + 18)
                card(t, step: step)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                card(t, step: step)
                Spacer().frame(height: max(24, size.height - hole.minY + 18))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func card(_ t: ThemeTokens, step: Step) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(index + 1) / \(steps.count)")
                    .font(t.monoFont(9, .bold))
                    .foregroundColor(t.accent)
                Text(step.title)
                    .font(t.labelFont(15, .medium))
                    .foregroundColor(.white)
                Spacer(minLength: 0)
            }
            Text(step.detail)
                .font(t.labelFont(12, .medium))
                .foregroundColor(.white.opacity(0.66))
                .fixedSize(horizontal: false, vertical: true)

            Button {
                if index + 1 >= steps.count {
                    onFinish()
                } else {
                    index += 1
                }
            } label: {
                Text(index + 1 >= steps.count ? "开始使用" : "下一步")
                    .font(t.labelFont(12, .medium))
                    .tracking(1.2)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(t.accent)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }

    /// 高亮范围：目标外扩一圈，再夹在屏幕内；圆控件取正方形
    private func holeRect(for rect: CGRect, in size: CGSize) -> CGRect {
        var padded = rect.insetBy(dx: -7, dy: -7)
        if steps[min(index, steps.count - 1)].target.isRound {
            let side = max(padded.width, padded.height)
            padded = CGRect(x: padded.midX - side / 2, y: padded.midY - side / 2,
                            width: side, height: side)
        }
        let x = max(6, min(padded.minX, size.width - padded.width - 6))
        let y = max(6, min(padded.minY, size.height - padded.height - 6))
        return CGRect(x: x, y: y, width: padded.width, height: padded.height)
    }
}
