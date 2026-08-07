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
}
