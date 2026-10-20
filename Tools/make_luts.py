#!/usr/bin/env python3
"""生成 FutureCam 自有 LUT（.cube, 33³）。

做法：以 CC0 的胶片 LUT 为底（可商用、可派生），在上面叠一套我们自己写的分级
（饱和度 / 分离调色 / 密度曲线）。产物是本项目的衍生作品，不含任何商标。

用法：python3 Tools/make_luts.py
"""

import os

SIZE = 33
OUT = os.path.join(os.path.dirname(__file__), "..", "FutureCam", "LUTs")

LUM = (0.2126, 0.7152, 0.0722)


def clamp(x):
    return 0.0 if x < 0 else (1.0 if x > 1 else x)


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def linear_to_srgb(c):
    c = clamp(c)
    return c * 12.92 if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055


def load_cube(path, size):
    """读 .cube 成 [(r,g,b)] 查找表，坐标是输入颜色"""
    table = {}
    vals = []
    with open(path) as f:
        for line in f:
            t = line.strip()
            if not t or t[0].isalpha():
                continue
            p = t.split()
            if len(p) == 3:
                vals.append(tuple(float(v) for v in p))
    step = 1.0 / (size - 1)
    i = 0
    for bi in range(size):
        for gi in range(size):
            for ri in range(size):
                table[(round(ri * step * 1000), round(gi * step * 1000), round(bi * step * 1000))] = vals[i]
                i += 1
    return table


def sample(table, size, r, g, b):
    """三线性插值查表"""
    def key(x):
        return min(size - 1, max(0, round(x * (size - 1))))
    # 直接用最近点（33³ 足够密，肉眼无差）
    return table.get((key(r), key(g), key(b)), (r, g, b))


class Look:
    """一条 look 的参数化描述。

    lift      黑位抬升（褪色感）
    shoulder  高光肩部压缩    0 = 不压
    contrast  中间调对比      >1 更硬
    saturation 饱和度
    shadowTint / highlightTint  阴影与高光的色偏（RGB 增量）
    gain      通道增益（整体色偏）
    """

    def __init__(self, name, lift=0.0, shoulder=0.35, contrast=1.0, saturation=1.0,
                 shadowTint=(0, 0, 0), highlightTint=(0, 0, 0), gain=(1, 1, 1),
                 mono=False):
        self.name = name
        self.lift = lift
        self.shoulder = shoulder
        self.contrast = contrast
        self.saturation = saturation
        self.shadowTint = shadowTint
        self.highlightTint = highlightTint
        self.gain = gain
        self.mono = mono

    def grade(self, r, g, b):
        """在已有底子上做分级（输入输出都是 sRGB 0…1）"""
        r, g, b = srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b)

        # 饱和度（围绕亮度）
        lum = LUM[0] * r + LUM[1] * g + LUM[2] * b
        r = lum + self.saturation * (r - lum)
        g = lum + self.saturation * (g - lum)
        b = lum + self.saturation * (b - lum)

        # 分离调色：阴影偏一处、高光偏另一处
        w = clamp(lum) ** 0.75
        out = []
        for i, ch in enumerate((r, g, b)):
            tint = self.shadowTint[i] * (1.0 - w) + self.highlightTint[i] * w
            out.append((ch + tint) * self.gain[i])
        r, g, b = out

        # 黑位抬升 + 轻微对比
        def tone(x):
            x = clamp(x)
            if self.contrast != 1.0:
                x = clamp(0.18 * ((x / 0.18) ** self.contrast)) if x > 0.0001 else x
            return self.lift + (1.0 - self.lift) * x

        return linear_to_srgb(tone(r)), linear_to_srgb(tone(g)), linear_to_srgb(tone(b))

    def apply(self, r, g, b):
        # 线性化后再做色调映射，符合胶片密度响应
        r, g, b = srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b)

        # 黑白：先按亮度合并
        if self.mono:
            lum = LUM[0] * r + LUM[1] * g + LUM[2] * b
            r = g = b = lum

        # 对比 + 黑位抬升
        def tone(x):
            x = clamp(x)
            x = x ** (1.0 / self.contrast) if self.contrast != 1.0 else x
            return self.lift + (1.0 - self.lift) * x

        r, g, b = tone(r), tone(g), tone(b)

        # 高光肩部：用有理函数压住 1.0 附近，避免死白
        if self.shoulder > 0:
            s = self.shoulder
            r, g, b = (x / (1.0 + s * x) * (1.0 + s) for x in (r, g, b))
            r, g, b = clamp(r), clamp(g), clamp(b)

        # 饱和度（围绕亮度）
        lum = LUM[0] * r + LUM[1] * g + LUM[2] * b
        r = lum + self.saturation * (r - lum)
        g = lum + self.saturation * (g - lum)
        b = lum + self.saturation * (b - lum)

        # 阴影 / 高光分离调色：按亮度在两者之间插值
        w = clamp(lum) ** 0.8
        for i, ch in enumerate((r, g, b)):
            tint = self.shadowTint[i] * (1.0 - w) + self.highlightTint[i] * w
            ch += tint
            ch *= self.gain[i]
            if i == 0:
                r = ch
            elif i == 1:
                g = ch
            else:
                b = ch

        return linear_to_srgb(r), linear_to_srgb(g), linear_to_srgb(b)


