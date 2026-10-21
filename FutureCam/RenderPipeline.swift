import CoreImage
import UIKit

/// 一条渲染管线，三个出口共用。
///
/// v1 之前预览、静帧、视频各写一遍滤镜顺序，加一个功能要改三处，
/// 一旦漏改就是"预览有、成片没有"这种问题（颗粒和调色都踩过）。
/// 现在只有这里定义顺序，三个出口只决定"要不要叠调色、要不要叠颗粒"。
enum RenderPipeline {

    /// 渲染配方：决定这一帧走哪几道工序
    struct Recipe {
        var preset: FilmPreset
        var traits: RollTraits?
        /// 视频预览不叠颗粒（会闪），静帧才叠
        var grain: GrainSettings
        /// 调色只作用于成片与显影页，不参与取景
        var grade: GradeSettings?
        /// 取景与录像用 .fast：跳过柔化与 halation，保帧率
        var quality: FilmFilter.Quality = .full
        /// 前置摄像头需要镜像
        var mirrored: Bool = false

        static func preview(preset: FilmPreset, traits: RollTraits?) -> Recipe {
            Recipe(preset: preset, traits: traits, grain: .none, grade: nil, quality: .fast)
        }

        static func still(preset: FilmPreset, traits: RollTraits?, grain: GrainSettings,
                          grade: GradeSettings?, mirrored: Bool) -> Recipe {
            Recipe(preset: preset, traits: traits, grain: grain, grade: grade, mirrored: mirrored)
        }

        static func video(preset: FilmPreset, traits: RollTraits?, mirrored: Bool) -> Recipe {
            Recipe(preset: preset, traits: traits, grain: .none, grade: nil,
                   quality: .fast, mirrored: mirrored)
        }
    }

    static func render(_ source: CIImage, recipe: Recipe) -> CIImage {
        let oriented = recipe.mirrored ? mirror(source) : source
        var out = FilmFilter.apply(oriented,
                                   preset: recipe.preset,
                                   traits: recipe.traits,
                                   grain: recipe.grain,
                                   quality: recipe.quality)
        if let grade = recipe.grade {
            out = FilmFilter.applyGrade(out, grade)
        }
        return out
    }

    /// 只叠调色（换配色时从"只过胶片的底"重渲染用）
    static func regrade(_ base: CIImage, grade: GradeSettings?) -> CIImage {
        guard let grade else { return base }
        return FilmFilter.applyGrade(base, grade)
    }

    private static func mirror(_ image: CIImage) -> CIImage {
        image
            .transformed(by: CGAffineTransform(scaleX: -1, y: 1))
            .transformed(by: CGAffineTransform(translationX: image.extent.width, y: 0))
    }
}
