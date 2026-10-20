import CoreMotion

/// CoreMotion 的薄封装：只关心"动得凶不凶"
final class CMMotionManagerShim {
    private let manager = CMMotionManager()
    private(set) var magnitude: Double = 0

    func start(_ onUpdate: @escaping (Double) -> Void) {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 0.1
        manager.startDeviceMotionUpdates(to: .main) { motion, _ in
            guard let m = motion else { return }
            // 角速度的模：转得越快说明越没拿稳
            let r = m.rotationRate
            let value = sqrt(r.x * r.x + r.y * r.y + r.z * r.z)
            self.magnitude = value
            onUpdate(value)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
