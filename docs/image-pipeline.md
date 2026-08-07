# Image pipeline

## Preview

```text
immutable original CIImage (EXIF orientation applied at load)
→ Core Image source-to-linear-sRGB working-space handling
→ downsample source to at most 2048 px long edge
→ optional 100% Technical LUT
→ exposure
→ highlights / shadows
→ contrast + saturation
→ temperature / tint
→ vibrance
→ eight-channel HSL mixer
→ master / red / green / blue tone curves
→ optional Creative LUT and 0…100% alpha blend
→ sharpness
→ vignette
→ rotation / horizontal flip / non-destructive crop
→ Core Image linear-working-to-sRGB output handling
→ sRGB CGImage for SwiftUI
```

Preview 从源 CIImage 先缩小，再经过同一条编辑链；不会在每次 Slider 变化时完整解码 24MP/48MP 原图。所有渲染都由 `ImagePipeline` 的单一 Metal-backed `CIContext` 完成。

## Export

```text
immutable original CIImage at full resolution
→ same Technical LUT, adjustments, Creative LUT and transform order
→ optional requested output resize
→ JPEG or HEIF encoding + copied ImageIO metadata
```

导出绝不放大 Preview。调整完成后才按用户选定最大长边缩放，`nil` 表示原始分辨率。导出始终写新文件，原照片不会被覆盖。

## Phase 5 color management

`ImagePipeline` 的单一 `CIContext` 以线性 sRGB 为工作空间、以 sRGB 为 SDR 输出空间；嵌入 profile 的 ImageIO 图像交由 Core Image 进行色彩处理，无 profile 的标准照片在读取时显式附着 sRGB。渲染顺序为 Source → Working → Technical → Creative Adjustments → Creative LUT → Output。`.cube` 不可靠地携带色彩空间信息，故导入时不再默认 sRGB；LUT 必须由用户声明种类和输入/输出色彩空间后才可使用。完整约定和 HDR 边界见 [color-management.md](color-management.md)。