LOOKS = [
    # (输出文件名, Look, 底子 cube 文件名)
    ("dusk-gold-100", Look("暮金 100", lift=0.010, contrast=1.02, saturation=1.06,
                           shadowTint=(-0.008, -0.002, 0.010),
                           highlightTint=(0.022, 0.010, -0.016)), "warm-negative"),
    ("slate-800", Look("石板 800", lift=0.038, contrast=0.90, saturation=0.62,
                       shadowTint=(0.004, 0.004, 0.008),
                       highlightTint=(-0.006, -0.002, 0.004)), "cool-chrome"),
    ("mint-400", Look("薄荷 400", lift=0.024, contrast=0.96, saturation=0.94,
                      shadowTint=(-0.014, 0.012, 0.004),
                      highlightTint=(-0.004, 0.008, 0.006)), "vintage-slide"),
    ("rust-400", Look("铁锈 400", lift=0.018, contrast=1.06, saturation=1.10,
                      shadowTint=(0.020, -0.006, -0.010),
                      highlightTint=(0.010, -0.002, -0.012)), "warm-negative"),
    ("frost-400", Look("霜白 400", lift=0.030, contrast=1.04, saturation=1.0,
                       shadowTint=(0.002, 0.002, 0.006),
                       highlightTint=(0.004, 0.004, 0.008), mono=True), "classic-slide"),
    ("ochre-200", Look("赭石 200", lift=0.014, contrast=1.00, saturation=0.92,
                       shadowTint=(0.012, 0.004, -0.008),
                       highlightTint=(0.016, 0.010, -0.012)), "classic-slide"),
    ("abyss-1600", Look("深潭 1600", lift=0.052, contrast=0.86, saturation=0.76,
                        shadowTint=(-0.004, 0.002, 0.014),
                        highlightTint=(-0.002, 0.004, 0.008)), "cool-chrome"),
]


def write_cube(look, base_table, path):
    lines = [f'TITLE "{look.name}"', f"LUT_3D_SIZE {SIZE}", "DOMAIN_MIN 0.0 0.0 0.0",
             "DOMAIN_MAX 1.0 1.0 1.0"]
    step = 1.0 / (SIZE - 1)
    for bi in range(SIZE):
        b = bi * step
        for gi in range(SIZE):
            g = gi * step
            for ri in range(SIZE):
                r = ri * step
                br, bg, bb = sample(base_table, SIZE, r, g, b)
                out = look.grade(br, bg, bb)
                lines.append("%.6f %.6f %.6f" % out)
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")
    return len(lines)


def main():
    cache = {}
    for filename, look, base in LOOKS:
        if base not in cache:
            cache[base] = load_cube(os.path.join(OUT, base + ".cube"), SIZE)
        path = os.path.join(OUT, filename + ".cube")
        n = write_cube(look, cache[base], path)
        print(f"{filename}.cube  {look.name}  底子 {base}  {os.path.getsize(path)//1024} KB")


if __name__ == "__main__":
    main()
