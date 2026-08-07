# Codex Development Prompt — iOS Photo Editor / LUT App

## 项目背景

开发一个原生 iOS 照片编辑、调色和 LUT App。

这是一个个人长期使用的软件，重点服务于日常旅行摄影、相机照片调色和 `.cube` LUT 套用。

不要把项目做成 Web App，也不要通过浏览器连接本地端口使用。

目标是一个真正的原生 iOS 应用。

请同时阅读仓库中的：

```text
plan.md
```

`plan.md` 是整个项目的长期路线图。

本轮开发以 **Phase 1** 为主，但架构必须明确兼容紧随其后的 Phase 2：

- HSL / Color Mixer
- RGB / Tone Curve
- Histogram
- Preset
- Copy / Paste Adjustments

不要提前大量实现后续 Phase，但禁止把 Phase 1 写成后续无法扩展的临时代码。

---

# 1. 开始前

先执行：

```bash
git status
git log --oneline -10
```

检查：

- 当前分支
- 当前已有实现
- 是否有未提交修改
- 项目结构
- Deployment Target
- Swift / Xcode 配置

如果仓库已经存在代码：

- 优先复用现有实现
- 不要无理由重建项目
- 不要删除有效功能
- 不要覆盖用户已有改动

如果仓库为空，则建立合理的原生 SwiftUI iOS 工程结构。

---

# 2. 技术栈

优先：

- Swift
- SwiftUI
- Core Image
- Metal-backed CIContext
- PhotosUI
- PhotoKit
- ImageIO
- UniformTypeIdentifiers
- Swift Concurrency

避免第三方依赖。

本阶段不要引入：

- OpenCV
- Flutter
- React Native
- WebView
- localhost web server
- Firebase
- 后端
- 大型 DI framework
- Redux
- 企业级 Clean Architecture protocol 套娃

如 Core Image 已足够解决问题，不要自己写 Metal Shader。

---

# 3. 当前阶段目标

完成：

```text
照片导入
→ 基础调色
→ .cube LUT
→ LUT 强度
→ Crop
→ Before / After
→ 全分辨率 Export
```

这是本轮 P0。

完成后 App 必须能真实拿来调一张照片，而不是只做 UI Demo。

---

# 4. Phase 1 功能

## 4.1 Image Import

实现：

- PhotosPicker
- Files Import

支持：

- JPEG
- HEIC / HEIF
- PNG

正确处理：

- EXIF orientation
- pixel width / height
- color space
- metadata

原图必须保持不变。

---

# 5. 非破坏性 EditState

建立统一 EditState。

第一阶段至少：

```swift
struct EditState: Codable, Equatable {
    var exposure: Double
    var contrast: Double
    var highlights: Double
    var shadows: Double

    var temperature: Double
    var tint: Double
    var saturation: Double
    var vibrance: Double

    var sharpness: Double
    var vignette: Double

    var selectedLUTID: UUID?
    var lutIntensity: Double

    var crop: CropState
    var rotation: Int
    var horizontalFlip: Bool
}
```

要求：

- reset
- clone/copy
- Codable
- Equatable

不要把：

- CIFilter
- CIImage
- UIImage

直接存入 EditState。

---

# 6. 为 Phase 2 提前预留 EditState 扩展

Phase 2 会增加：

```text
HSL
Tone Curve
Histogram
Presets
Copy / Paste
```

因此建议从现在开始把 EditState 结构组织为可扩展的子模型，例如：

```swift
struct EditState {
    var light: LightAdjustments
    var color: ColorAdjustments
    var detail: DetailAdjustments
    var effects: EffectAdjustments

    var lut: LUTAdjustment
    var transform: TransformAdjustment
}
```

但不要为了未来做过度抽象。

目标只是避免：

```text
EditorView.swift
```

以后变成一个包含几十个 Double 和 CIFilter 的巨大文件。

---

# 7. 基础调色

实现：

## Light

- Exposure
- Contrast
- Highlights
- Shadows

## Color

- Temperature
- Tint
- Saturation
- Vibrance

## Detail

- Sharpness

## Effects

- Vignette

UI 数值和 CIFilter 参数通过：

```text
AdjustmentMapper
```

映射。

不要直接把 Slider `-100...100` 作为 CIFilter 输入。

---

# 8. ImagePipeline

建立核心：

```text
Core/
    Imaging/
        ImagePipeline.swift
        ImageLoader.swift
        PreviewRenderer.swift
        ExportRenderer.swift
```

接口可以参考：

