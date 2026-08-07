# PhotoEdit

PhotoEdit 是一个原生 SwiftUI iOS 照片编辑器，面向日常旅行摄影与 `.cube` LUT 工作流。应用使用 Core Image 与长生命周期 Metal-backed `CIContext`；编辑状态是可序列化、非破坏性的。

当前已实现 Phase 1：照片/文件导入、基础调色、3D LUT、裁切/旋转/镜像、撤销、前后对比，以及 JPEG/HEIF 全分辨率导出。后续阶段状态以 [development-progress.md](docs/development-progress.md) 为准。

## Build and test

需要 Xcode 26.6 或更新版本与 iOS 26.5 Simulator：

```bash
xcodegen generate
xcodebuild -project PhotoEdit.xcodeproj -scheme PhotoEdit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test
xcodebuild -project PhotoEdit.xcodeproj -scheme PhotoEdit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build
```

## 当前色彩假设与限制

Phase 1 面向标准动态范围照片和 Creative LUT。工作空间为线性 sRGB；导入图像的方向会在读取时规范化。LUT 文件中没有可验证的色彩空间元数据，因此导入 LUT 假定其输入和输出均为 sRGB。技术 LUT、HDR、RAW 和视频在后续阶段处理。

导出保留可由 ImageIO 直接写回的源元数据；实际 Photos 权限、HEIF 编码、真机色彩/GPU 结果需要在真实设备验证。
