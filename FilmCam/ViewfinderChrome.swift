import SwiftUI
import UIKit
import CoreMotion
import AVKit

struct GridOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: CGPoint(x: geo.size.width / 3, y: 0))
                p.addLine(to: CGPoint(x: geo.size.width / 3, y: geo.size.height))
                p.move(to: CGPoint(x: geo.size.width * 2 / 3, y: 0))
                p.addLine(to: CGPoint(x: geo.size.width * 2 / 3, y: geo.size.height))
                p.move(to: CGPoint(x: 0, y: geo.size.height / 3))
                p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 3))
                p.move(to: CGPoint(x: 0, y: geo.size.height * 2 / 3))
                p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height * 2 / 3))
            }
            .stroke(CameraTheme.amber.opacity(0.28), lineWidth: 0.75)
        }
        .padding(10)
    }
}

/// 水平仪：加速度算横滚角，中心琥珀线随倾斜偏移，接近水平时变亮

struct LevelIndicator: View {
    @StateObject private var meter = LevelMeter()

    var body: some View {
        GeometryReader { geo in
            let midY = geo.size.height / 2
            let maxOffset = geo.size.width / 2 - 24
            let offset = CGFloat(meter.roll) / 45.0 * maxOffset
            let level = abs(meter.roll) < 1.0
            ZStack {
                Rectangle().fill(CameraTheme.amber.opacity(0.18))
                    .frame(width: geo.size.width - 48, height: 1)
                Rectangle()
                    .fill(level ? CameraTheme.amber : CameraTheme.amber.opacity(0.55))
                    .frame(width: 60, height: 2)
                    .position(x: geo.size.width / 2 + offset, y: midY)
                    .shadow(color: level ? CameraTheme.amber.opacity(0.6) : .clear, radius: 6)
            }
            .overlay(alignment: .bottom) {
                Text(String(format: "%.1f°", meter.roll))
                    .font(CameraTheme.mono(11))
                    .foregroundColor(level ? CameraTheme.amber : CameraTheme.inkDim)
                    .padding(.bottom, 34)
            }
        }
        .padding(10)
        .onAppear { meter.start() }
        .onDisappear { meter.stop() }
    }
}

/// 横滚角数据源（仅水平仪可见时运行）

final class LevelMeter: ObservableObject, @unchecked Sendable {
    @Published var roll: Double = 0
    private let motion = CMMotionManager()
    private let queue = OperationQueue()

    func start() {
        guard motion.isAccelerometerAvailable, !motion.isAccelerometerActive else { return }
        motion.accelerometerUpdateInterval = 1.0 / 20.0
        motion.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
            guard let self, let data else { return }
            let a = data.acceleration
            let roll = atan2(a.x, sqrt(a.y * a.y + a.z * a.z)) * 180.0 / .pi
            DispatchQueue.main.async { self.roll = roll }
        }
    }

    func stop() { motion.stopAccelerometerUpdates() }
    deinit { motion.stopAccelerometerUpdates() }
}

// MARK: - 顶部圆角形状

/// 只描三条边（左 / 上 / 右）的圆角描边：
/// 弹层面板贴屏幕底部时，底边不该出现一条横线。
