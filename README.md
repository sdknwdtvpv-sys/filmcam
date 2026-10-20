# FilmCam

一台只做一件事的胶片相机：实时胶片滤镜、拍立得显影、双重曝光，以及带 LUT 的竖版视频录制。
纯原生 SwiftUI + AVFoundation + Core Image，无第三方依赖。

> 需要 **Xcode 26+ / iOS 17.0+**。相机能力只能在真机上验证，模拟器没有摄像头。

## 跑起来

```bash
open FilmCam.xcodeproj      # 选 FilmCam scheme + 真机运行
```

首次运行会依次请求**相机**、**麦克风**（录音用；拒绝则静音录像）、**相册写入**（保存成片；拒绝则只存应用内相册）。

命令行编译（不需要签名）：

```bash
xcodebuild -project FilmCam.xcodeproj -scheme FilmCam \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -configuration Debug -derivedDataPath ./build CODE_SIGNING_ALLOWED=NO build
```

## 功能

| 模块 | 说明 |
| --- | --- |
| 胶片滤镜 | Core Image 链：色温 → 色彩控制 → 暗角 → 漏光 → 3D LUT（`.cube`，强度可调） |
| 胶片预设 | 柯达金 200 / 富士 400 / 经典黑白 / 褪色电影 / 电影 LUT |
| 双重曝光 | 第一张只做合成底图（短暂提示），第二张合成后才进显影 |
| 视频录制 | 1080×1920 / 30fps / H.264 12Mbps，滤镜实时烘焙进画面，有麦克风权限时带 AAC 音轨 |
| 手动曝光 | ISO、快门（1/4000–1/4）、EV 补偿；设备侧自动 clamp 到支持范围 |
| 白平衡 | 色温 3000–8000K、色调 −150–150 |
| 取景手势 | 点按对焦、长按锁定 AE/AF、捏合变焦（1×–8×） |
| 镜头 | 前后摄切换（前摄镜像在滤镜管线内完成） |
| 显影 | 拍立得白边 + 日期戳；摇一摇或等待自动显影 |
| 相册 | 应用内网格浏览（照片 + 视频）、全屏查看、照片缩放、视频播放、分享、删除 |

## 目录结构

```
FilmCam/
├─ FilmCamApp.swift              入口，注入 CameraManager
├─ CameraView.swift              相机主界面 + 各类控件 + 弹层 + toast + 显影页
├─ CameraTheme.swift             设计令牌（配色 / 等宽字体）
├─ CameraManager.swift           主线程视图模型：UI 状态、权限、保存、相册列表
├─ CaptureSessionController.swift 后台相机引擎：会话、滤镜、拍照、录制、双曝、对焦变焦
├─ FilmFilter.swift              胶片滤镜链与预设参数、双重曝光合成
├─ LUTFilter.swift               .cube 解析 / 强度烘焙 / CIColorCube 施加
├─ FilmPreview.swift             胶片选择弹层里的合成预览图
├─ AlbumStore.swift              应用内相册的文件层（读 / 写 / 删）
├─ AlbumView.swift               相册网格 + 全屏查看 + 删除确认
├─ MediaThumbnail.swift          ImageIO / AVAsset 下采样缩略图 + 缓存
├─ ViewfinderGestures.swift      取景手势层、对焦框、变焦角标、镜头切换按钮
├─ DebugHarness.swift            仅 Debug：启动参数直达界面 / 合成预览
└─ LUTs/                         CC0 HaldCLUT（以 folder reference 整体打包）
```

## 几个关键实现

**预览帧不进 SwiftUI 状态。** 相机帧通过 `PassthroughSubject` 直连 `UIImageView.image`，
如果每帧都 `@Published`，整棵视图树每帧重算，真机会明显掉帧。

**方向统一在渲染前修正。** 相机 buffer 是传感器原生横向，`CIImage(...).oriented(.right)` 之后再进滤镜链；
拍照路径的 JPEG 同样要补这一步（EXIF 里的方向会被 `CIImage(cgImage:)` 忽略，漏了成片就横躺）。

**前摄镜像不能用 `connection.isVideoMirrored`。** 那是传感器空间（横向）的翻转，转 90° 之后会变成上下颠倒。
这里在滤镜管线里、转正之后再左右翻。

**会话恢复。** 进后台主动 `stopRunning()`，回前台 `startRunning()`；同时监听
`AVCaptureSessionRuntimeError` / `InterruptionEnded`，来电或媒体服务重启后能自己接上。

**缩略图一律下采样。** `UIImage(contentsOfFile:)` 读一张 12MP 成片解码后约 48MB，网格里十几张就会被系统杀掉。
照片走 ImageIO `CGImageSourceCreateThumbnailAtIndex`，视频走 `AVAssetImageGenerator`，结果进 `NSCache`。

**相册存储只依赖沙盒。** `Documents/filmcam_photos`、`Documents/filmcam_videos`；
系统「照片」写入用 `addOnly` 权限，所以应用内删除**不会**删掉系统相册里的副本，删除确认里已写明。

## Debug 自检

模拟器没有相机，也没法脚本点击，所以 Debug 构建提供了启动参数（`DebugHarness.swift`，Release 不含）：

```bash
xcrun simctl launch booted com.filmcam.app -fcScreen album      # album / albumDetail / albumPhoto / film / settings
xcrun simctl launch booted com.filmcam.app -fcStubPreview       # 垫一帧合成预览，检查叠加层可读性
```

`-fcStubPreview` 只是布局自检用的假画面，**不能**拿来当商店截图。

## 真机测试清单

改完相机相关代码后至少过一遍：

- [ ] 首次安装：权限弹窗文案清楚，拒绝相机后能点「去系统设置」回来恢复
- [ ] 拒绝麦克风后录制仍可用（无声）
- [ ] 拒绝相册写入：提示「照片未保存」而不是谎报成功；应用内相册里仍有照片
- [ ] 切后台再回来：预览自动恢复，不需要杀进程
- [ ] 来电/其它 App 抢占相机后回来：预览恢复
- [ ] 前后摄切换：预览镜像正确（自拍时左右符合直觉、上下不颠倒），对焦位置准确
- [ ] 点按对焦、长按锁定 AE/AF（对焦框出现、锁定后常驻）
- [ ] 捏合变焦到 8×，切换镜头后倍率复位
- [ ] 三种模式各拍一次：照片 / 双曝（两次快门）/ 视频（录 10s 后停止）
- [ ] 录制结果：系统「照片」里能看到视频；应用内相册里也有；分享面板能导出
- [ ] 删除一张照片 / 一条视频：网格与全屏都同步，系统相册不受影响
- [ ] 老机型（A12 及以下）预览帧率与录制流畅度

## 已知限制

- 仅竖屏，`UIRequiresFullScreen`；`TARGETED_DEVICE_FAMILY = 1`（iPhone）
- 视频固定 1080×1920 竖版 30fps，未做多档分辨率 / 帧率
- 未做 HDR、夜景、闪光灯强度、超广角/长焦镜头选择
- 相册没有云同步 / 收藏 / 搜索
- 无 App 内购与账号体系
