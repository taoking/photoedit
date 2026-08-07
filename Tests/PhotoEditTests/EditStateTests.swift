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

    func testHSLCanResetOneChannelOrAllChannels() {
        var hsl = HSLAdjustments()
        hsl.red.saturation = -80
        hsl.blue.hue = 25
        hsl.reset(.red)
        XCTAssertEqual(hsl.red, HSLChannelAdjustment())
        XCTAssertEqual(hsl.blue.hue, 25)
        hsl.resetAll()
        XCTAssertTrue(hsl.isIdentity)
    }

    func testCurveKeepsEndpointsAndPreventsCrossing() throws {
        var curve = ToneCurve()
        curve.addPoint(x: 0.25, y: 0.6)
        curve.addPoint(x: 0.75, y: 0.4)
        let middle = try XCTUnwrap(curve.points.first(where: { $0.id != "start" && $0.id != "end" }))
        curve.movePoint(id: middle.id, x: 2, y: 0.8)
        XCTAssertEqual(curve.points.first?.x, 0)
        XCTAssertEqual(curve.points.last?.x, 1)
        XCTAssertLessThan(curve.points[1].x, curve.points[2].x)
        curve.removePoint(id: "start")
        XCTAssertEqual(curve.points.first?.id, "start")
        let decoded = try JSONDecoder().decode(ToneCurve.self, from: JSONEncoder().encode(curve))
        XCTAssertEqual(decoded, curve)
    }
}
