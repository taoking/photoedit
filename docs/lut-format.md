# LUT format

PhotoEdit 支持标准 3D `.cube` 文件中的：

- `TITLE`
- `LUT_3D_SIZE`：17、33、65
- `DOMAIN_MIN` 与 `DOMAIN_MAX`
- RGB 浮点表
- 空行、整行与行内 `#` 注释

1D LUT (`LUT_1D_SIZE`) 不属于 Phase 1 范围。解析器会精确检查颜色数等于 `dimension³`，并为缺少尺寸、非支持尺寸、无效数值与数量不匹配返回可显示错误，绝不崩溃。

RGB 值以 `.cube` 通用的 red-fastest 顺序读取，并转换为 Core Image 所需的 `RGBA Float32`（每个 alpha 恒为 1）数据。渲染会先逐通道将输入从 `DOMAIN_MIN…DOMAIN_MAX` 归一化到 Core Image cube 的 `0…1` 坐标；每个 `DOMAIN_MAX` 必须大于对应 `DOMAIN_MIN`，否则导入被拒绝。LUT 强度不重新构建 cube：先渲染完整 LUT 结果，再以它的 alpha 在未经 LUT 的当前编辑图像上混合；0% 即无 LUT，100% 即完整 LUT。

导入成功后源文件会复制到 Application Support，原始 File Provider 的临时 URL 不再是依赖。缩略图通过 256px preview 渲染并使用内存缓存；相同 LUT 的 in-flight 请求会去重，避免 SwiftUI 列表刷新重复启动渲染。

LUT 目前只用于 SDR 照片和 SDR 视频。HDR 照片中的 Color Cube LUT 会被明确禁用，以避免损失 extended-range headroom。Technical LUT 必须携带并匹配实际源 encoding；Sony S-Log3/S-Gamut3(.Cine)、LogC、PQ 等 log/camera transform 尚未实现。
