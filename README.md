# PhotoEdit

PhotoEdit 是一个原生 SwiftUI iOS 照片编辑器，面向日常旅行摄影与 `.cube` LUT 工作流。应用使用 Core Image 与长生命周期 Metal-backed `CIContext`；编辑状态是可序列化、非破坏性的。

当前已完成 Phase 1 至 Phase 9.0。功能包含基础调色、LUT、HSL、曲线、预设、基于 `CIRAWFilter` 的 DNG/ARW RAW 调整、批量处理、色彩管理、HDR preview/SDR tone mapping/10-bit HEIF HDR 导出、线性/径向/画笔局部调整，以及独立的视频 LUT 预览与导出工作流。Phase 9.0 进一步补齐自适应编辑布局、当前会话恢复、导出状态/取消和 UI 自动化。阶段状态以 [development-progress.md](docs/development-progress.md) 为准。

## Build and test

最低运行版本为 **iOS 26.0**。当前版本仅面向 iOS 26+，旧 iOS 17–25 兼容暂不维护。需要 Xcode 26.6 或更新版本与 iOS 26.5 Simulator：

```bash
xcodegen generate
xcodebuild -project PhotoEdit.xcodeproj -scheme PhotoEdit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test
xcodebuild -project PhotoEdit.xcodeproj -scheme PhotoEdit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build
```

真机首次签名、构建、安装与启动步骤见 [device-installation.md](docs/device-installation.md)。

## iPhone 编辑器体验

编辑页采用照片优先的深色中性工作区：默认只保留底部横向工具栏，选择光线、颜色、HSL、曲线、细节、LUT、裁切或局部工具后才展开对应参数；可通过参数标题栏的箭头重新收起。顶部仅保留关闭当前照片、撤销、按住查看原图、导出和更多操作；重新导入、预设、批量、参考图及复制/粘贴等次级功能归入“更多”。预览支持连续累积的双指缩放和拖拽，并按图片边界约束平移，双击恢复全图。

竖屏下照片与可滚动参数区上下排列；横屏会自动切换为照片在左、参数在右的双栏布局。辅助功能字号下底部工具栏改用图标主导形式，关键顶部图标保持稳定触控尺寸。当前照片的原始数据和 `EditState` 会自动保存到 Application Support；返回首页时可保留并继续上次编辑，明确选择“放弃”才删除会话。全分辨率导出期间编辑页持续显示状态和取消入口，并阻止重复提交。

应用图标位于 `PhotoEdit/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`，为不透明 1024 × 1024 PNG，并通过 `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` 编译到 iPhone App。`Info.plist` 同时声明现代 `UILaunchScreen`，避免 iPhone 以 320 × 480 兼容模式运行而造成编辑器非全屏。

## 当前色彩假设与限制

Phase 6 使用 Extended Linear sRGB + half-float Core Image working space；SDR preview/export 明确输出 sRGB，而检测到真实 HDR 内容时可使用 EDR preview 和 10-bit HEIF Rec.2100 HLG 导出。为避免静默裁切高光，当前 HDR 照片仅允许 identity/基础安全链：HSL、曲线和所有 Color Cube LUT 都会明确禁用，直到具备经过验证的 extended-range 实现。每个 LUT 都必须声明类型、原色/色域和传递函数；Technical LUT 必须与实际源编码精确匹配，且当前仅支持输入与输出 encoding 完全相同的 LUT（例如 sRGB → sRGB、Rec.709 → Rec.709），不执行跨编码转换。S-Log3/S-Gamut3(.Cine)、LogC、PQ、HLG Technical conversion 等尚未实现且会被拒绝。RAW 的零色温/色调是相对相机 as-shot 白平衡的零增量，不会强制 6500 K；新 RAW 状态未触碰的 NR、锐化、细节、局部色调和镜头校正也会保留 CIRAWFilter decoder 默认值。旧版本 RAW JSON 中已存的数值无法区分 UI 默认值与手动设置，因此为保留已有编辑结果会迁移为显式覆盖。详见 [color-management.md](docs/color-management.md)、[hdr-workflow.md](docs/hdr-workflow.md)、[local-adjustments.md](docs/local-adjustments.md) 与 [real-world-validation.md](docs/real-world-validation.md)。

导出保留可由 ImageIO 直接写回的源元数据；实际 Photos 权限、HEIF 编码、真机色彩/GPU 结果需要在真实设备验证。

视频仅支持 SDR：从 Files 导入视频后可调整曝光、对比度、饱和度和已声明 sRGB → sRGB 的 Creative LUT，并导出 MP4/MOV。视频使用独立 AVFoundation/Core Image/Metal 组合，HDR HLG/PQ 视频不会被当作 SDR 静默处理。详见 [video-workflow.md](docs/video-workflow.md)。
