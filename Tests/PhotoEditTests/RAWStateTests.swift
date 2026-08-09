import CoreGraphics
import CoreImage
import XCTest
@testable import PhotoEdit

@MainActor
final class RAWStateTests: XCTestCase {
    func testResetPreservesRAWStateAndClearsAllAdjustments() {
        let model = EditorViewModel()
        model.install(asset: Self.rawAsset(), scheduleRendering: false)
        XCTAssertTrue(model.asset?.isRAW == true)
        XCTAssertEqual(model.state.raw, RAWAdjustments())

        model.update { state in
            state.light.exposure = 1.25
            state.color.saturation = 42
            state.hsl.red.luminance = -25
            var curve = state.curves.blue
            curve.movePoint(id: "end", x: 1, y: 0.6)
            state.curves.blue = curve
            state.lut.selectedLUTID = UUID()
            state.lut.technicalLUTID = UUID()
            state.lut.intensity = 0.4
            state.localAdjustments = [.linear()]
            state.transform.rotation = 90
            state.transform.horizontalFlip = true
            state.raw?.exposure = 2
            state.raw?.temperature = 30
            state.raw?.tint = -12
            state.raw?.luminanceNoiseReduction = 0.4
            state.raw?.colorNoiseReduction = 0.3
            state.raw?.sharpness = 0.6
            state.raw?.detail = 1.2
            state.raw?.localTone = 0.8
            state.raw?.lensCorrectionEnabled = false
        }

        model.reset()

        XCTAssertEqual(model.state, EditorViewModel.defaultState(for: model.asset))
        guard let raw = model.state.raw else {
            return XCTFail("RAW reset must retain RAW adjustments")
        }
        XCTAssertEqual(raw.temperature, 0)
        XCTAssertEqual(raw.tint, 0)
        XCTAssertNil(raw.decoderOverrides.luminanceNoiseReduction)
        XCTAssertNil(raw.decoderOverrides.colorNoiseReduction)
        XCTAssertNil(raw.decoderOverrides.sharpness)
        XCTAssertNil(raw.decoderOverrides.detail)
        XCTAssertNil(raw.decoderOverrides.localTone)
        XCTAssertNil(raw.decoderOverrides.lensCorrectionEnabled)
        XCTAssertEqual(model.state.light, LightAdjustments())
        XCTAssertEqual(model.state.color, ColorAdjustments())
        XCTAssertTrue(model.state.hsl.isIdentity)
        XCTAssertTrue(model.state.curves.isIdentity)
        XCTAssertEqual(model.state.lut, LUTAdjustment())
        XCTAssertTrue(model.state.localAdjustments.isEmpty)
        XCTAssertEqual(model.state.transform, TransformAdjustment())
    }

    func testDefaultStateForNonRAWAssetRemainsInitial() {
        XCTAssertEqual(EditorViewModel.defaultState(for: Self.standardAsset()), .initial)
    }

    func testResetRAWStateRendersTheStandardPipeline() async throws {
        let resetState = EditorViewModel.defaultState(for: Self.rawAsset())
        let rendered = try await ImagePipeline().render(
            image: Self.standardAsset().fullResolutionImage,
            state: resetState,
            lut: nil,
            sourceColorSpace: .sRGB,
            mode: .preview(maximumDimension: 24)
        )
        XCTAssertEqual(rendered.width, 24)
        XCTAssertEqual(rendered.height, 24)
        XCTAssertNotNil(resetState.raw)
    }

    func testRAWAjustmentsAreCodableAndSeparateFromStandardAdjustments() throws {
        var state = EditState()
        state.light.exposure = 1
        state.raw = RAWAdjustments(exposure: 2, temperature: 35, tint: -4, luminanceNoiseReduction: 0.4, colorNoiseReduction: 0.3, sharpness: 0.6, detail: 1.2, localTone: 0.8, lensCorrectionEnabled: false)
        let decoded = try JSONDecoder().decode(EditState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded.light.exposure, 1)
        XCTAssertEqual(decoded.raw?.exposure, 2)
        XCTAssertEqual(decoded.raw?.temperature, 35)
        XCTAssertFalse(decoded.raw?.lensCorrectionEnabled ?? true)
    }

    func testCameraMetadataIsValueType() throws {
        let metadata = CameraMetadata(camera: "Sony ILCE-7CM2", lens: "FE 20-70mm F4 G", aperture: 4, shutterSeconds: 1.0 / 125, iso: 800, focalLength: 35, captureDate: .now)
        let decoded = try JSONDecoder().decode(CameraMetadata.self, from: JSONEncoder().encode(metadata))
        XCTAssertEqual(decoded.camera, "Sony ILCE-7CM2")
        XCTAssertEqual(decoded.focalLength, 35)
    }

