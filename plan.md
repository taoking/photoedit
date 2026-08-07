# iOS Photo Editor / LUT App — Development Plan

## 1. 产品定位

开发一个面向个人日常使用的原生 iOS 照片编辑应用，重点解决：

- 基础照片调色
- `.cube` 3D LUT 导入与套用
- LUT 强度调整
- 高性能实时预览
- 非破坏性编辑
- 全分辨率导出
- 后续逐步增加 HSL、曲线、RAW、预设、批量处理以及更完整的色彩管理能力

产品不以第一版复制 Lightroom / Darkroom / VSCO 全部功能为目标。

优先级始终是：

1. 图像处理正确
2. 色彩结果可靠
3. 操作流畅
4. 架构可扩展
5. UI 简洁
6. 再增加高级功能

主要面向 iPhone，使用 SwiftUI + Core Image 构建原生应用。

---

# 2. 总体技术原则

优先采用 Apple 原生技术：

- Swift
- SwiftUI
- Core Image
- Metal-backed `CIContext`
- PhotosUI / PhotosPicker
- PhotoKit
- ImageIO
- UniformTypeIdentifiers
- Core Graphics
- Swift Concurrency

原则：

- 第一阶段不自研 Metal Shader
- 第一阶段不引入大型第三方图像处理框架
- Preview 与 Export 必须分离
- 所有编辑参数采用非破坏性状态保存
- UI 不直接操作 CIFilter
- CIContext 长生命周期复用
- 高分辨率处理不得阻塞 MainActor
- 原图永远不被覆盖
- 对色彩空间、LUT 输入空间和输出空间保持明确假设
- 为 RAW / HDR / Technical LUT 留出扩展空间

---

# 3. 推荐整体架构

```text
SwiftUI UI
    ↓
EditorViewModel / EditorSession
    ↓
EditState
    ↓
ImagePipeline
    ├── PreviewRenderer
    └── ExportRenderer
    ↓
Core Image
    ↓
CIContext / Metal
```

辅助模块：

```text
Core/
├── Imaging/
├── Editing/
├── LUT/
├── Color/
├── RAW/
├── Presets/
└── Export/

Features/
├── Library/
├── Editor/
├── Adjust/
├── LUTLibrary/
├── Crop/
├── Presets/
├── Batch/
└── Export/
```

---

# 4. 编辑状态模型

所有调整都保存为参数，而不是修改源图。

建议逐步演化为：

```swift
struct EditState: Codable, Equatable {
    var light: LightAdjustments
    var color: ColorAdjustments
    var hsl: HSLAdjustments
    var curve: CurveAdjustments
    var detail: DetailAdjustments
    var effects: EffectAdjustments

    var selectedLUTID: UUID?
    var lutIntensity: Double

    var crop: CropState
    var rotation: Int
    var horizontalFlip: Bool

    var raw: RAWAdjustments?
}
```

Phase 1 可以只实现已有字段，后续逐步扩展。

必须支持：

- reset
- copy
- serialization
- preset 保存
- future migration

---

# 5. 图像处理流水线

## Preview

```text
Original
→ Orientation Normalize
→ Downsample Preview Source
→ Adjustments
→ LUT
→ Detail / Effects
→ Crop
→ Screen Preview
```

建议 Preview 最长边约：

- 2048 px
- 或根据设备动态调整到 2560 px

禁止 Slider 每次变化都重新解码完整 24MP / 48MP 原图。

---

## Export

```text
Original Full Resolution
→ Orientation Normalize
→ Same EditState
→ Full Resolution Pipeline
→ Crop
→ Encode
→ Photos / Files
```

严禁把 Preview 图片放大后作为最终导出。

---

# 6. Phase 1 — 可用 MVP

## 目标

得到一个真正可以日常使用的基础照片调色 + LUT App。

不是 Demo。

---

## 6.1 图片导入

支持：

- PhotosPicker
- Files

格式：

- JPEG
- HEIC / HEIF
- PNG

处理：

- EXIF Orientation
- Color Space
- Pixel Size
- Metadata

---

## 6.2 基础调色

### Light

- Exposure
- Contrast
- Highlights
- Shadows

### Color

- Temperature
- Tint
- Saturation
- Vibrance

### Detail

- Sharpness

### Effects

- Vignette

---

## 6.3 LUT

第一阶段核心。

支持：

- `.cube`
- 17×17×17
- 33×33×33
- 65×65×65

解析：

- TITLE
- LUT_3D_SIZE
- DOMAIN_MIN
- DOMAIN_MAX
- RGB values
- comments
- blank lines

功能：

- LUT 导入
- LUT 删除
- LUT 重命名
- LUT 收藏
- Built-in / Imported 分类
- LUT thumbnail
- LUT preview cache
- LUT 0–100% 强度

必须提供 Identity LUT 测试。

---

## 6.4 编辑交互

支持：

- Before / After
- Reset
- Undo 基础能力
- Pinch Zoom
- 图片拖动
- Slider 实时调整

快速拖动 Slider 时：

- 旧任务可以取消
- 或忽略过期结果
- 禁止旧 render 覆盖新 render

