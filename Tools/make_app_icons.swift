// 生成 App 图标（方案 C：机身）。
// 用法：swift Tools/make_app_icons.swift && cp /tmp/icon-c.png FutureCam/Assets.xcassets/AppIcon.appiconset/AppIcon.png

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import AppKit

let S: CGFloat = 1024

func ctx() -> CGContext {
    CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
}

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

var seed: UInt64 = 0x9E3779B97F4A7C15
func rnd() -> CGFloat {
    seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
    return CGFloat(seed % 10_000) / 10_000
}

/// 拉丝铝：竖向渐变 + 横向细纹
func brushedAluminum(_ c: CGContext, rect: CGRect) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                       colors: [rgb(0xF2F4F6), rgb(0xD3D8DC), rgb(0xB4BABF)] as CFArray,
                       locations: [0, 0.55, 1])!
    c.saveGState(); c.clip(to: rect)
    c.drawLinearGradient(g, start: CGPoint(x: rect.midX, y: rect.maxY),
                         end: CGPoint(x: rect.midX, y: rect.minY), options: [])
    // 横向拉丝
    var y = rect.minY
    while y < rect.maxY {
        let a = 0.012 + rnd() * 0.030
        c.setFillColor(rnd() > 0.5 ? rgb(0xFFFFFF, a) : rgb(0x5A6068, a * 0.8))
        c.fill(CGRect(x: rect.minX, y: y, width: rect.width, height: 0.8 + rnd() * 1.6))
        y += 1.6 + rnd() * 2.2
    }
    c.restoreGState()
}

/// 黑蒙皮：近黑底 + 颗粒 + 暗角
func leather(_ c: CGContext, rect: CGRect) {
    c.saveGState(); c.clip(to: rect)
    c.setFillColor(rgb(0x17181A)); c.fill(rect)
    for _ in 0..<26000 {
        let x = rect.minX + rnd() * rect.width
        let y = rect.minY + rnd() * rect.height
        c.setFillColor(rnd() > 0.5 ? rgb(0xFFFFFF, 0.014 + rnd() * 0.020)
                                   : rgb(0x000000, 0.05 + rnd() * 0.10))
        c.fill(CGRect(x: x, y: y, width: 1 + rnd() * 2.4, height: 1 + rnd() * 2.4))
    }
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                       colors: [rgb(0x000000, 0), rgb(0x000000, 0.55)] as CFArray, locations: [0.45, 1])!
    c.drawRadialGradient(g, startCenter: CGPoint(x: rect.midX, y: rect.midY), startRadius: rect.width * 0.2,
                         endCenter: CGPoint(x: rect.midX, y: rect.midY), endRadius: rect.width * 0.78,
                         options: [])
    c.restoreGState()
}

/// 滚花盘：一圈钢齿
func knurl(_ c: CGContext, center: CGPoint, outer: CGFloat, inner: CGFloat, teeth: Int) {
    // 细齿：亮暗各一根细线，靠密度出金属感，不靠对比
    let step = 2 * CGFloat.pi / CGFloat(teeth)
    c.setLineCap(.butt)
    for i in 0..<teeth {
        let a = CGFloat(i) * step
        let p1 = CGPoint(x: center.x + cos(a) * inner, y: center.y + sin(a) * inner)
        let p2 = CGPoint(x: center.x + cos(a) * outer, y: center.y + sin(a) * outer)
        c.setStrokeColor(rgb(0x3E454C, 0.42)); c.setLineWidth(3.0)
        c.move(to: p1); c.addLine(to: p2); c.strokePath()

        let b = a + step * 0.5
        let q1 = CGPoint(x: center.x + cos(b) * inner, y: center.y + sin(b) * inner)
        let q2 = CGPoint(x: center.x + cos(b) * outer, y: center.y + sin(b) * outer)
        c.setStrokeColor(rgb(0xFFFFFF, 0.60)); c.setLineWidth(2.4)
        c.move(to: q1); c.addLine(to: q2); c.strokePath()
    }
}