```swift
func render(
    image: CIImage,
    state: EditState,
    mode: RenderMode
) async throws -> RenderedImage
```

```swift
enum RenderMode {
    case preview
    case export
}
```

SwiftUI View 不允许直接构造完整滤镜链。

---

# 9. 建议 Pipeline 顺序

```text
Input
↓
Orientation Normalization
↓
Exposure
↓
Highlights / Shadows
↓
Contrast
↓
Temperature / Tint
↓
Saturation
↓
Vibrance
↓
LUT
↓
Sharpness
↓
Vignette
↓
Crop / Rotation
↓
Output
```

如果存在更合理实现，可以调整。

但是最终 pipeline 顺序必须：

- 明确
- 集中管理
- 写入 docs/image-pipeline.md

---

# 10. CIContext

创建长生命周期：

```text
Metal-backed CIContext
```

优先使用系统默认 Metal Device。

不要：

- 每次 slider 修改创建 CIContext
- 每次 render 创建新的 GPU context

需要考虑：

- Swift Concurrency
- task cancellation
- stale render result

---

# 11. Preview Pipeline

Preview 和 Export 必须严格分开。

Preview：

```text
Original
→ Downsample
→ Preview CIImage
→ Adjustments
→ Screen
```

建议最长边：

```text
2048 ~ 2560 px
```

不要 Slider 每变化一次就处理 24MP / 48MP 全图。

---

# 12. Slider Render Scheduling

用户快速拖动：

```text
Exposure
Temperature
LUT Intensity
```

时，不允许不断堆积 render task。

实现至少一种：

- Task cancellation
- render generation ID
- debounce / coalescing

要求：

旧 render 不能覆盖新的 EditState。

---

# 13. LUT 系统

建立：

```text
Core/
    LUT/
        LUT.swift
        CUBEParser.swift
        LUTProcessor.swift
        LUTRepository.swift
        LUTPreviewCache.swift
```

支持标准 `.cube` 3D LUT。

至少支持：

- 17
- 33
- 65

解析：

```text
TITLE
LUT_3D_SIZE
DOMAIN_MIN
DOMAIN_MAX
R G B
```

忽略：

- comments
- blank lines

---

# 14. LUT Model

例如：

```swift
struct LUT: Identifiable {
    let id: UUID
    let name: String
    let dimension: Int

    let domainMin: SIMD3<Float>
    let domainMax: SIMD3<Float>

    let values: [SIMD3<Float>]
}
```

必须验证：

```text
values.count == dimension³
```

---

# 15. CUBE Parser Error

实现明确错误。

例如：

```swift
enum CUBEParserError: Error {
    case missingDimension
    case invalidDimension
    case invalidValue
    case incorrectValueCount
    case unsupportedFormat
}
```

坏 `.cube` 文件：

- 给用户正常错误提示
- 不得 crash

---

# 16. LUT Render

将 LUT 转为 Core Image Color Cube 所需：

```text
RGBA Float Data
```

使用：

```text
CIColorCubeWithColorSpace
```

或当前平台等价 API。

务必确认：

- RGB traversal order
- cube dimension
- float layout
- alpha = 1
- color space

不要猜顺序。

---

# 17. Identity LUT Test

必须提供：

```text
Identity17.cube
Identity33.cube
```

或者测试代码动态生成。

测试：

```text
Input → Identity LUT
```

输出必须与输入基本一致。

如果 Identity LUT 失败，优先修正 LUT pipeline，不要继续堆新功能。

---

# 18. LUT Intensity

支持：

```text
0...100%
```

语义：

```text
0%   = 调色后但未套 LUT
100% = 完整 LUT
```

通过：

```text
base image
+
lut image
+
blend
```

实现。

不要为了强度反复重建 LUT cube。

---

# 19. LUT Library

界面至少：

```text
None
Built-in
Imported
Favorites
```

支持：

- Import
- Rename
- Delete imported LUT
- Favorite
- Select

Built-in LUT 不可删除。

---

# 20. LUT Persistence

`.cube` Import 后复制到：

```text
Application Support/
    LUTs/
        imported/
```

不能长期依赖 fileImporter 临时 URL。

metadata 可使用：

- Codable JSON

第一阶段不需要数据库。

---

# 21. LUT Thumbnail

每个 LUT 可显示当前照片的小缩略图效果。

只用：

```text
256 / 512 px
```

处理。

建立缓存。

禁止打开 LUT 页面后同时对几十个 LUT 做全分辨率 render。

---

