# Preset format

预设是单个 Codable JSON `Preset` 文件，可通过预设页导入或导出。它由稳定的 ID、名称、收藏状态、创建时间和以下 `PresetPayload` 组成：

- Light：曝光、对比度、高光、阴影
- Color：色温、色调、饱和度、自然饱和度
- HSL：红、橙、黄、绿、青、蓝、紫、洋红的 Hue/Saturation/Luminance
- Curves：Master、Red、Green、Blue 的有序控制点
- Detail、Effects、LUT 和 LUT 强度
- 可选 `transform`：仅当创建预设时明确勾选才包括裁切、旋转和水平翻转

导入预设会分配新的本地 ID，以免覆盖已有项目。应用预设不会修改原图，且默认保留正在编辑照片的 transform。应用内 `AdjustmentClipboard` 提供同一组字段的 Copy All、Paste All 和任意分组选择性粘贴。