    func testDefaultRAWWhiteBalancePreservesDecoderValuesAndUsesRelativeDeltas() {
        let defaultAdjustment = RAWAdjustments().whiteBalanceAdjustment
        XCTAssertTrue(defaultAdjustment.isIdentity)
        let preserved = defaultAdjustment.resolved(decoderTemperature: 5_250, decoderTint: -18)
        XCTAssertEqual(preserved.temperature, 5_250)
        XCTAssertEqual(preserved.tint, -18)

        let changed = RAWWhiteBalanceAdjustment(temperatureDelta: 25, tintDelta: 8)
            .resolved(decoderTemperature: 5_250, decoderTint: -18)
        XCTAssertEqual(changed.temperature, 5_750)
        XCTAssertEqual(changed.tint, -10)
    }

    func testDefaultRAWDecoderDependentControlsDoNotRequestOverrides() {
        let overrides = RAWAdjustments().decoderOverrides

        XCTAssertNil(overrides.luminanceNoiseReduction)
        XCTAssertNil(overrides.colorNoiseReduction)
        XCTAssertNil(overrides.sharpness)
        XCTAssertNil(overrides.detail)
        XCTAssertNil(overrides.localTone)
        XCTAssertNil(overrides.lensCorrectionEnabled)
    }

    func testExplicitRAWDecoderDependentControlsRequestClampedOverrides() {
        let overrides = RAWAdjustments(
            luminanceNoiseReduction: 1.5,
            colorNoiseReduction: -1,
            sharpness: 0.6,
            detail: 4,
            localTone: 0.8,
            lensCorrectionEnabled: false
        ).decoderOverrides

        XCTAssertEqual(overrides.luminanceNoiseReduction, 1)
        XCTAssertEqual(overrides.colorNoiseReduction, 0)
        XCTAssertEqual(overrides.sharpness, 0.6)
        XCTAssertEqual(overrides.detail, 3)
        XCTAssertEqual(overrides.localTone, 0.8)
        XCTAssertEqual(overrides.lensCorrectionEnabled, false)
    }

    func testLegacyRAWStateRemainsDecodableAndMigratesStoredValuesToOverrides() throws {
        let legacy = """
        {
          "raw": {
            "exposure": 0,
            "temperature": 0,
            "tint": 0,
            "luminanceNoiseReduction": 0,
            "colorNoiseReduction": 0.2,
            "sharpness": 0.3,
            "detail": 1.1,
            "localTone": 0.4,
            "lensCorrectionEnabled": true
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(EditState.self, from: legacy)
        XCTAssertEqual(decoded.raw?.decoderOverrides, RAWDecoderOverrides(
            luminanceNoiseReduction: 0,
            colorNoiseReduction: 0.2,
            sharpness: 0.3,
            detail: 1.1,
            localTone: 0.4,
            lensCorrectionEnabled: true
        ))
    }

    func testRAWMetadataParsesEXIFDateTimeOriginalAndTIFFFallbackWithoutInventingUTC() throws {
        let exif: [CFString: Any] = [kCGImagePropertyExifDateTimeOriginal: "2026:07:15 18:30:21"]
        let date = try XCTUnwrap(RAWImageSource.captureDate(exif: exif, tiff: nil))
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 7)
        XCTAssertEqual(components.day, 15)
        XCTAssertEqual(components.hour, 18)
        XCTAssertEqual(components.minute, 30)
        XCTAssertEqual(components.second, 21)

        let tiff: [CFString: Any] = [kCGImagePropertyTIFFDateTime: "2024:01:02 03:04:05"]
        XCTAssertNotNil(RAWImageSource.captureDate(exif: nil, tiff: tiff))
    }

    private static func standardAsset() -> ImageAsset {
        let image = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 24, height: 24))
        return ImageAsset(
            id: UUID(), sourceName: "Test.jpg", fullResolutionImage: image, originalData: Data(),
            pixelWidth: 24, pixelHeight: 24, metadata: [:], sourceType: .jpeg,
            sourceColorSpace: .sRGB, sourceHeadroom: 1, rawSource: nil
        )
    }

    private static func rawAsset() -> ImageAsset {
        let standard = standardAsset()
        return ImageAsset(
            id: standard.id, sourceName: "Test.dng", fullResolutionImage: standard.fullResolutionImage, originalData: Data(),
            pixelWidth: standard.pixelWidth, pixelHeight: standard.pixelHeight, metadata: [:], sourceType: .data,
            sourceColorSpace: .sRGB, sourceHeadroom: 1,
            rawSource: RAWImageSource(data: Data(), identifierHint: nil, metadata: CameraMetadata())
        )
    }
}
