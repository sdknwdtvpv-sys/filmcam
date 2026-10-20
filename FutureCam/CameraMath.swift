import Foundation
import CoreGraphics

/// 相机里的纯计算：不碰 UIKit / AVFoundation，方便直接跑测试。
enum CameraMath {

    // MARK: 对焦坐标

    /// 取景器内的一点 → 传感器归一化坐标（0…1，原点在传感器横图左上）。
    ///
    /// 预览以 aspectFill 铺满容器，所以要先把点击位置还原成图像内坐标，
    /// 再按「图像顺时针转了 90°」换算回传感器坐标系；前摄预览是镜像过的，横向再反一次。
    static func sensorPoint(from viewPoint: CGPoint,
                            container: CGSize,
                            previewAspect: CGFloat,
                            mirrored: Bool) -> CGPoint {
        guard previewAspect > 0, container.width > 0, container.height > 0 else {
            return CGPoint(x: 0.5, y: 0.5)
        }
        let scale = max(container.width / previewAspect, container.height)
        let drawnW = previewAspect * scale
        let drawnH = scale
        let originX = (container.width - drawnW) / 2
        let originY = (container.height - drawnH) / 2

        let u = clamp01((viewPoint.x - originX) / drawnW)
        let v = clamp01((viewPoint.y - originY) / drawnH)

        return mirrored
            ? CGPoint(x: v, y: u)
            : CGPoint(x: v, y: 1 - u)
    }

    static func clamp01(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }

    // MARK: 快门刻度

    /// 快门速度（秒）在 1/4000 … 30s 之间的对数位置，0…1。
    /// 超过 1 秒的部分是长曝光，靠多帧堆栈实现，设备单帧仍不超过 1 秒。
    static func shutterProgress(_ seconds: Double) -> Double {
        guard seconds > 0 else { return 0 }
        let lo = log2(4000.0), hi = log2(1.0 / 30.0)
        return min(max((log2(1 / seconds) - lo) / (hi - lo), 0), 1)
    }

    static func isoProgress(_ iso: Double) -> Double {
        guard iso > 0 else { return 0 }
        let lo = log2(100.0), hi = log2(1600.0)
        return min(max((log2(iso) - lo) / (hi - lo), 0), 1)
    }

    /// 按 1/3 档进位（direction > 0 更慢/更大）
    static func steppedStop(_ value: Double, direction: Int, range: ClosedRange<Double>) -> Double {
        let factor = pow(2.0, 1.0 / 3.0)
        let next = value * (direction > 0 ? factor : 1 / factor)
        return min(max(next, range.lowerBound), range.upperBound)
    }

    // MARK: 量化

    /// 把连续值量化到最近的 step 倍数
    static func quantize(_ value: Double, step: Double) -> Double {
        guard step > 0 else { return value }
        return (value / step).rounded() * step
    }

    /// 覆盖范围 0…1 的刻度进度
    static func progress(_ value: Double, in range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    // MARK: 读数格式

    static func shutterLabel(_ value: Double) -> String {
        if value >= 1 { return String(format: "%.0fs", value.rounded()) }
        return "1/\(Int((1 / value).rounded()))"
    }

    /// 长曝光的整数档位（秒）
    static let longExposureSteps: [Double] = [1, 2, 4, 8, 15, 30]

    /// 超过这个值就走多帧堆栈
    static let longExposureThreshold: Double = 1.05

    static func evLabel(_ value: Double) -> String {
        String(format: "%+.1f", value)
    }
}

// MARK: - 读数的大白话解释（给不懂相机参数的人）

extension CameraMath {
    /// 感光度：数字越大越能在暗处拍，但颗粒越粗
    static func isoHint(_ iso: Double) -> String {
        switch iso {
        case ..<150: return "颗粒最细"
        case ..<300: return "颗粒细"
        case ..<600: return "颗粒中等"
        case ..<1200: return "颗粒明显"
        default: return "颗粒很粗"
        }
    }

    /// 快门：开得越久越亮，也越容易糊
    static func shutterHint(_ seconds: Double) -> String {
        if seconds >= 1.05 {
            return seconds >= 8 ? "必须架稳，长时间积分" : "长曝光，最好架稳"
        }
        let inverse = 1 / max(seconds, 0.0001)
        switch inverse {
        case 250...: return "能定格动作"
        case 100..<250: return "手持不易糊"
        case 50..<100: return "手持慢速"
        case 15..<50: return "容易手抖"
        default: return "要架稳"
        }
    }

    /// 曝光补偿：整体加亮还是压暗
    static func evHint(_ bias: Double) -> String {
        switch bias {
        case 1.05...: return "明显更亮"
        case 0.35..<1.05: return "更亮"
        case -0.35..<0.35: return "标准曝光"
        case -1.05..<(-0.35): return "更暗"
        default: return "明显更暗"
        }
    }

    /// 色温：K 数越大越偏蓝，越小越偏黄
    static func temperatureHint(_ kelvin: Double) -> String {
        switch kelvin {
        case ..<3600: return "偏暖·发黄"
        case 3600..<4800: return "略暖"
        case 4800..<6000: return "接近日光"
        case 6000..<7000: return "略冷"
        default: return "偏冷·发蓝"
        }
    }

    /// 色调：绿 ↔ 洋红
    static func tintHint(_ tint: Double) -> String {
        switch tint {
        case 25...: return "偏洋红"
        case -25..<25: return "标准"
        default: return "偏绿"
        }
    }
}
