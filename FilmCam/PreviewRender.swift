import SwiftUI
import UIKit
import Combine
import CoreMotion
import AVKit

struct PreviewView: UIViewRepresentable {
    let frames: PassthroughSubject<UIImage, Never>
    /// 首帧兜底：视图比帧晚创建时先显示上一帧，而不是黑屏
    var initialImage: UIImage? = nil

    func makeUIView(context: Context) -> UIView {
        // 关键：不能把 UIImageView 直接返回给 SwiftUI。
        // UIImageView 的固有尺寸 = 图片尺寸，相机帧动辄 4000×3000，
        // 会让取景器膨胀到远超屏幕，把顶部/底部所有 UI 挤出屏幕（真机必现）。
        // 用普通容器 view 承载（无固有尺寸），图片 view 靠约束贴边，
        // 尺寸完全由外层 .frame 决定。
        let container = UIView()
        container.backgroundColor = .black

        let iv = UIImageView()
        iv.image = initialImage
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = .black
        iv.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(iv)
        NSLayoutConstraint.activate([
            iv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            iv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            iv.topAnchor.constraint(equalTo: container.topAnchor),
            iv.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        context.coordinator.cancellable = frames
            .receive(on: DispatchQueue.main)
            .sink { [weak iv] image in iv?.image = image }
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var cancellable: AnyCancellable?
    }
}