/// 快门钮（A、C 共用）：底座 + 滚花 + 圆顶 + 红点
func shutterDial(_ c: CGContext, center: CGPoint, radius: CGFloat, teeth: Int = 96) {
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -10), blur: 40, color: rgb(0x000000, 0.35))
    c.setFillColor(rgb(0xC7CCD1))
    c.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    c.restoreGState()

    knurl(c, center: center, outer: radius, inner: radius * 0.905, teeth: teeth)

    // 盘面
    let disc = CGRect(x: center.x - radius * 0.845, y: center.y - radius * 0.845,
                      width: radius * 1.69, height: radius * 1.69)
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                       colors: [rgb(0xB9BFC4), rgb(0x8E9499)] as CFArray, locations: [0, 1])!
    c.saveGState()
    c.addEllipse(in: disc); c.clip()
    c.drawLinearGradient(g, start: CGPoint(x: disc.midX, y: disc.maxY),
                         end: CGPoint(x: disc.midX, y: disc.minY), options: [])
    c.restoreGState()

    // 中央圆顶
    let dome = CGRect(x: center.x - radius * 0.60, y: center.y - radius * 0.60,
                      width: radius * 1.20, height: radius * 1.20)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -8), blur: 22, color: rgb(0x000000, 0.30))
    c.setFillColor(rgb(0xFFFFFF)); c.fillEllipse(in: dome)
    c.restoreGState()

    let dg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [rgb(0xFFFFFF), rgb(0xEEF1F3), rgb(0xC3C9CE)] as CFArray,
                        locations: [0, 0.55, 1])!
    c.saveGState(); c.addEllipse(in: dome); c.clip()
    c.drawRadialGradient(dg, startCenter: CGPoint(x: dome.midX, y: dome.midY + dome.height * 0.22),
                         startRadius: 4, endCenter: CGPoint(x: dome.midX, y: dome.midY),
                         endRadius: dome.width * 0.62, options: [])
    c.restoreGState()

    // 红点
    let dotR = radius * 0.115
    let dot = CGRect(x: center.x - dotR, y: center.y - dotR, width: dotR * 2, height: dotR * 2)
    c.saveGState()
    c.setShadow(offset: .zero, blur: 12, color: rgb(0xC4331C, 0.55))
    c.setFillColor(rgb(0xC4331C)); c.fillEllipse(in: dot)
    c.restoreGState()
}

func finish(_ c: CGContext, _ name: String) {
    let img = c.makeImage()!
    let url = URL(fileURLWithPath: "/tmp/icon-\(name).png")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
    print("wrote icon-\(name).png")
}

// ── A：快门盘（顶视图）
do {
    seed = 0x1234567
    let c = ctx()
    let full = CGRect(x: 0, y: 0, width: S, height: S)
    brushedAluminum(c, rect: full)
    shutterDial(c, center: CGPoint(x: S / 2, y: S / 2), radius: S * 0.355, teeth: 168)
    // 边缘一圈内阴影，像嵌在机身里
    c.saveGState()
    c.setStrokeColor(rgb(0x000000, 0.09)); c.setLineWidth(40)
    c.strokeEllipse(in: CGRect(x: -8, y: -8, width: S + 16, height: S + 16))
    c.restoreGState()
    finish(c, "a")
}

