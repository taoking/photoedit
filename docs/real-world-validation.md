# 真机与真实媒体验收清单

本清单用于 Phase 8.5 后的人工验收。不得将个人照片、ARW/DNG、视频、导出文件或缓存提交进 Git。

## 标准照片

- iPhone HEIC、带/不带 ICC profile 的 sRGB JPEG、Display P3 照片分别导入。
- 检查 EXIF 6/8 方向、裁切、90° 旋转、最长边 resize 后的预览/导出像素尺寸和 Orientation=1 metadata。
- 对比 Preview 与 JPEG/HEIF 导出的曝光、色温、饱和度、HSL、曲线和 Creative LUT。
- 在红、橙、肤色、青、蓝区域反复正负调整 HSL 后回到界面 0；确认预览恢复原图且相邻通道不会随操作次数持续串色。
- 先提高曝光再调整不匹配的 HSL 通道，确认高光和非目标颜色不发生额外重建、变白或色相漂移。
- 分别验证 GPS 保留/移除；确认拍摄日期、相机、镜头、ISO、快门和光圈仍存在。

## Sony A7C II ARW / DNG

- 初次打开应与相机 as-shot 白平衡一致；不移动 RAW 色温/色调滑杆时不能被重置到 6500 K。
- 不调整任何 RAW slider 时，将结果与系统/Core Image decoder 默认 render 对比；明度/色彩降噪、RAW 锐化、细节、局部色调和镜头校正均不得被 PhotoEdit 的 UI 初始值覆盖。
- 调整 RAW 温度/色调增量、曝光、双降噪、锐化、细节、局部色调和镜头校正。
- 比较 draft preview、较高质量 preview 与 JPEG/HEIF 全分辨率导出；检查相机与镜头 metadata。
- 记录 24MP/48MP 真实文件的首帧、滑杆延迟、峰值内存和导出时间。

## LUT

- 验证 17³、33³、65³ cube，以及非默认 `DOMAIN_MIN/MAX` 的厂商样本。
- 只依据作者资料配置 Creative/Technical 与 encoding；确认不匹配 source 的 Technical LUT、以及所有跨 encoding Technical LUT（例如 Rec.709 → sRGB）均被拒绝。
- Sony S-Log3/S-Gamut3(.Cine)、LogC、PQ、HLG Technical conversion 和未声明 LUT 当前应被拒绝，不能人工标记为 sRGB 后误用。

## HDR

- 在支持 EDR 的 iPhone 使用 iPhone HDR HEIF/gain-map、HLG 真实素材检查亮部 preview、SDR tone-map 与 10-bit HLG HEIF 导出。
- 当前应明确看到 HDR HSL、曲线和 LUT 不可用；不要把它们视为漏测。验证基础全局调整和局部蒙版不丢失 highlight headroom。
- 在 SDR 显示器检查 SDR 导出 roll-off，在 HDR 设备/Photos 检查 HDR HEIF 高光细节。

## 视频

- 使用横拍与竖拍 metadata rotation 的 H.264/HEVC SDR 视频，确认 preview 和导出没有双旋转、裁切或时长变化。
- 验证含音频、4K、长时和不同帧率素材的连续播放、音画同步、LUT 强度、MP4/MOV 分享以及导出耗时/峰值内存。
- 导入带 HLG/PQ metadata 的 HDR 视频时应得到明确拒绝；不要把未标记 HDR 文件视为已验证的 SDR。
