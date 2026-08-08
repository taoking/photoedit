# Development Progress

## Phase 8.5 — Correctness & Real-world Validation

Status: COMPLETED (AUTOMATED)

Commit: recorded by the Phase 8.5 commit in Git history

Tests: PASS — `xcodebuild -project PhotoEdit.xcodeproj -scheme PhotoEdit -destination 'platform=iOS Simulator,id=E2208B8A-94AC-4945-A50F-05AD793584B2' test`; 58 tests, 0 failures.

Build: PASS — `xcodegen generate` 后，iPhone 17 Pro、iOS 26.5 Simulator 的独立 `xcodebuild ... build` 成功；安装和启动冒烟检查成功。

Phase 8.5 Acceptance:

- [PASS] RAW 零 temperature/tint 改为相对 CIRAWFilter decoder/as-shot 白平衡的零增量；旧 `EditState` JSON 无 schema 破坏。
- [PASS] EXIF `DateTimeOriginal` 使用 `yyyy:MM:dd HH:mm:ss` + `en_US_POSIX` 解析，并以 TIFF DateTime fallback；缺少时区时不伪造 UTC。
- [PASS] HDR synthetic `RGB > 1` identity HSL/curve 路径保留 half-float headroom；非 identity HSL、曲线和 Technical/Creative Color Cube LUT 被 UI 与 render pipeline 明确拒绝，避免静默 SDR 裁切。
- [PASS] LUT metadata 额外建模 primaries/gamut 与 transfer function；Technical LUT 必须和实际 source encoding 精确匹配。S-Log3/S-Gamut3(.Cine)、LogC、PQ 等未实现 encoding 会安全拒绝。
- [PASS] `.cube DOMAIN_MIN/MAX` 在进入 Color Cube 前逐通道归一化；反向/零宽 domain 被拒绝。
- [PASS] 导出 metadata 强制 Orientation=1、正确根/EXIF/TIFF 像素尺寸、移除陈旧 thumbnail，并回归验证 crop/rotate/resize/GPS remove。
- [PASS] Histogram 从最后成功的 edited preview 节流计算，不重复渲染 source；正曝光回归验证其向亮部移动。
- [PASS] Brush mask 改为按 Preview/Export 尺寸栅格化的 alpha bitmap cache，不再构建最多 512 个 CI radial filter 节点；归一化 Preview/Export 对齐测试通过。
- [PASS] 视频新增 80×40、90° preferredTransform fixture，导出 display geometry 为 40×80、时长正确且无 double rotate。iOS 26 使用新 API；iOS 17–25 的旧 API 仅保留在隔离兼容层。
- [PASS] `SWIFT_STRICT_CONCURRENCY` 从 `minimal` 提升到 `targeted`；增加最后导入请求获胜和 LUT thumbnail in-flight 去重回归。

Manual Verification Required:

- 按 [real-world-validation.md](real-world-validation.md) 在 Sony A7C II ARW/DNG、iPhone HDR HEIF/gain-map、Display P3、带方向 metadata 的 H.264/HEVC 与 4K/含音频视频上验收。
- 重点检查 RAW as-shot 白平衡、真实 HDR highlight、metadata、长笔画内存、视频音画同步与 4K 导出性能；真实媒体不纳入仓库。

Known Limitations:

- 当前 HDR 照片明确不支持 HSL、曲线及所有 LUT；这是正确性保护而非功能故障，待 extended-range 实现和真实设备验证后才可恢复。
- S-Log3/S-Gamut3(.Cine)、LogC、PQ、Dolby Vision 及 HDR video 仍不支持，不能被 metadata/文件名猜测为 sRGB。
- Xcode 仍会输出无 AppIntents dependency 的非操作性 metadata-extraction warning；没有新的 compiler/concurrency/Core Image actionable warning。

---

## Phase 1

Status: COMPLETED

Commit: recorded by the Phase 1 commit in Git history

Tests: PASS — `xcodebuild -project PhotoEdit.xcodeproj -scheme PhotoEdit -destination 'platform=iOS Simulator,id=E2208B8A-94AC-4945-A50F-05AD793584B2' test`; 15 tests, 0 failures.

