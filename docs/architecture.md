# Architecture

PhotoEdit 保持单向数据流：SwiftUI `EditorView` 只绑定 `EditorViewModel`；ViewModel 保存可编码的 `EditState` 并调度 `ImagePipeline`；渲染器和导出器才接触 `CIImage`、`CIFilter` 与 `CIContext`。

```text
PhotosPicker / File importer
       ↓
ImageLoader → ImageAsset (immutable original bytes + metadata + CIImage)
       ↓
EditorViewModel → EditState → ImagePipeline actor → long-lived Metal CIContext
       ↓                                  ↓
SwiftUI preview                         ImageExporter / Photos / Files / Share
```

`EditState` 是纯值类型，并按 light、color、detail、effects、lut、transform 分组。它不含 `CIImage`、`UIImage`、滤镜或可变全局状态，因此支持复制、JSON 序列化、撤销以及后续的预设和选择性粘贴。

`ImagePipeline` 是 actor：渲染在 actor 的串行执行器中完成，`CIContext` 在应用生命周期内复用。ViewModel 给每一次预览分配 generation，同时取消上一项任务；过期结果无法回写 UI。导入解码和完整导出均从 UI 状态分离，只有预览/导出状态更新发生在 MainActor。

LUT 元数据与原始 `.cube` 文件分开保存：导入文件复制至 `Application Support/PhotoEdit/LUTs/imported`，目录元数据写入 `metadata.json`。内置 LUT 不可删除；导入 LUT 可重命名、收藏和删除。

后续 Phase 2 将向 `EditState` 加入 HSL、曲线与直方图，且不会将滤镜逻辑推回 View。RAW、批处理、色彩管理、HDR、蒙版和视频会在自己的输入/任务模型中接入现有状态与 LUT 模块。
