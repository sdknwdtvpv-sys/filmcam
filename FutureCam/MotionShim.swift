import CoreMotion
import UIKit

/// CoreMotion 的薄封装：只关心"动得凶不凶"
final class CMMotionManagerShim {
    private let manager = CMMotionManager()
    private(set) var magnitude: Double = 0
    /// 最近一次的重力向量：用来判断手机是竖着还是横着拿
    private(set) var gravity: (x: Double, y: Double, z: Double) = (0, -1, 0)

    func start(_ onUpdate: @escaping (Double) -> Void) {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 0.1
        manager.startDeviceMotionUpdates(to: .main) { motion, _ in
            guard let m = motion else { return }
            // 角速度的模：转得越快说明越没拿稳
            let g = m.gravity
            self.gravity = (g.x, g.y, g.z)
            let r = m.rotationRate
            let value = sqrt(r.x * r.x + r.y * r.y + r.z * r.z)
            self.magnitude = value
            onUpdate(value)
        }
    }

    /// 拿机方向：竖 / 倒置 / 左横 / 右横 / 未知。
    /// 不依赖 UIKit 的朝向通知——那个在锁竖屏的 App 里常年是 unknown。
    var deviceOrientation: UIDeviceOrientation {
        let g = gravity
        if g.y < -0.55 { return .portrait }
        if g.y > 0.55 { return .portraitUpsideDown }
        if g.x < -0.55 { return .landscapeRight }
        if g.x > 0.55 { return .landscapeLeft }
        return .unknown
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}


/// 全局一份传感器：长曝光测稳和拍片朝向共用
@MainActor
enum MotionShim {
    static let shared = CMMotionManagerShim()
}