---

## 6.5 Crop

支持：

- Free
- Original
- 1:1
- 4:3
- 3:2
- 16:9
- Rotate 90°
- Horizontal Flip

---

## 6.6 Export

格式：

- JPEG
- HEIF

支持：

- Original Resolution
- Resize
- JPEG Quality
- Save to Photos
- Share
- Save to Files

默认：

- Original Resolution
- JPEG 90%

不得覆盖原照片。

---

## 6.7 Phase 1 验收

必须真实验证：

1. 选择一张 24MP HEIC
2. 调曝光、色温、饱和度
3. Preview 无明显卡顿
4. 导入 33 `.cube`
5. LUT 正确显示
6. LUT 强度 0–100% 可调
7. Before / After 正常
8. Crop 正常
9. Original Resolution Export 正常
10. 原照片未修改
11. 关闭 App 后 LUT 仍存在
12. Identity LUT 前后结果基本一致
13. Build 无 compiler error
14. 无明显 concurrency warning
15. 大照片不会产生异常内存峰值

---

# 7. Phase 2 — 完整照片调色能力

Phase 2 的目标是让应用从“LUT 工具”升级为“轻量专业照片调色工具”。

---

## 7.1 HSL / Color Mixer

支持至少：

- Red
- Orange
- Yellow
- Green
- Aqua
- Blue
- Purple
- Magenta

每个颜色：

- Hue
- Saturation
- Luminance

UI：

```text
Color Mixer
Red       H S L
Orange    H S L
...
```

要求：

- 参数进入 EditState
- 可以 Reset 单色
- 可以 Reset 整个 HSL
- 不允许写死在 View 中

实现方式优先评估：

1. Core Image 原生组合
2. CIColorKernel
3. Metal Shader

如果 Core Image 原生组合无法正确实现，再进入自定义 kernel。

---

## 7.2 RGB / Tone Curve

增加：

- Master Curve
- Red Curve
- Green Curve
- Blue Curve

要求：

- 可增加控制点
- 可移动控制点
- 不允许 X 坐标交叉
- 可删除非端点
- 一键 Reset

Curve 参数必须序列化。

---

## 7.3 Histogram

增加实时 Histogram：

- RGB
- Luminance

Histogram 基于 Preview Source 计算。

禁止对每一次 Slider 变化都使用全分辨率图片计算 Histogram。

允许节流更新。

---

## 7.4 Preset

增加预设系统。

Preset 保存：

- Light
- Color
- HSL
- Curve
- Detail
- Effects
- LUT
- LUT Intensity

默认不保存：

- Crop
- Rotation

除非用户主动选择。

功能：

- Create Preset
- Rename
- Delete
- Favorite
- Import / Export preset

Preset 建议使用 Codable JSON。

---

## 7.5 Copy / Paste Adjustments

支持：

- Copy All
- Paste All
- Selective Paste

Selective Paste：

- Light
- Color
- HSL
- Curve
- LUT
- Detail
- Effects
- Crop

---

# 8. Phase 3 — RAW 与专业摄影工作流

目标：

支持 Sony A7C II 等相机 RAW 文件，以及更适合相机照片的工作流。

---

## 8.1 RAW

优先支持：

- DNG
- Sony ARW

基于：

- CIRAWFilter
- Core Image RAW pipeline

需要支持或评估：

- Exposure
- Temperature
- Tint
- Noise Reduction
- Sharpness
- Detail
- Local Tone
- Lens Correction

RAW 调整与普通 JPEG 调整分层：

```text
RAW Decode
→ RAW Adjustments
→ Standard Editing Pipeline
→ LUT
→ Export
```

不能把 RAW 参数和普通图片参数混成同一层。

---

## 8.2 RAW Preview Strategy

RAW 打开时：

- 优先快速生成 Preview
- 后台准备更高质量预览
- Export 时重新执行 Full RAW Decode

不能为了第一次打开图片就直接做全分辨率完整 RAW Render。

---

## 8.3 Camera Metadata

显示：

- Camera
- Lens
- Aperture
- Shutter
- ISO
- Focal Length
- Capture Date

---

# 9. Phase 4 — 批量与照片工作流

目标：

提升大量旅行照片处理效率。

---

## 9.1 Batch Apply

支持一次选择多张图片。

可执行：

- Apply Preset
- Apply LUT
- Copy Adjustments
- Export Batch

要求：

- 有任务队列
- 有取消
- 有进度
- 单张失败不应导致整个 Batch 崩溃

---

## 9.2 Recent Settings

记录：

- Recent LUT
- Recent Preset
- Recent Export Setting

方便大量相似照片连续处理。

---

## 9.3 Reference Photo

编辑时允许暂时加载一张 Reference Photo：

- 左右切换
- 或 Split View

用于统一一组旅行照片色调。

---

## 9.4 Batch Export

支持：

- JPEG
- HEIF
- Resize
- Quality
- Filename strategy

不得一次把所有全分辨率图像加载进内存。

必须顺序或受控并行处理。

---

# 10. Phase 5 — 色彩科学与 Technical LUT

