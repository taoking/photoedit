# Color management and Technical LUTs

## Render contract

PhotoEdit uses one long-lived, Metal-backed `CIContext`. It declares an Extended Linear sRGB, RGBA half-float Core Image working space; SDR output uses sRGB and HDR output uses Rec.2100 HLG 10-bit HEIF. ImageIO preserves an embedded ICC profile when it can identify one; a standard JPEG, HEIF or PNG with no profile is explicitly loaded with an sRGB fallback. The source asset records the detected descriptor for inspection and render planning.

```text
Source Color Space
→ Extended Linear sRGB Core Image Working Space
→ Technical LUT (optional, 100%)
→ global creative adjustments
→ Creative LUT (optional, 0…100%)
→ transform / crop
→ HDR preview / Rec.2100 HLG HDR output, or tone-mapped sRGB SDR output
```

`CIContext` performs its normal source-to-working and working-to-output color handling. The pipeline deliberately does not add `CIImage.matchedToWorkingSpace` nodes: Core Image returns a black frame for some generated or profile-less `CIImage` graphs when those nodes are injected. This keeps ordinary CIImage, ImageIO and RAW paths stable while retaining the context-level color-management boundary.

## Descriptors

The persisted `ColorSpaceDescriptor` values are sRGB, Display P3, Linear sRGB, Rec.709, Extended Linear sRGB, Rec.709 HLG and Rec.2100 HLG. Extended Linear and HLG are preserved as explicit descriptors rather than silently interpreted as sRGB. Phase 6 adds the HDR preview/export policy; SDR remains the default.

## LUT metadata and ordering

Every LUT carries a `LUTKind` and `LUTColorMetadata`:

- `Creative` describes a look such as film, warm/cool or cinematic. It is blended after global adjustments using the selected strength.
- `Technical` describes a camera/display conversion such as S-Log3 → Rec.709 or HLG → Rec.709. It runs before all creative adjustments and always runs at 100%.

`.cube` does not reliably encode input or output color spaces. New imports therefore start as `Creative` with both fields unspecified; they cannot be rendered until the user deliberately selects the LUT kind and its input/output descriptors in the LUT panel. Existing catalog entries migrate to the same safe, unspecified state. The built-in Neutral LUT is explicitly sRGB → sRGB.

The metadata is stored with the catalog and validated before rendering. `CIColorCubeWithColorSpace` receives the declared output space as the working color space of the cube texels (the mapped RGB values); the declared input remains an explicit compatibility constraint. A LUT file's title or filename is never treated as proof of its encoding. Users must consult the LUT author/camera documentation before labelling a technical conversion.

## Output and verification limits

SDR exports remain JPEG or HEIF sRGB, with the existing metadata/GPS policy. Phase 6 additionally provides HDR HEIF only for a validated HDR source, with Rec.2100 HLG and 10-bit encoding. This app does not claim to make an arbitrary S-Log, HLG or P3 cube visually correct without an accurate LUT declaration and a real source file.

Manual verification is required with the original camera/display assets:

- Compare a known S-Log3 → Rec.709 and HLG → Rec.709 Technical LUT on a physical device against the LUT vendor's reference viewer.
- Check Display P3 source import and sRGB export on both an SDR-only display and a wide-gamut iPhone display.
- Compare Preview with a full-resolution JPEG/HEIF export, including a Technical LUT followed by a Creative LUT.