Build: PASS — iPhone 17 Pro, iOS 26.5 Simulator.

Implemented:

- Native SwiftUI application with PhotosPicker and File importer for JPEG, HEIC/HEIF and PNG.
- Immutable source asset plus Codable, Equatable, grouped non-destructive EditState and base undo/reset.
- Shared Metal-backed Core Image pipeline with preview downsampling, render cancellation/generation guard, and full-resolution export path.
- Exposure, contrast, highlights, shadows, temperature, tint, saturation, vibrance, sharpness and vignette.
- 17³/33³/65³ CUBE parser, identity built-in LUT, imported LUT persistence, favorites, rename/delete, thumbnail cache and 0–100% blend.
- Non-destructive free/aspect crop, 90° rotation, horizontal flip, hold-to-view-before, zoom/pan.
- JPEG/HEIF original-or-resized export, metadata/GPS option, Photos saving, sharing and Files export.
- Architecture, pipeline and LUT-format documentation plus parser/state/pipeline/export/repository tests.

Manual Verification Required:

- Import a real 24MP HEIC from Photos; interactively drag all sliders and switch a real 33³ LUT.
- Verify Photos permission, Photos save, Share and Files sheet on an actual device.
- Compare a real-camera full-resolution JPEG/HEIF output with Preview for visual color agreement and metadata retention.
- Measure peak memory and latency for 12MP, 24MP and 48MP photos on physical hardware.
- Verify pinch/pan, before press/hold and free-crop interaction ergonomics manually.

Known Limitations:

- No source repository, photo fixtures or README existed before this run; a new local Git repository and project were initialized.
- The simulator build emits Xcode's non-actionable AppIntents metadata-extraction warning because this app intentionally has no AppIntents dependency.
- Phase 1 deliberately assumes SDR sRGB Creative LUTs; Technical LUT color metadata, RAW, HDR, batch, masks and video remain later phases.

---

## Phase 2

Status: COMPLETED

Commit: recorded by the Phase 2 commit in Git history

Tests: PASS — `xcodebuild -project PhotoEdit.xcodeproj -scheme PhotoEdit -destination 'platform=iOS Simulator,id=E2208B8A-94AC-4945-A50F-05AD793584B2' test`; 22 tests, 0 failures (includes Phase 1 regression).

Build: PASS — iPhone 17 Pro, iOS 26.5 Simulator.

PHASE 2 ACCEPTANCE

- [PASS] Red / Orange / Yellow / Green / Aqua / Blue / Purple / Magenta each have Codable Hue, Saturation and Luminance state.
- [PASS] Single-channel and global HSL reset are implemented outside SwiftUI views.
- [PASS] Master, Red, Green and Blue curves support adding, moving, non-crossing X positions, protected endpoints, deleting inner points and reset.
- [PASS] RGB and luminance histograms are computed from a 512px Preview Source, not full-resolution Slider renders.
- [PASS] Presets create, apply, rename, delete, favorite, JSON import/export and exclude transform by default.
- [PASS] Copy All, Paste All and selective group paste cover Light, Color, HSL, Curve, LUT, Detail, Effects and Crop.
- [PASS] Phase 1 parser, pipeline, crop, LUT and export regression coverage remains green.

Implemented:

- HSL `CIColorKernel` with soft hue/saturation selection, exercised by a red desaturation render test.
- Serializable, constrained arbitrary-point tone curves rendered as 64³ Core Image Color Cube.
- Throttled RGB/luminance Preview Source histogram.
- Codable JSON `PresetRepository`, Files import/export UI and app-local adjustment clipboard.
- Color Mixer, curve editor, histogram, preset and selective-paste SwiftUI interfaces.

Manual Verification Required:

- On a physical device, inspect HSL boundary behavior for real skin tones, oranges, aqua/blue and low-saturation pixels.
- Manually judge tone-curve touch ergonomics, point deletion, histogram responsiveness and preset Files/Share workflow.
- Repeat Phase 1 real-photo/Photos-permission, 12MP/24MP/48MP performance and export visual checks.

Known Limitations:

