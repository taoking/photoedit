# LUT format

PhotoEdit 支持标准 3D `.cube` 文件中的：

- `TITLE`
- `LUT_3D_SIZE`：17、33、65
- `DOMAIN_MIN` 与 `DOMAIN_MAX`
- RGB 浮点表
- 空行、整行与行内 `#` 注释

1D LUT (`LUT_1D_SIZE`) 不属于 Phase 1 范围。解析器会精确检查颜色数等于 `dimension³`，并为缺少尺寸、非支持尺寸、无效数值与数量不匹配返回可显示错误，绝不崩溃。

RGB 值以 `.cube` 通用的 red-fastest 顺序读取，并转换为 Core Image 所需的 `RGBA Float32`（每个 alpha 恒为 1）数据。LUT 强度不重新构建 cube：先渲染完整 LUT 结果，再以它的 alpha 在未经 LUT 的当前编辑图像上混合；0% 即无 LUT，100% 即完整 LUT。

导入成功后源文件会复制到 Application Support，原始 File Provider 的临时 URL 不再是依赖。缩略图通过 256px preview 渲染并使用内存缓存，避免 LUT 列表触发全分辨率处理。

Phase 1 把 LUT 视为 SDR sRGB Creative LUT。Technical LUT 的类别、输入/输出色彩元数据和色彩转换将在 Phase 5 提供。
