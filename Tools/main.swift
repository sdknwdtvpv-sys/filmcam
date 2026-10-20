import Foundation
import CoreGraphics

// FutureCam 纯逻辑自检：xcrun swiftc FutureCam/CameraMath.swift Tools/main.swift -o /tmp/logiccheck && /tmp/logiccheck

var failures = 0
var checks = 0

func expect(_ condition: Bool, _ label: String, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if !condition {
        failures += 1
        print("FAIL  \(label)  \(detail())")
    }
}

func close(_ a: Double, _ b: Double, _ eps: Double = 1e-6) -> Bool { abs(a - b) < eps }
func close(_ a: CGFloat, _ b: CGFloat, _ eps: CGFloat = 1e-6) -> Bool { abs(a - b) < eps }

// MARK: 对焦坐标映射

// 竖版预览 1080×1920 放进 378×380 的取景窗：aspectFill 后图像被横向裁掉
let aspect: CGFloat = 1080.0 / 1920.0
let container = CGSize(width: 378, height: 380)

let center = CameraMath.sensorPoint(from: CGPoint(x: 189, y: 190), container: container,
                                    previewAspect: aspect, mirrored: false)
expect(close(center.x, 0.5, 0.001), "取景窗中心 → 传感器中心 x", "\(center)")
expect(close(center.y, 0.5, 0.001), "取景窗中心 → 传感器中心 y", "\(center)")

// 前摄镜像：横向要反过来，纵向不变
let mirrored = CameraMath.sensorPoint(from: CGPoint(x: 100, y: 120), container: container,
                                      previewAspect: aspect, mirrored: true)
let plain = CameraMath.sensorPoint(from: CGPoint(x: 100, y: 120), container: container,
                                   previewAspect: aspect, mirrored: false)
expect(close(mirrored.x, plain.x), "镜像不改变纵向分量", "\(mirrored) vs \(plain)")
expect(close(mirrored.y + plain.y, 1.0, 0.001), "镜像的横向分量是补数", "\(mirrored) vs \(plain)")

// 点到窗外时被夹在 0…1
let outside = CameraMath.sensorPoint(from: CGPoint(x: -500, y: 2000), container: container,
                                     previewAspect: aspect, mirrored: false)
expect((0...1).contains(outside.x) && (0...1).contains(outside.y), "窗外点击被夹紧", "\(outside)")

// 非法输入兜底
let degenerate = CameraMath.sensorPoint(from: .zero, container: .zero,
                                        previewAspect: 0, mirrored: false)
expect(close(degenerate.x, 0.5) && close(degenerate.y, 0.5), "零尺寸兜底到中心", "\(degenerate)")

// MARK: 快门刻度

let fast = CameraMath.shutterProgress(1.0 / 1000)
let mid = CameraMath.shutterProgress(1.0 / 60)
let slow = CameraMath.shutterProgress(1.0 / 8)
expect(fast < mid && mid < slow, "快门进度单调递增", "\(fast) \(mid) \(slow)")
expect((0...1).contains(fast) && (0...1).contains(slow), "进度落在 0…1", "\(fast) \(slow)")
expect(close(CameraMath.shutterProgress(1.0 / 4000), 0, 1e-9), "最快档在最左")
expect(close(CameraMath.shutterProgress(0.25), 1, 1e-9), "最慢档在最右")

// 1/3 档进位
let stepped = CameraMath.steppedStop(1.0 / 60, direction: 1, range: 1.0 / 4000...0.25)
expect(stepped > 1.0 / 60, "进位后更慢", "\(stepped)")
expect(close(stepped / (1.0 / 60), pow(2.0, 1.0 / 3.0), 1e-6), "进位幅度是 1/3 档", "\(stepped)")
let clamped = CameraMath.steppedStop(0.25, direction: 1, range: 1.0 / 4000...0.25)
expect(close(clamped, 0.25), "到顶后不再进位", "\(clamped)")

// MARK: 量化

expect(close(CameraMath.quantize(0.44, step: 0.3), 0.3), "EV 量化到 0.3 档", "\(CameraMath.quantize(0.44, step: 0.3))")
expect(close(CameraMath.quantize(3170, step: 100), 3200), "色温量化到 100K", "\(CameraMath.quantize(3170, step: 100))")
expect(close(CameraMath.quantize(13, step: 10), 10), "色调量化到 10", "\(CameraMath.quantize(13, step: 10))")
expect(close(CameraMath.quantize(13, step: 0), 13), "步长为 0 时原样返回")

// MARK: 读数格式

expect(CameraMath.shutterLabel(1.0 / 60) == "1/60", "快门标签 1/60", CameraMath.shutterLabel(1.0 / 60))
expect(CameraMath.shutterLabel(2.0) == "2.0s", "快门标签 2.0s", CameraMath.shutterLabel(2.0))
expect(CameraMath.evLabel(0.30000000000000004) == "+0.3", "EV 标签 +0.3", CameraMath.evLabel(0.3))
expect(CameraMath.evLabel(-1.5) == "-1.5", "EV 标签 -1.5", CameraMath.evLabel(-1.5))

// MARK: 结果

if failures == 0 {
    print("PASS  \(checks) 项检查全部通过")
    exit(0)
} else {
    print("FAILED  \(failures)/\(checks) 项失败")
    exit(1)
}
