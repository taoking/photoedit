# PhotoEdit

PhotoEdit 是一个原生 SwiftUI iOS 照片编辑器，面向日常旅行摄影与 `.cube` LUT 工作流。应用使用 Core Image 与长生命周期 Metal-backed `CIContext`；编辑状态是可序列化、非破坏性的。

当前已完成 Phase 1 至 Phase 6：包含基础调色、LUT、HSL、曲线、预设、基于 `CIRAWFilter` 的 DNG/ARW RAW 调整、批量处理、色彩管理与 Creative/Technical LUT 分流，以及 HDR preview/SDR tone mapping/10-bit HEIF HDR 导出。后续阶段状态以 [development-progress.md](docs/development-progress.md) 为准。

## Build and test

需要 Xcode 26.6 或更新版本与 iOS 26.5 Simulator：

```bash
xcodegen generate
xcodebuild -project PhotoEdit.xcodeproj -scheme PhotoEdit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test
xcodebuild -project PhotoEdit.xcodeproj -scheme PhotoEdit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build
```

## 当前色彩假设与限制

Phase 6 使用 Extended Linear sRGB + half-float Core Image working space；SDR preview/export 仍明确输出 sRGB，而检测到真实 HDR 内容时，编辑器可使用 EDR preview 和 10-bit HEIF Rec.2100 HLG 导出。每个 LUT 都必须声明类型及输入/输出色彩空间：新导入 `.cube` 默认为未声明，不能被渲染，避免把未知 LUT 伪装成 sRGB。Technical LUT 在全局调整前以 100% 套用，Creative LUT 在其后按强度混合。详见 [color-management.md](docs/color-management.md) 与 [hdr-workflow.md](docs/hdr-workflow.md)。

导出保留可由 ImageIO 直接写回的源元数据；实际 Photos 权限、HEIF 编码、真机色彩/GPU 结果需要在真实设备验证。
