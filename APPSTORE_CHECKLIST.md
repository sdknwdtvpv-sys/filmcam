# FilmCam App Store 上架清单

> 对标 DAZZ（胶片）/ 飓风相机（Log+LUT 电影感）的原创独立相机应用。

## 一、工程配置（已在 Xcode 工程中设置）
- **Bundle ID**：`com.filmcam.app`（替换为你的真实域名反向 ID）
- **Display Name**：FilmCam
- **Version / Build**：1.0 / 1
- **Deployment Target**：iOS 17.0
- **Devices**：iPhone + iPad（如仅手机，改为 1）
- **Signing**：Xcode 自动管理，需登录付费开发者账号
- **AppIcon**：`Assets.xcassets/AppIcon.appiconset` 已接入工程，**上线前必须补充 1024×1024 及全套尺寸实图**（当前为占位空壳，Archive/上架会报错）
- **隐私权限文案**：`Info.plist` 已含 `NSCameraUsageDescription`、`NSPhotoLibraryAddUsageDescription`

## 二、4.2 原创性规避（关键）
App Store 指南 4.2 拒绝「缺乏独特设计、仅仅是模板/克隆」的应用。FilmCam 的差异化主张：
1. **原创滤镜引擎**：基于 Core Image 自建胶片/电影 LUT 链（色温、暗角、漏光、双重曝光），并非套用现成 SDK。
2. **原创交互**：拍立得「摇一摇显影」动效、拟物取景框、实时参数面板。
3. **明确差异化**：同时覆盖「胶片」与「电影 Log+LUT 视频」两条路线，区别于单点功能克隆。
4. **描述避免**：不要写「类似 DAZZ/飓风相机」，强调原创设计与功能组合。

## 三、上架前必须补齐
- [ ] 真实 App 图标（全套尺寸）
- [ ] 至少 3–5 张真实截图（含取景、滤镜切换、双曝、视频录制界面）
- [ ] 应用预览视频（可选但建议）
- [ ] 隐私政策网址（托管本 `PRIVACY_POLICY.md` 或自建页面）
- [ ] 关键词：胶片相机、复古、CCD、Log、LUT、双重曝光、拍立得
- [ ] 分类：摄影与录像
- [ ] 年龄分级：4+
- [ ] 内购/广告：当前无；如有会员体系需补充「应用内购买」说明

## 四、合规与审核注意
- 真机测试相机/录制权限弹窗文案是否清晰。
- 视频录制使用 AVAssetWriter，部分旧设备对高码率 H.264 支持有限，建议真机覆盖测试。
- 模拟器无法验证相机与录制，必须在真机走查后再提交。
