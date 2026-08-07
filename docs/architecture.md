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

`EditState` 是纯值类型，并按 light、color、detail、effects、lut、localAdjustments、transform 分组。它不含 `CIImage`、`UIImage`、滤镜或可变全局状态，因此支持复制、JSON 序列化、撤销以及后续的预设和选择性粘贴。新增字段通过 `decodeIfPresent` 回退到默认值，历史预设不会因缺失局部蒙版字段而失效。

Phase 2 扩展了 `hsl` 与 `curves` 两个可编码子模型。HSL 通过一个按 Hue/Saturation 软选择的 `CIColorKernel` 顺序处理八个色相区；Core Image 没有可正确表达八色独立 H/S/L 的内置组合。曲线模型保存任意数量的有序点，并在渲染时采样为 64³ Core Image Color Cube；端点不可删除、内部点不会越过相邻 X 坐标。`CI_SILENCE_GL_DEPRECATION` 只用于抑制 Apple 已知的 Kernel Language API 标注，运行时仍由 Core Image 执行；若未来平台移除此 API，Phase 2 的处理器边界可替换为 Metal 实现。

直方图由 `ImagePipeline` 从最多 512px 长边的 Preview Source 读取 RGBA 像素，包含 RGB 与亮度各 256 bin。它在新图导入时经过节流后独立计算，不会在每一次 Slider 变化中读取全分辨率图像。

`ImagePipeline` 是 actor：渲染在 actor 的串行执行器中完成，`CIContext` 在应用生命周期内复用。ViewModel 给每一次预览分配 generation，同时取消上一项任务；过期结果无法回写 UI。导入解码和完整导出均从 UI 状态分离，只有预览/导出状态更新发生在 MainActor。

LUT 元数据与原始 `.cube` 文件分开保存：导入文件复制至 `Application Support/PhotoEdit/LUTs/imported`，目录元数据写入 `metadata.json`。内置 LUT 不可删除；导入 LUT 可重命名、收藏和删除。

预设采用 Codable JSON，保存 light/color/HSL/curve/detail/effects/LUT 与强度；除非创建时明确选择，否则不会写入 transform。`PresetRepository` 将库持久化到 `Application Support/PhotoEdit/Presets.json`，而 `AdjustmentClipboard` 保持应用内全部或分组选择性粘贴所需的值状态。

Phase 7 的 `LocalAdjustment` 是 `EditState` 的值类型子模型，每项持有一个线性、径向或画笔蒙版及独立参数；`LocalAdjustmentProcessor` 在图像层执行合成，View 只编辑模型。视频不会复用静态 `ImagePipeline`，而是在 Phase 8 使用独立 AVFoundation composition。
