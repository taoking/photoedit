# 视频 LUT 工作流

Phase 8 是独立于 `ImagePipeline` 的视频路径。它重用 `.cube` 解析器、`LUT` 值类型和 LUT 色彩元数据，但不把静态照片的 Preview/RAW/HDR 图像链强行用于视频。

## 输入与预览

Files 视频选择器会把源文件复制到应用临时目录，再读取视频轨道、时长、尺寸和 `preferredTransform`；原视频绝不改写。`AVPlayerItem` 的 `AVVideoComposition` 会对每个请求帧执行同一套 `VideoFrameProcessor`：

```text
AVFoundation source frame
→ Core Image exposure / contrast / saturation
→ Creative .cube LUT + 0…100% alpha blend
→ source preferredTransform（仅套用一次，保持竖拍方向）
→ Metal-backed CIContext
→ AVPlayer preview 或 AVAssetExportSession
```

滑杆和 LUT 选择会重建 player item 的 video composition，因此预览与导出共享相同的状态和滤镜顺序，而非对预览截图再编码。

## LUT 与色彩范围

当前视频范围明确是 SDR。只显示/接受已经声明为 **Creative、sRGB → sRGB** 的 LUT；Technical LUT、未声明 LUT 和其它输入/输出空间的 LUT 都会被拒绝，避免对视频源作猜测的色彩转换。新导入的 `.cube` 会列出一项显式确认操作：只有用户根据 LUT 作者资料确认它是 sRGB 输入/输出的 Creative LUT 后，才写入该 metadata 并进入视频 LUT 列表。带明确 HLG 或 PQ transfer function 的 HDR 视频会在导入时提示不受支持，等待独立的 HDR 视频输出策略。

未携带 transfer-function metadata 的视频无法仅靠文件扩展名可靠识别 HDR，因此仍需用真实相机文件进行人工验证；本阶段不声称可安全处理这类未标记 HDR 源。

## 导出

`AVAssetExportSession` 使用 `AVAssetExportPresetHighestQuality` 和同一个 video composition 重新编码视频。优先输出 MP4；若系统会话不支持则回退到 MOV。导出完成后提供系统共享面板保存或发送，源视频不覆盖。现有音轨由 export session 随源资产一并保留。iOS 26 使用新的 `AVVideoComposition(applyingFiltersTo:)` API；为保留 iOS 17–25 支持，旧 filtering handler 被隔离在一个兼容层，待最低版本升至 iOS 26 后删除。

## 已验证与人工验收

自动测试在模拟器以内存生成一个 H.264 MOV，导入后做基础调色、用视频 composition 导出、再由 `AVURLAsset` 读取结果的视频轨道和时长；另有状态 Codable、帧级调色及旋转 extent 测试。

仍需在真实 iPhone 上使用横拍/竖拍、含音轨、长时、4K 和不同帧率的 SDR 视频，检查：播放连续性、竖拍方向、音画同步、LUT 强度、Preview 与导出一致性、MP4/MOV 分享及导出耗时/峰值内存。HDR、Dolby Vision、逐帧 HDR metadata、剪辑、转场与多轨合成不属于本阶段。