# 22. Before / After

实现：

按住：

```text
Before
```

显示原图。

松开恢复当前编辑结果。

要求：

- 快速
- 不重新解码原图
- 不改变 EditState

---

# 23. Crop

实现：

- Free
- Original
- 1:1
- 4:3
- 3:2
- 16:9
- Rotate 90°
- Horizontal Flip

Crop 必须非破坏性保存于 EditState。

---

# 24. Export Pipeline

Export：

```text
Original Full Resolution
→ Same EditState
→ Full-resolution render
→ Encode
```

禁止：

```text
Preview → Upscale → Export
```

---

# 25. Export UI

格式：

- JPEG
- HEIF

Size：

- Original
- Resize

Quality：

- JPEG 80
- JPEG 90
- JPEG 100

默认：

```text
Original
JPEG 90%
```

支持：

- Save to Photos
- Share
- Save to Files

永远创建新文件 / 新 Asset。

禁止覆盖原图。

---

# 26. Metadata

尽量保留：

- capture date
- camera
- lens
- EXIF

GPS：

如果实现方便，增加：

```text
Keep Location
```

开关。

如果第一版无法完整保留 metadata：

在 docs 中准确说明。

不要声称全部保留。

---

# 27. Error Handling

建立统一错误：

```swift
enum ImageEditorError: Error {
    case imageLoadFailed
    case unsupportedFormat
    case invalidLUT
    case renderFailed
    case exportFailed
    case permissionDenied
}
```

用户看到：

- 简洁错误信息

开发 log：

- technical details

---

# 28. Swift Concurrency

高成本任务不能放 MainActor：

- decode
- LUT thumbnail
- image render
- full export

UI state 更新正确回 MainActor。

重点检查：

- actor isolation
- Sendable
- cancellation
- stale state

---

# 29. 内存

避免这种链：

```text
Data
→ UIImage
→ CGImage
→ CIImage
→ UIImage
→ PNG
→ UIImage
```

尽量长期保持：

```text
CIImage
```

到最终展示/导出边界。

新打开图片后：

释放上一张不需要的大对象。

---

# 30. UI

目标是简洁、可日常使用，不做复杂炫技 UI。

建议：

```text
Editor

Top:
Back
Undo / Reset
Before
Export

Center:
Image

Bottom:
Adjust
LUT
Crop
```

Adjust 内：

```text
Light
Color
Detail
Effects
```

---

# 31. Phase 2 — 下一阶段明确需求

虽然本轮主要完成 Phase 1，但下面这些是紧接着要开发的功能。

架构必须预留。

---

## 31.1 HSL / Color Mixer

支持：

- Red
- Orange
- Yellow
- Green
- Aqua
- Blue
- Purple
- Magenta

每色：

- Hue
- Saturation
- Luminance

不要现在写假的 HSL Slider。

如果准备实现 Phase 2 时 Core Image 原生无法正确满足，评估：

- CIColorKernel
- Metal

---

## 31.2 Tone Curve

支持：

- Master RGB
- Red
- Green
- Blue

控制点：

- Add
- Move
- Delete
- Reset

数据必须 Codable。

---

## 31.3 Histogram

支持：

- RGB
- Luminance

基于 Preview Source。

允许 throttling。

不要使用 Full Resolution 每帧计算。

---

## 31.4 Presets

支持：

- Create
- Apply
- Rename
- Delete
- Favorite
- Import / Export

Preset 包括：

- Light
- Color
- HSL
- Curves
- LUT
- LUT Intensity
- Detail
- Effects

默认不包括 Crop。

---

## 31.5 Copy / Paste Adjustments

支持：

- Copy All
- Paste All
- Selective Paste

所以 Phase 1 的 EditState 必须设计成可复制、可序列化、分组明确。

---

# 32. 后续阶段兼容要求

后面还会开发：

```text
RAW / ARW / DNG
Batch Editing
Technical LUT
S-Log3
HLG
Rec.709
Display P3
HDR
Local Masks
Video LUT
```

不要现在实现。

但是：

LUT 不要设计成只能接受 sRGB 的硬编码模型。

以后需要加入：

```swift
enum LUTKind {
    case creative
    case technical
}
```

以及 input/output color metadata。

当前 Phase 1 可以默认：

```text
Standard SDR image + Creative LUT
```

并在文档中写清楚这个假设。

---

# 33. Tests

至少增加：

## CUBEParser

- identity 17
- identity 33
- TITLE
- comments
- blank lines
- DOMAIN_MIN
- DOMAIN_MAX
- invalid dimension
- malformed float
- insufficient values
- excess values

