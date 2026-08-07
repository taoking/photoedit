# HDR workflow

## Dynamic-range contract

Phase 6 keeps the existing SDR behavior as the default. The source is loaded with Core Image's HDR expansion enabled, and PhotoEdit records the source color descriptor plus its reported content headroom. A source is treated as HDR only when Core Image reports headroom above 1.0 or it carries an explicit HDR descriptor such as Rec.2100 HLG; a normal sRGB image cannot be exported as HDR merely by changing an export setting.

```text
HDR source / HDR gain map
→ Extended Linear sRGB + RGBA half-float Core Image working space
→ Technical LUT → adjustments → Creative LUT → transform/crop
→ HDR preview (RGBA half-float, UIImageView preferred dynamic range: high)
→ 10-bit HEIF in Rec.2100 HLG

the same edited HDR source
→ Core Image Tone Map Headroom (target headroom 1.0)
→ sRGB RGBA8 preview or JPEG/HEIF SDR export
```

The source-to-working and working-to-output conversions remain Core Image responsibilities. Technical and Creative LUT ordering is unchanged from Phase 5.

## Export behavior

- `SDR (sRGB)` is the default for JPEG and HEIF. HDR source content is tone mapped after all edits, so a standard display/export does not receive unclamped HDR values.
- `HDR (10-bit HEIF)` is offered in the export sheets. Selecting it forces HEIF and rejects non-HDR sources before rendering.
- The HDR encoder uses the long-lived pipeline context's `heif10Representation`, with a Rec.2100 HLG output color space. Metadata is retained through the CI image properties; GPS is removed when the existing privacy switch is off.
- Batch export uses the same validation per item. A non-HDR item fails with an explicit error while the sequential queue continues with the remaining items.

`CIToneMapHeadroom` is available from iOS 18. On an older OS, SDR JPEG/HEIF source behavior is unchanged, but converting an HDR source to SDR reports that the system tone mapper is unavailable rather than silently clipping it.

## Display behavior and verification

The editor's primary and original previews request `UIImageView.preferredImageDynamicRange = .high`; SDR images are unaffected. Whether highlights are actually brighter depends on the physical display's EDR headroom and the current system appearance/brightness policy, so simulator pixels alone are not proof of visual HDR output.

Manual verification required:

- Import an iPhone HDR HEIF (including a gain-map asset) and an HLG camera file on an EDR-capable iPhone; compare the preview's highlight detail against Photos.
- Export both SDR and HDR versions after exposure, HSL, curves and a Technical LUT. Inspect the SDR file on a conventional display for roll-off and the HDR HEIF on an HDR-capable device for retained highlights.
- Use the Photos save/share/files flows for the generated HDR HEIF, and verify GPS removal with the privacy switch disabled.
- Measure preview and export memory/latency on 12MP, 24MP and 48MP HDR camera assets. The repository has no redistributable real HDR fixture, so that hardware validation remains manual.