- The Phase 2 HSL kernel uses Core Image Kernel Language because no native filter can isolate the requested eight HSL ranges. Its deprecation annotation is explicitly silenced by Apple’s `CI_SILENCE_GL_DEPRECATION` setting; its processor boundary is isolated for a future Metal replacement.
- The simulator build emits Xcode's non-actionable AppIntents metadata-extraction warning because this app intentionally has no AppIntents dependency.

## Phase 3

Status: COMPLETED

Commit: recorded by the Phase 3 commit in Git history

Tests: PASS — 24 tests, 0 failures (includes all prior regression tests).

Build: PASS — iPhone 17 Pro, iOS 26.5 Simulator.

Implemented:

- DNG/ARW 文件识别与 `CIRAWFilter` 解码层，RAW 参数独立于通用 `EditState` 调整。
- Draft 低分辨率 Preview 和全分辨率 Export decode 策略；RAW 输出随后进入同一标准编辑/LUT/导出管线。
- RAW Exposure、Temperature、Tint、双降噪、Sharpness、Detail、Local Tone 与 lens correction 控制。
- Camera、Lens、Aperture、Shutter、ISO 与 Focal Length 元数据展示。

Manual Verification Required:

- 用 Sony A7C II ARW 和 DNG 在真机验证 `CIRAWFilter` 支持、相机白平衡、镜头校正、draft→高质量预览与全分辨率导出。

Known Limitations:

- 工作区没有可合法纳入仓库的真实 DNG/ARW fixture，因此无法自动验证厂商 RAW decoder 兼容性；这是人工验收项，不影响标准照片回归。

## Phase 4

Status: COMPLETED

Commit: recorded by the Phase 4 commit in Git history

Tests: PASS — `xcodebuild -project PhotoEdit.xcodeproj -scheme PhotoEdit -destination 'platform=iOS Simulator,id=E2208B8A-94AC-4945-A50F-05AD793584B2' test`; 27 tests, 0 failures (includes all prior regression tests).

Build: PASS — iPhone 17 Pro, iOS 26.5 Simulator.

Phase 4 Acceptance:

- [PASS] Files picker can select multiple JPEG/HEIF/PNG/DNG/ARW sources in one operation.
- [PASS] A batch can explicitly use current adjustments, clipboard adjustments, a stored preset, or a selected LUT.
- [PASS] `BatchExportQueue` processes jobs strictly one at a time; each iteration opens its own source URL, so selected photos are not all decoded/retained in memory.
- [PASS] Progress, cancellation and completed/failed/cancelled item results are exposed in the editor; a unit test verifies one invalid source does not prevent a valid item from exporting.
- [PASS] JPEG/HEIF, original/resize, JPEG quality and original/original-edited/sequential filename strategies are supported; completed files can be handed to the system share/save sheet together.
- [PASS] Recent LUT, preset and export settings are persisted and deduplicated, with coverage for persistence.
- [PASS] A reference file produces an independent preview that can be shown beside the current edit.

Implemented:

- URL-backed batch selection, sequential Core Image export queue and per-item outcome model.
- Batch adjustment-source controls, progress/cancel UI, result summary and system sharing.
- Export naming policies shared by single and batch export.
- UserDefaults-backed Recent Settings store for LUT, preset and export settings.
- Reference photo import and left/right comparison presentation.
- RAW file-path detection fix and correct full-resolution RAW decode even for resized exports.

Manual Verification Required:

- On a physical device, select a real travel folder of JPEG/HEIF/DNG/ARW files and verify progress, cancellation latency, memory peak, errors, system share/save workflow and filename collision behavior.
- Compare a reference photo and edit side-by-side for several source aspect ratios; evaluate legibility and accessibility under both light and dark appearances.

Known Limitations:

- The File importer—not PhotosPicker—is the multi-selection entry point, because raw camera files require Files access in this phase.
- Batch output remains temporary until handed to the system share/save sheet; the app never overwrites source files.

## Phase 5

Status: COMPLETED

Commit: recorded by the Phase 5 commit in Git history