// ── B：取景窗（LCD + 指示灯）
do {
    seed = 0x7654321
    let c = ctx()
    let full = CGRect(x: 0, y: 0, width: S, height: S)
    leather(c, rect: full)
    let win = CGRect(x: S * 0.155, y: S * 0.235, width: S * 0.69, height: S * 0.53)
    let r: CGFloat = 34
    // 铝制斜面（渐变，不是一块死白）
    let bezel = win.insetBy(dx: -11, dy: -11)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -10), blur: 34, color: rgb(0x000000, 0.75))
    c.addPath(CGPath(roundedRect: bezel, cornerWidth: r + 9, cornerHeight: r + 9, transform: nil))
    c.clip()
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [rgb(0xEEF1F3), rgb(0xC6CBD0), rgb(0x9AA0A6)] as CFArray,
                        locations: [0, 0.5, 1])!
    c.drawLinearGradient(bg, start: CGPoint(x: bezel.midX, y: bezel.maxY),
                         end: CGPoint(x: bezel.midX, y: bezel.minY), options: [])
    c.restoreGState()
    // 玻璃
    let glass = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [rgb(0x101A16), rgb(0x16221D), rgb(0x0A100D)] as CFArray,
                           locations: [0, 0.5, 1])!
    c.saveGState()
    c.addPath(CGPath(roundedRect: win, cornerWidth: r, cornerHeight: r, transform: nil)); c.clip()
    c.drawLinearGradient(glass, start: CGPoint(x: win.midX, y: win.maxY),
                         end: CGPoint(x: win.midX, y: win.minY), options: [])
    // 扫描线
    var y = win.minY
    while y < win.maxY {
        c.setFillColor(rgb(0xFFFFFF, 0.022))
        c.fill(CGRect(x: win.minX, y: y, width: win.width, height: 1.5))
        y += 5
    }
    // 取景角标
    c.setStrokeColor(rgb(0xE8EDEA, 0.30)); c.setLineWidth(3)
    let inset: CGFloat = 46, len: CGFloat = 44
    for (px, py, dx, dy) in [(win.minX + inset, win.minY + inset, 1.0, 1.0),
                             (win.maxX - inset, win.minY + inset, -1.0, 1.0),
                             (win.minX + inset, win.maxY - inset, 1.0, -1.0),
                             (win.maxX - inset, win.maxY - inset, -1.0, -1.0)] {
        c.move(to: CGPoint(x: px + CGFloat(dx) * len, y: py))
        c.addLine(to: CGPoint(x: px, y: py))
        c.addLine(to: CGPoint(x: px, y: py + CGFloat(dy) * len))
        c.strokePath()
    }
    c.restoreGState()
    // 裂像黄斑：一条横线在黄斑里被错开，正是旁轴对焦的样子
    let patchH = win.height * 0.30
    let patch = CGRect(x: win.minX + win.width * 0.13, y: win.midY - patchH / 2,
                       width: win.width * 0.26, height: patchH)
    c.saveGState()
    c.setFillColor(rgb(0xFFE8B8, 0.10))
    c.fill(patch)
    c.setStrokeColor(rgb(0xFFE8B8, 0.45)); c.setLineWidth(2)
    c.stroke(patch)
    // 黄斑外：一条水平亮线穿窗而过
    c.setStrokeColor(rgb(0xE8EDEA, 0.34)); c.setLineWidth(3)
    c.move(to: CGPoint(x: win.minX + 30, y: win.midY))
    c.addLine(to: CGPoint(x: win.maxX - 30, y: win.midY))
    c.strokePath()
    // 黄斑内：同一条线上下错开
    c.saveGState()
    c.addPath(CGPath(roundedRect: patch, cornerWidth: 6, cornerHeight: 6, transform: nil)); c.clip()
    c.setStrokeColor(rgb(0xFFF3DC, 0.85)); c.setLineWidth(3.5)
    c.move(to: CGPoint(x: patch.minX, y: patch.midY + 11))
    c.addLine(to: CGPoint(x: patch.maxX, y: patch.midY + 11))
    c.strokePath()
    c.restoreGState()
    c.restoreGState()

    // 中央十字
    c.setStrokeColor(rgb(0xE8EDEA, 0.35)); c.setLineWidth(2.5)
    c.move(to: CGPoint(x: win.midX - 26, y: win.midY)); c.addLine(to: CGPoint(x: win.midX + 26, y: win.midY))
    c.move(to: CGPoint(x: win.midX, y: win.midY - 26)); c.addLine(to: CGPoint(x: win.midX, y: win.midY + 26))
    c.strokePath()

    // 底部胶片色条：这卷是什么颜色
    c.setFillColor(rgb(0xC8912B, 0.85))
    c.fill(CGRect(x: win.minX, y: win.minY, width: win.width, height: 7))

    // 指示灯
    let led = CGPoint(x: win.maxX - 52, y: win.maxY - 52)
    c.saveGState()
    c.setShadow(offset: .zero, blur: 26, color: rgb(0xD8452A, 0.9))
    c.setFillColor(rgb(0xE04A2C))
    c.fillEllipse(in: CGRect(x: led.x - 17, y: led.y - 17, width: 34, height: 34))
    c.restoreGState()
    finish(c, "b")
}

// ── C：机身（铝顶盖 + 蒙皮 + 快门）
do {
    seed = 0xABCDEF
    let c = ctx()
    let full = CGRect(x: 0, y: 0, width: S, height: S)
    let plateH = S * 0.52
    let plate = CGRect(x: 0, y: S - plateH, width: S, height: plateH)
    leather(c, rect: CGRect(x: 0, y: 0, width: S, height: S - plateH + 2))
    brushedAluminum(c, rect: plate)
    // 顶盖与蒙皮之间的凹槽
    c.setFillColor(rgb(0x000000, 0.85))
    c.fill(CGRect(x: 0, y: S - plateH - 5, width: S, height: 7))
    c.setFillColor(rgb(0xFFFFFF, 0.5))
    c.fill(CGRect(x: 0, y: S - plateH + 2, width: S, height: 2))
    // 左侧丝印：两条粗细不同的横线，像刻在铝上
    c.setFillColor(rgb(0x2A2E33, 0.42))
    c.fill(CGRect(x: S * 0.085, y: S * 0.745, width: S * 0.235, height: 11))
    c.setFillColor(rgb(0x2A2E33, 0.26))
    c.fill(CGRect(x: S * 0.085, y: S * 0.690, width: S * 0.145, height: 6))
    // 快门盘偏右，压在顶盖与蒙皮交界上沿：不对称才有构图
    shutterDial(c, center: CGPoint(x: S * 0.655, y: S - plateH + S * 0.030),
                radius: S * 0.205, teeth: 132)
    finish(c, "c")
}
