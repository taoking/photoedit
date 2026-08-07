import CoreImage
import XCTest
@testable import PhotoEdit

@MainActor
final class LocalAdjustmentTests: XCTestCase {
    func testLocalAdjustmentsRoundTripWithoutChangingGlobalLight() throws {
        var state = EditState()
        state.light.exposure = 1
        var local = LocalAdjustment.radial()
        local.adjustments.exposure = 2
        state.localAdjustments = [local]

        let restored = try JSONDecoder().decode(EditState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(restored.light.exposure, 1)
        XCTAssertEqual(restored.localAdjustments, [local])
    }

    func testLegacyStateWithoutLocalAdjustmentsDecodesToEmptyMaskList() throws {
        var state = EditState()
        state.localAdjustments = [.linear()]
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        object.removeValue(forKey: "localAdjustments")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        XCTAssertEqual(try JSONDecoder().decode(EditState.self, from: legacyData).localAdjustments, [])
    }

    func testLinearRadialAndBrushMasksApplyOnlyThroughLocalPipeline() async throws {
        let source = CIImage(color: CIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 96, height: 96))
        let pipeline = ImagePipeline()
        let base = try await pipeline.render(image: source, state: .initial, lut: nil, mode: .preview(maximumDimension: 96))

        var linearState = EditState()
        var linear = LocalAdjustment.linear()
        linear.adjustments.exposure = 2
        linearState.localAdjustments = [linear]
        let linearOutput = try await pipeline.render(image: source, state: linearState, lut: nil, mode: .preview(maximumDimension: 96))

        var radialState = EditState()
        var radial = LocalAdjustment.radial()
        radial.adjustments.exposure = 2
        radialState.localAdjustments = [radial]
        let radialOutput = try await pipeline.render(image: source, state: radialState, lut: nil, mode: .preview(maximumDimension: 96))

        var brushState = EditState()
        var brush = LocalAdjustment.brush()
        brush.adjustments.exposure = 2
        brush.mask = .brush(BrushMask(points: [NormalizedPoint(x: 0.5, y: 0.5)], size: 0.45, hardness: 0.6))
        brushState.localAdjustments = [brush]
        let brushOutput = try await pipeline.render(image: source, state: brushState, lut: nil, mode: .preview(maximumDimension: 96))

        XCTAssertGreaterThan(pixelByteSum(linearOutput), pixelByteSum(base))
        XCTAssertGreaterThan(pixelByteSum(radialOutput), pixelByteSum(base))
        XCTAssertGreaterThan(pixelByteSum(brushOutput), pixelByteSum(base))
    }

    func testClipboardCanCopyLocalAdjustmentsIndependently() {
        let clipboard = AdjustmentClipboard()
        var source = EditState()
        source.localAdjustments = [.linear()]
        clipboard.copy(from: source)

        let pasted = clipboard.paste(into: .initial, groups: [.local])
        XCTAssertEqual(pasted?.localAdjustments, source.localAdjustments)
        XCTAssertEqual(pasted?.light, EditState.initial.light)
    }

    private func pixelByteSum(_ image: CGImage) -> Int {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return 0 }
        return Array(UnsafeBufferPointer(start: bytes, count: CFDataGetLength(data))).reduce(0) { $0 + Int($1) }
    }
}
