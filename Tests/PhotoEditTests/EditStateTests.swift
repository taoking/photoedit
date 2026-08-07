import XCTest
@testable import PhotoEdit

final class EditStateTests: XCTestCase {
    func testStateRoundTripsThroughJSONAndResets() throws {
        var state = EditState()
        state.light.exposure = 1.25
        state.color.temperature = 20
        state.detail.sharpness = 50
        state.lut.selectedLUTID = UUID()
        state.transform.crop.aspectRatio = .threeToTwo
        state.transform.rotation = 90

        let decoded = try JSONDecoder().decode(EditState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded, state)
        state.reset()
        XCTAssertEqual(state, .initial)
    }

    func testAdjustmentMapperUsesFilterUnitsRatherThanUIUnits() {
        XCTAssertEqual(AdjustmentMapper.contrast(50), 1.5)
        XCTAssertEqual(AdjustmentMapper.saturation(-100), 0)
        XCTAssertEqual(AdjustmentMapper.exposureEV(9), 5)
        XCTAssertEqual(AdjustmentMapper.temperature(100), 8500)
        XCTAssertEqual(AdjustmentMapper.vibrance(-50), -0.5)
    }

    func testTransformRotatesInQuarterTurns() {
        var transform = TransformAdjustment()
        transform.rotateClockwise()
        transform.rotateClockwise()
        XCTAssertEqual(transform.rotation, 180)
    }
}