## EditState

- reset
- Codable
- equality

## AdjustmentMapper

检查参数映射。

## Pipeline

至少有基础 smoke test。

## LUT

Identity LUT correctness。

---

# 34. 文档

生成 / 更新：

```text
README.md
plan.md
docs/architecture.md
docs/image-pipeline.md
docs/lut-format.md
```

README：

- 项目目标
- 功能
- Build
- 当前限制

architecture：

- 模块
- 数据流
- concurrency

image-pipeline：

- Preview Pipeline
- Export Pipeline
- Filter order
- color space assumption

lut-format：

- parser
- supported size
- data order
- color space assumption
- limitations

---

# 35. 项目结构参考

```text
App/
Features/
    Editor/
    Adjust/
    LUTLibrary/
    Crop/
    Export/

Core/
    Imaging/
    Editing/
    LUT/
    Color/

Services/
    PhotoLibrary/
    FileImport/
    Export/

Tests/
```

允许根据现有项目结构调整。

不要为了匹配目录模板强行移动所有已有代码。

---

# 36. 不要做

本轮不要开发：

- RAW
- AI mask
- batch
- cloud
- account
- backend
- video
- subscription
- social
- HSL fake implementation
- HDR

不要花大量时间：

- splash screen
- 动画
- icon
- marketing UI

P0 image pipeline 没稳定之前，不做这些。

---

# 37. P0

必须完成：

1. Import image
2. EditState
3. ImagePipeline
4. Metal-backed CIContext
5. Preview render
6. Light / Color adjustments
7. CUBE parser
8. LUT render
9. LUT intensity
10. full-resolution export

---

# 38. P1

在 P0 稳定后：

- LUT library
- LUT persistence
- LUT thumbnails
- Before / After
- Crop
- metadata
- better error UI

---

# 39. P2

最后：

- UI polish
- animation
- additional built-in LUTs

---

# 40. 性能验证

测试：

- 12MP
- 24MP
- 48MP

至少观察：

- Preview responsiveness
- rapid slider drag
- LUT switching
- peak memory
- full resolution export

如果无法提供精确 benchmark，也必须说明人工验证方法和观察结果。

---

# 41. Build

开发完成后必须实际执行 Build。

修复：

- compile errors
- warnings
- concurrency errors
- obvious runtime problems

如果可运行 simulator tests：

执行。

如果某些 PhotoKit / Metal 行为只能真机验证：

明确列出来。

---

# 42. Git

不要提交：

- DerivedData
- build
- personal photos
- large test photos
- secrets
- API keys
- temporary files

结束前：

```bash
git status
git diff --stat
```

检查修改范围。

---

# 43. 最终报告

完成后输出：

## Implementation

实现了什么。

## Architecture

核心架构。

## Image Pipeline

Preview / Export。

## LUT

Parser / renderer / intensity。

## Performance

采取了哪些性能措施。

## Tests

测试结果。

## Build

Build 结果。

## Known Issues

当前已知限制。

## Phase 2 Readiness

说明：

- HSL
- Curve
- Histogram
- Preset
- Copy/Paste

接下来从哪些模块继续开发。

---

# 44. 验收场景

必须至少覆盖：

### Scenario 1

```text
Photos
→ Select HEIC
→ Exposure
→ Temperature
→ Saturation
```

实时显示。

### Scenario 2

```text
Files
→ Import 33.cube
→ Apply LUT
→ intensity 0%
→ intensity 50%
→ intensity 100%
```

结果正确。

### Scenario 3

```text
Before press
→ Original
→ Release
→ Edited
```

### Scenario 4

```text
Crop 3:2
→ Rotate
→ Export Original Resolution
→ JPEG 90
→ Photos
```

成功。

### Scenario 5

退出重开：

Imported LUT 仍存在。

### Scenario 6

Identity LUT：

前后结果基本一致。

---

# 45. 开发原则

这个项目是个人长期使用工具。

宁可：

- 少几个功能
- 但图像结果正确
- pipeline 清晰
- 性能稳定

不要：

- 功能很多
- 但 Preview 和 Export 不一致
- LUT 顺序错误
- 高分辨率图片频繁 OOM
- 所有逻辑塞进 SwiftUI View

本轮最终目标：

**得到一个能够稳定导入相机/手机照片、进行基础调色、导入和套用 `.cube` LUT、实时预览，并以原始分辨率可靠导出的 iOS App。**
