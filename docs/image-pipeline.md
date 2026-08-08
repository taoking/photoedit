# Image pipeline

## Preview

```text
immutable original CIImage (EXIF orientation applied at load)
→ Core Image source-to-extended-linear-sRGB working-space handling
→ downsample source to at most 2048 px long edge
→ optional 100% Technical LUT (SDR only; exact source-encoding match)
→ exposure
→ highlights / shadows
→ contrast + saturation
→ temperature / tint
→ vibrance
→ eight-channel HSL mixer (SDR only)
→ master / red / green / blue tone curves (SDR only)
→ local linear / radial / brush mask adjustments
→ optional Creative LUT and 0…100% alpha blend (SDR only)
→ sharpness
→ vignette
→ rotation / horizontal flip / non-destructive crop
→ HDR preview: half-float extended-linear output / SDR preview: tone map then sRGB output
→ SDR sRGB CGImage or HDR half-float CGImage for SwiftUI/UIKit
```

Preview 从源 CIImage 先缩小，再经过同一条编辑链；不会在每次 Slider 变化时完整解码 24MP/48MP 原图。所有渲染都由 `ImagePipeline` 的单一 Metal-backed `CIContext` 完成。

`ImageAsset` 保留不可变的原始 `Data` 与延迟计算的 `CIImage`；RAW source 共享同一 copy-on-write data backing，并在每次 preview/export 单独创建 `CIRAWFilter`，不会将 draft 解码结果复用于导出。Preview 不持有全分辨率 `CGImage`，局部画笔 mask 仅按当前 Preview/Export 尺寸栅格化；缓存的 preview mask 上限为约 16 MiB，超过上限的全分辨率 mask 不进入缓存。

## Export

```text
immutable original CIImage at full resolution
→ same Technical LUT, adjustments, Creative LUT and transform order
→ optional requested output resize
→ JPEG or HEIF encoding + sanitized ImageIO metadata
```

导出绝不放大 Preview。调整完成后才按用户选定最大长边缩放，`nil` 表示原始分辨率。导出始终写新文件，原照片不会被覆盖。由于方向、裁切、旋转和 resize 已烘焙进最终像素，metadata sanitizer 会写入 Orientation=1、实际 PixelWidth/PixelHeight、EXIF PixelX/YDimension 和 TIFF Orientation=1，移除旧 thumbnail；GPS 仍遵守用户保留/移除设置，其余合理的拍摄日期、相机、镜头、ISO、快门与光圈 metadata 会保留。

## Phase 5–6 color management

`ImagePipeline` 的单一 `CIContext` 以 Extended Linear sRGB + RGBA half-float 为工作空间；嵌入 profile 的 ImageIO 图像交由 Core Image 进行色彩处理，无 profile 的标准照片在读取时显式附着 sRGB。渲染顺序为 Source → Working → Technical → 全局调整 → 局部蒙版调整 → Creative LUT → Output。`.cube` 不可靠地携带色彩空间信息，故导入时不再默认 sRGB；Technical LUT 还必须与源 encoding 完整匹配。HDR 源的 SDR 输出在全部调整完成后进行 headroom tone mapping；HDR 输出为 10-bit HEIF Rec.2100 HLG。HDR 下不安全的 HSL、曲线和 LUT 会被显式拒绝。Histogram 在每次最新 preview 成功后节流约 160 ms 从该 CGImage 计算，不会因 Slider 再渲染一次源图。详见 [color-management.md](color-management.md)、[hdr-workflow.md](hdr-workflow.md) 与 [local-adjustments.md](local-adjustments.md)。