Tests: PASS — `xcodebuild -project PhotoEdit.xcodeproj -scheme PhotoEdit -destination 'platform=iOS Simulator,id=E2208B8A-94AC-4945-A50F-05AD793584B2' test`; 31 tests, 0 failures (includes all prior regression tests).

Build: PASS — iPhone 17 Pro, iOS 26.5 Simulator.

Phase 5 Acceptance:

- [PASS] Creative LUT 与 Technical LUT 通过持久化 `LUTKind` 分流；Technical LUT 在全局创意调整前以 100% 套用，Creative LUT 在其后按强度混合。
- [PASS] `LUTColorMetadata` 持久化输入/输出色彩空间；新导入 LUT 不再猜测 sRGB，未声明 metadata 的 LUT 被拒绝渲染。
- [PASS] sRGB、Display P3、Linear sRGB、Rec.709、Extended Linear sRGB 与 Rec.709 HLG 均有显式 descriptor，HDR 输入不会被默认为 sRGB。
- [PASS] 长生命周期 `CIContext` 使用 linear sRGB working space 与 sRGB SDR output；Source → Working → Technical → Creative → Output 流程已经文档化。
- [PASS] Technical identity LUT、metadata 编解码、未知 metadata 拒绝和既有 pipeline/export/batch/RAW 回归均自动覆盖。

Manual Verification Required:

- 在真机以已知 S-Log3 → Rec.709、HLG → Rec.709 LUT 与相机原始素材比对厂商参考结果。
- 以 Display P3 源图检查 Preview、全分辨率 JPEG/HEIF sRGB export，并检查 Technical + Creative LUT 连用的视觉一致性。

Known Limitations:

- `.cube` 没有可靠的标准色彩空间 metadata；用户必须依据 LUT 作者资料标注其类型和输入/输出空间。
- Phase 5 的输出仍是 SDR sRGB。Extended Linear/HLG 仅保留为可验证的描述符；真正的 HDR preview、tone mapping 与 HDR HEIF export 留待 Phase 6。

## Phase 6

Status: COMPLETED

Commit: recorded by the Phase 6 commit in Git history

Tests: PASS — `xcodebuild -project PhotoEdit.xcodeproj -scheme PhotoEdit -destination 'platform=iOS Simulator,id=E2208B8A-94AC-4945-A50F-05AD793584B2' test`; 36 tests, 0 failures (includes Phase 1–5 regression tests and a real HEIF10 encode/decode test).

Build: PASS — iPhone 17 Pro, iOS 26.5 Simulator.

Phase 6 Acceptance:

- [PASS] HDR-capable ImageIO input is expanded through Core Image, with source color descriptor and content headroom tracked separately from SDR assets.
- [PASS] The shared pipeline now uses Extended Linear sRGB plus RGBA half-float intermediates; HDR preview renders a half-float `CGImage` and the editor requests `UIImageView` high dynamic range presentation.
- [PASS] SDR remains the default for JPEG/HEIF. HDR source content is tone mapped to headroom 1.0 after the edit chain, and SDR preview still renders RGBA8 sRGB.
- [PASS] HDR export rejects SDR input and non-HEIF formats, then emits Rec.2100 HLG with Core Image `heif10Representation`; an automated test encodes and decodes an HDR HEIF on the simulator.
- [PASS] Existing SDR import, LUT, RAW, crop, batch and JPEG export regressions remain green.

Manual Verification Required:

- On an EDR-capable iPhone, compare imported iPhone HDR HEIF/gain-map and HLG camera files with Photos, checking bright highlight detail in preview and Rec.2100 HLG HEIF output.
- Inspect SDR tone-mapped exports on a conventional display; verify HDR HEIF Photos/Share/Files save behavior and GPS removal.
- Measure memory and latency for 12MP/24MP/48MP real HDR sources.

Known Limitations:

- The repository has no redistributable real HDR/gain-map fixture, so visual HDR headroom and hardware display behavior cannot be automated here.
- Core Image's `CIToneMapHeadroom` requires iOS 18. HDR → SDR conversion reports an explicit unsupported-system error below that OS rather than silently clipping; ordinary SDR behavior still supports the app's iOS 17 deployment target.

## Phase 7

Status: COMPLETED