这一阶段解决 Creative LUT 与 Camera Technical LUT 混用的问题。

---

## 10.1 LUT 类型

区分：

### Creative LUT

例如：

- Film Look
- Fuji-like Look
- Cinematic
- Warm
- Cool

### Technical LUT

例如：

- S-Log3 → Rec.709
- HLG → Rec.709
- Log → Display P3

---

## 10.2 LUT Metadata

LUT 增加：

```swift
enum LUTKind {
    case creative
    case technical
}

struct LUTColorMetadata {
    var inputColorSpace: ColorSpaceDescriptor?
    var outputColorSpace: ColorSpaceDescriptor?
}
```

不允许默认认为所有 LUT 都接受 sRGB。

---

## 10.3 Color Management

系统性处理：

- sRGB
- Display P3
- Linear RGB
- Rec.709
- Extended Linear
- HDR input

明确：

```text
Source Color Space
→ Working Color Space
→ Technical Transform
→ Creative Adjustments
→ Output Color Space
```

并写入文档。

---

# 11. Phase 6 — HDR / 高级显示

根据实际需求再开发。

考虑：

- HDR HEIF
- Extended Dynamic Range
- HDR Preview
- SDR Export
- HDR Export
- Tone Mapping

必须先解决 Phase 5 色彩管理，再进入 HDR。

---

# 12. Phase 7 — 局部调整

只有前面的基础能力稳定后再进入。

候选：

- Linear Gradient
- Radial Gradient
- Brush Mask
- Subject Mask
- Sky Mask

优先：

1. 手动 Gradient
2. Brush
3. Vision / Core ML 自动蒙版

AI 不作为早期阶段优先级。

---

# 13. Phase 8 — 视频 LUT（可选）

只有照片功能成熟后再考虑。

支持：

- 视频导入
- LUT Preview
- LUT Strength
- Basic Color Adjustments
- Video Export

技术方向：

- AVFoundation
- Core Image video composition
- Metal

不要让 Phase 1 的静态图片架构强行承担视频 pipeline。

可以共用：

- LUT parser
- adjustment models
- color management model

但渲染 pipeline 应独立。

---

# 14. 明确不做或低优先级

个人使用项目，不优先考虑：

- 登录
- 账号
- 云同步
- 订阅
- 广告
- 社区
- 社交
- 在线模板商城
- 后端
- Web 管理后台
- 企业级权限系统

---

# 15. 开发顺序

推荐：

```text
Phase 1
MVP
↓
Phase 2
HSL / Curve / Histogram / Preset
↓
Phase 3
RAW
↓
Phase 4
Batch Workflow
↓
Phase 5
Color Management / Technical LUT
↓
Phase 6
HDR
↓
Phase 7
Local Masks
↓
Phase 8
Video LUT
```

其中最有实际使用价值的前三个里程碑：

### Milestone A

基础调色 + LUT + Export

### Milestone B

HSL + Curve + Preset + Histogram

### Milestone C

RAW + Batch

完成 Milestone C 后，已经可以作为一个成熟的个人旅行摄影调色 App 长期使用。

---

# 16. 开发策略

每一个 Phase 必须：

1. 先检查当前代码
2. 明确本 Phase scope
3. 实现
4. 写测试
5. Build
6. 真机/模拟器验证可验证项目
7. 更新 docs
8. 总结已知限制
9. 再进入下一 Phase

禁止：

- Phase 1 尚未稳定就堆 Phase 5 功能
- 为未来假想需求过度设计
- 一次引入多个大型图像框架
- 只写 UI，不验证图像结果
- 只看编译通过，不验证 LUT 与导出结果

---

# 17. 性能基准

后续测试图片至少覆盖：

- 12MP
- 24MP
- 48MP
- HEIC
- JPEG
- RAW

关注：

- 打开耗时
- Preview render latency
- Slider latency
- LUT switching latency
- Peak memory
- Export duration
- Export correctness

不要为了 benchmark 做过度优化。

重点是个人真实设备上的体验。

---

# 18. 项目完成标准

本项目长期目标不是功能数量，而是：

- 照片处理结果可靠
- LUT 不偏色、不乱序
- 调色可重复
- Preview 与 Export 基本一致
- 高分辨率照片不会轻易 OOM
- RAW 工作流可靠
- Preset / Batch 真正提高效率
- 色彩管理假设有明确文档
- 项目代码长期可维护

---

# 19. 执行状态

阶段执行、测试、构建、人工验证项与提交记录维护在 `docs/development-progress.md`。本计划保留为产品路线图，开发时按 Phase 1 至 Phase 8 的顺序更新该进度记录。

当前执行状态：

- [x] Phase 1 — 基础调色、LUT、Crop、全分辨率导出
- [x] Phase 2 — HSL / Curve / Histogram / Preset / Copy-Paste
- [x] Phase 3 — RAW 工作流
- [ ] Phase 4 — 批量工作流
- [ ] Phase 5 — 色彩管理与 Technical LUT
- [ ] Phase 6 — HDR
- [ ] Phase 7 — 局部调整
- [ ] Phase 8 — 视频 LUT
