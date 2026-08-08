# PhotoEdit

PhotoEdit 是一个原生 SwiftUI iOS 照片编辑器，面向日常旅行摄影与 `.cube` LUT 工作流。应用使用 Core Image 与长生命周期 Metal-backed `CIContext`；编辑状态是可序列化、非破坏性的。

当前已完成 Phase 1 至 Phase 8；Phase 8.5 正在进行正确性加固。功能包含基础调色、LUT、HSL、曲线、预设、基于 `CIRAWFilter` 的 DNG/ARW RAW 调整、批量处理、色彩管理、HDR preview/SDR tone mapping/10-bit HEIF HDR 导出、线性/径向/画笔局部调整，以及独立的视频 LUT 预览与导出工作流。阶段状态以 [development-progress.md](docs/development-progress.md) 为准。

## Build and test

需要 Xcode 26.6 或更新版本与 iOS 26.5 Simulator：

```bash
xcodegen generate
xcodebuild -project PhotoEdit.xcodeproj -scheme PhotoEdit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test
xcodebuild -project PhotoEdit.xcodeproj -scheme PhotoEdit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build
```

## 当前色彩假设与限制

Phase 6 使用 Extended Linear sRGB + half-float Core Image working space；SDR preview/export 明确输出 sRGB，而检测到真实 HDR 内容时可使用 EDR preview 和 10-bit HEIF Rec.2100 HLG 导出。为避免静默裁切高光，当前 HDR 照片仅允许 identity/基础安全链：HSL、曲线和所有 Color Cube LUT 都会明确禁用，直到具备经过验证的 extended-range 实现。每个 LUT 都必须声明类型、原色/色域和传递函数；Technical LUT 还必须与实际源编码精确匹配。S-Log3/S-Gamut3(.Cine)、LogC、PQ 等 camera-log/transfer 转换尚未实现且会被拒绝。RAW 的零色温/色调是相对相机 as-shot 白平衡的零增量，不会强制 6500 K。详见 [color-management.md](docs/color-management.md)、[hdr-workflow.md](docs/hdr-workflow.md)、[local-adjustments.md](docs/local-adjustments.md) 与 [real-world-validation.md](docs/real-world-validation.md)。

导出保留可由 ImageIO 直接写回的源元数据；实际 Photos 权限、HEIF 编码、真机色彩/GPU 结果需要在真实设备验证。

视频仅支持 SDR：从 Files 导入视频后可调整曝光、对比度、饱和度和已声明 sRGB → sRGB 的 Creative LUT，并导出 MP4/MOV。视频使用独立 AVFoundation/Core Image/Metal 组合，HDR HLG/PQ 视频不会被当作 SDR 静默处理。详见 [video-workflow.md](docs/video-workflow.md)。
