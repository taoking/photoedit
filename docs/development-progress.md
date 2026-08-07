# Development Progress

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

Status: NOT_STARTED

## Phase 7

Status: NOT_STARTED

## Phase 8

Status: NOT_STARTED
