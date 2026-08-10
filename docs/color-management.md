# Color management and Technical LUTs

## Render contract

PhotoEdit uses one long-lived, Metal-backed `CIContext`. It declares an Extended Linear sRGB, RGBA half-float Core Image working space; SDR output uses sRGB and HDR output uses Rec.2100 HLG 10-bit HEIF. ImageIO preserves an embedded ICC profile when it can identify one; a standard JPEG, HEIF or PNG with no profile is explicitly loaded with an sRGB fallback. The source asset records the detected descriptor for inspection and render planning.

```text
Source Color Space
→ Extended Linear sRGB Core Image Working Space
→ Technical LUT (optional, 100%，source encoding 必须精确匹配，且 input/output encoding 必须相同)
→ global creative adjustments
→ Creative LUT (optional, 0…100%)
→ transform / crop
→ HDR preview / Rec.2100 HLG HDR output, or tone-mapped sRGB SDR output
```

`CIContext` performs its normal source-to-working and working-to-output color handling. The pipeline deliberately does not add `CIImage.matchedToWorkingSpace` nodes: Core Image returns a black frame for some generated or profile-less `CIImage` graphs when those nodes are injected. This keeps ordinary CIImage, ImageIO and RAW paths stable while retaining the context-level color-management boundary.

SDR HSL is a deliberate local exception inside the global linear working graph. Its single-pass kernel converts each sampled extended-linear value through the sRGB transfer function, derives all eight channel weights from that unchanged display-referred pixel, combines active channel deltas without overlap amplification, and converts the result back to linear. Values above 1 are normalized only for classification and regain their original peak afterward; a pixel outside every active hue range returns byte-for-byte unchanged. HDR HSL remains disabled because this SDR rule is not an HLG/PQ appearance model.

## Descriptors

`ColorSpaceDescriptor` covers the Core Image color spaces the app can actually construct: sRGB, Display P3, Linear sRGB, Rec.709, Extended Linear sRGB, Rec.709 HLG and Rec.2100 HLG. `ColorEncodingDescriptor` separately persists **primaries/gamut** and **transfer function**, so metadata can distinguish e.g. Rec.2020 HLG from Rec.709 HLG instead of treating both as a vague “HDR space”. Existing Phase 5 JSON without these fields migrates from its stored `ColorSpaceDescriptor`.

## LUT metadata and ordering

Every LUT carries a `LUTKind` and `LUTColorMetadata`:

- `Creative` describes a look such as film, warm/cool or cinematic. It is blended after global adjustments using the selected strength.
- `Technical` is a precisely declared conversion for an encoding supported by the current photo pipeline. It runs before all creative adjustments and always runs at 100%.

`.cube` does not reliably encode input or output color spaces. New imports therefore start as `Creative` with both fields unspecified; they cannot be rendered until the user deliberately selects the LUT kind and its input/output descriptors in the LUT panel. Existing catalog entries migrate to the same safe, unspecified state. The built-in Neutral LUT is explicitly sRGB → sRGB.

The metadata is stored with the catalog and validated before rendering. Technical LUT 的 source encoding 必须等于声明的 input encoding，且 input encoding 必须完全等于 output encoding；PhotoEdit 不会因为 metadata 完整就执行任何跨编码转换。`CIColorCubeWithColorSpace` receives the declared output space as the working color space of the cube texels. A LUT file's title or filename is never treated as proof of its encoding. Users must consult the LUT author/camera documentation before labelling a technical conversion.

Supported now: SDR source 上的 **same-encoding Technical LUT only**，且 source encoding 必须精确匹配，例如 sRGB → sRGB 与 Rec.709 → Rec.709。Not supported: cross-encoding Technical LUT（包括 Rec.709 → sRGB、Display P3 → sRGB、HLG → Rec.709）、Sony S-Log3/S-Gamut3/S-Gamut3.Cine、ARRI LogC、generic “Log”、PQ、Dolby Vision，以及任何 camera-log-to-display 转换。HLG photo sources use the HDR path, where Color Cube LUTs are deliberately disabled until extended-range cube behavior is proven correct.

## Output and verification limits

SDR exports remain JPEG or HEIF sRGB, with the existing metadata/GPS policy. Phase 6 additionally provides HDR HEIF only for a validated HDR source, with Rec.2100 HLG and 10-bit encoding. This app does not claim to make an arbitrary S-Log, HLG or P3 cube visually correct without an accurate LUT declaration and a real source file.

Manual verification is required with the original camera/display assets:

- Compare an exact same-encoding SDR Technical LUT（sRGB → sRGB 或 Rec.709 → Rec.709）on a physical device against the LUT vendor's reference viewer. Do not use cross-encoding、S-Log3/HLG/PQ LUTs in the current release; those encodings are intentionally rejected.
- Check Display P3 source import and sRGB export on both an SDR-only display and a wide-gamut iPhone display.
- Compare Preview with a full-resolution JPEG/HEIF export, including a Technical LUT followed by a Creative LUT.
