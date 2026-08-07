# Image pipeline

## Preview

```text
immutable original CIImage (EXIF orientation applied at load)
→ downsample source to at most 2048 px long edge
→ exposure
→ highlights / shadows
→ contrast + saturation
→ temperature / tint
→ vibrance
→ optional LUT and 0…100% alpha blend
→ sharpness
→ vignette
→ rotation / horizontal flip / non-destructive crop
→ sRGB CGImage for SwiftUI
```

Preview 从源 CIImage 先缩小，再经过同一条编辑链；不会在每次 Slider 变化时完整解码 24MP/48MP 原图。所有渲染都由 `ImagePipeline` 的单一 Metal-backed `CIContext` 完成。

## Export

```text
immutable original CIImage at full resolution
→ same adjustments, LUT and transform order
→ optional requested output resize
→ JPEG or HEIF encoding + copied ImageIO metadata
```

导出绝不放大 Preview。调整完成后才按用户选定最大长边缩放，`nil` 表示原始分辨率。导出始终写新文件，原照片不会被覆盖。

## Phase 1 color assumption

Phase 1 使用 sRGB Core Image working/output space，面向 SDR 输入和 Creative LUT。`.cube` 本身未可靠表达色彩空间，所以导入 LUT 假定输入/输出均为 sRGB。这是明确限制，而非对 Technical LUT 的隐式猜测；Phase 5 会在 Source → Working → Technical → Creative → Output 颜色链中取代它。
