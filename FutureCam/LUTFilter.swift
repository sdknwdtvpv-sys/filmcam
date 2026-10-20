import CoreImage
import Foundation
import os

/// 一个 3D LUT（.cube 解析结果），可直接喂给 Core Image 的 CIColorCube。
struct CubeLUT {
    let dimension: Int
    let data: Data   // Float32 RGBA，共 维度³×4；排列顺序为「红最快、绿次之、蓝最慢」，与 .cube 文件一致

    /// 把 LUT 朝「单位 LUT（原图直出）」方向按 t 混合，得到可调节强度的 LUT。
    func withIntensity(_ t: Float) -> CubeLUT {
        guard t < 1.0 - 1e-4 else { return self }
        let n = dimension
        let total = n * n * n
        var out = [Float](repeating: 0, count: total * 4)
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            let src = base.assumingMemoryBound(to: Float.self)
            for i in 0..<total {
                let ri = i % n
                let gi = (i / n) % n
                let bi = i / (n * n)
                let r0 = Float(ri) / Float(n - 1)
                let g0 = Float(gi) / Float(n - 1)
                let b0 = Float(bi) / Float(n - 1)
                let j = i * 4
                out[j]     = r0 * (1 - t) + src[j] * t
                out[j + 1] = g0 * (1 - t) + src[j + 1] * t
                out[j + 2] = b0 * (1 - t) + src[j + 2] * t
                out[j + 3] = 1
            }
        }
        return CubeLUT(dimension: n, data: Data(bytes: out, count: out.count * MemoryLayout<Float>.stride))
    }

    /// 解析 Adobe/IRIDAS .cube 文本（支持 3D LUT：LUT_3D_SIZE）。
    static func parse(_ text: String) throws -> CubeLUT {
        var dim = 0
        var floats: [Float] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let comps = line.split(whereSeparator: { $0.isWhitespace })
            if comps.first == "LUT_3D_SIZE", comps.count >= 2, let d = Int(comps[1]) {
                dim = d
                continue
            }
            // 非数值首 token（TITLE / DOMAIN_MIN / DOMAIN_MAX 等关键字）直接跳过
            guard comps.count >= 3,
                  let r = Float(comps[0]), let g = Float(comps[1]), let b = Float(comps[2]) else {
                continue
            }
            floats.append(contentsOf: [r, g, b, 1.0])
        }
        guard dim > 1 else { throw LUTError.noSize }
        let expected = dim * dim * dim * 4
        guard floats.count == expected else { throw LUTError.countMismatch(floats.count, expected) }
        return CubeLUT(dimension: dim,
                       data: Data(bytes: floats, count: floats.count * MemoryLayout<Float>.stride))
    }

    enum LUTError: Error { case noSize, countMismatch(Int, Int) }
}

/// LUT 资源加载与施加（Core Image CIColorCube）。
struct LUTFilter {
    /// 预设 → 绑定的 .cube 文件名（位于 FutureCam/LUTs/ 下，CC0 HaldCLUT，已改描述性文件名）。
    /// 想新增/替换 LUT：把 .cube 丢进 LUTs/，在此映射即可。
    static let lutFileForPreset: [FilmPreset: String] = [
        .kodakGold: "warm-negative.cube",
        .fuji400:   "vintage-slide.cube",
        .cinematic: "classic-slide.cube",
        // .classicBnw / .fadedCinema 走纯算法；cool-chrome.cube 已内置可随时映射
    ]

    private static let cache = OSAllocatedUnfairLock<[FilmPreset: CubeLUT]>(initialState: [:])

    /// 取预设对应的 LUT（按强度烘焙后缓存，强度固定故只算一次）。
    static func resolvedLUT(for preset: FilmPreset, intensity: Float) -> CubeLUT? {
        if let cached = cache.withLock({ $0[preset] }) { return cached }
        guard let file = lutFileForPreset[preset],
              let url = Bundle.main.url(forResource: file, withExtension: nil, subdirectory: "LUTs"),
              let text = try? String(contentsOf: url, encoding: .utf8),
              let base = try? CubeLUT.parse(text) else { return nil }
        let baked = base.withIntensity(intensity)
        cache.withLock { $0[preset] = baked }
        return baked
    }

    /// 用 CIColorCube 施加 LUT 到图像。
    static func apply(_ lut: CubeLUT, to image: CIImage) -> CIImage {
        guard let f = CIFilter(name: "CIColorCube") else { return image }
        f.setValue(image, forKey: kCIInputImageKey)
        f.setValue(lut.data, forKey: "inputCubeData")
        f.setValue(lut.dimension, forKey: "inputCubeDimension")
        return f.outputImage ?? image
    }
}