Commit: recorded by the Phase 7 commit in Git history

Tests: PASS — `xcodebuild -project PhotoEdit.xcodeproj -scheme PhotoEdit -destination 'platform=iOS Simulator,id=E2208B8A-94AC-4945-A50F-05AD793584B2' test`; 40 tests, 0 failures (includes all Phase 1–6 regressions).

Build: PASS — iPhone 17 Pro, iOS 26.5 Simulator.

Phase 7 Acceptance:

- [PASS] `EditState` stores an ordered list of independent local adjustments, each with its own enabled flag, mask and exposure/contrast/saturation values; an old JSON state without the new field decodes safely to an empty list.
- [PASS] Linear gradient, radial gradient and sampled brush masks are rendered by Core Image and blend only the adjusted result through the mask; automated pixel checks prove all three alter the output.
- [PASS] Local adjustments are applied after global adjustments and before Creative LUT/transform, so Preview and full-resolution export use the same order.
- [PASS] Local adjustments participate in undo, Codable persistence and selective copy/paste. Brush sampling is distance-limited and capped at 512 points per stroke.
- [PASS] All existing photo, RAW, batch, color-management and HDR tests remain green.

Manual Verification Required:

- Verify touch ergonomics, crop alignment, overlapping-mask order and Preview/export consistency on JPEG, HEIF and actual RAW files on an iPhone.
- Measure long brush stroke responsiveness and memory on 12MP/24MP/48MP assets. Semantic Subject/Sky masks are intentionally deferred and therefore have no claim of automatic scene selection.

Known Limitations:

- The Phase 7 scope intentionally provides manual linear/radial/brush masks only; no AI subject or sky segmentation is included.
- A very dense brush is bounded at 512 samples to protect render cost. The cap favors predictable editing latency over an unbounded geometric stroke representation.

## Phase 8

Status: COMPLETED

Commit: recorded by the Phase 8 commit in Git history

Tests: PASS — `xcodebuild -project PhotoEdit.xcodeproj -scheme PhotoEdit -destination 'platform=iOS Simulator,id=E2208B8A-94AC-4945-A50F-05AD793584B2' test`; 44 tests, 0 failures (includes a generated H.264 video export/decode regression and all Phase 1–7 tests).

Build: PASS — iPhone 17 Pro, iOS 26.5 Simulator.

Phase 8 Acceptance:

- [PASS] Files import opens an independent full-screen video editor; it copies the selected source to temporary storage before reading the video track, duration, dimensions and orientation transform.
- [PASS] AVPlayer preview uses an `AVVideoComposition`; exposure, contrast, saturation, Creative LUT selection and LUT intensity all go through the same `VideoFrameProcessor` as export.
- [PASS] The per-frame Core Image processor uses a Metal-backed context and preserves the source preferred transform. Video export uses `AVAssetExportSession` at highest quality, preferring MP4 and falling back to MOV, without altering the original source.
- [PASS] Only Creative LUTs declared sRGB → sRGB are accepted by this SDR video workflow. HLG/PQ-marked HDR videos, Technical LUTs and ambiguous LUT metadata are rejected rather than silently treated as SDR/sRGB.
- [PASS] An automated test writes a small H.264 MOV, imports, filters, exports and decodes it to a non-empty video track; state serialization and basic filter/orientation tests also pass.

Manual Verification Required:

- On an iPhone, import horizontal and vertical SDR H.264/HEVC videos with audio, including long/4K/high-frame-rate material. Compare player preview with exported MP4/MOV for direction, LUT strength, continuous playback and audio/video sync.
- Measure preview rebuild latency and export memory/time with actual travel footage; use the system Share sheet to verify save/send compatibility.

Known Limitations:

- HDR HLG/PQ, Dolby Vision, gain maps and per-frame HDR metadata have no Phase 8 export policy and are explicitly outside this SDR video workflow. Unmarked HDR sources cannot be inferred reliably from an extension alone and still require human source inspection.
- No trim, transition, multi-track, local masks, HSL/curves, RAW or technical log-to-display video conversion is implemented. The scope is basic SDR correction plus a declared Creative LUT.
