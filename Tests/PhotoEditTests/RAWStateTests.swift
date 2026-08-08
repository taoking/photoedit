import XCTest
@testable import PhotoEdit

final class RAWStateTests: XCTestCase {
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
}
