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

    func testRasterizedBrushKeepsNormalizedGeometryAcrossPreviewAndExport() async throws {
        let source = CIImage(color: CIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 192, height: 192))
        var state = EditState()
        var brush = LocalAdjustment.brush()
        brush.adjustments.exposure = 3
        brush.mask = .brush(BrushMask(
            points: [NormalizedPoint(x: 0.22, y: 0.76), NormalizedPoint(x: 0.28, y: 0.76)],
            size: 0.16,
            hardness: 1
        ))
        state.localAdjustments = [brush]
        let pipeline = ImagePipeline()
        let preview = try await pipeline.render(image: source, state: state, lut: nil, mode: .preview(maximumDimension: 96))
        let exported = try await pipeline.render(image: source, state: state, lut: nil, mode: .export(maximumDimension: nil))
        let previewCentroid = brightCentroid(preview)
        let exportCentroid = brightCentroid(exported)

        XCTAssertGreaterThan(previewCentroid.weight, 0)
        XCTAssertGreaterThan(exportCentroid.weight, 0)
        XCTAssertEqual(previewCentroid.x, exportCentroid.x, accuracy: 0.03)
        XCTAssertEqual(previewCentroid.y, exportCentroid.y, accuracy: 0.03)
    }

    func testEmptyBrushMaskKeepsBackgroundUnchanged() async throws {
        let source = CIImage(color: CIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        var state = EditState()
        var brush = LocalAdjustment.brush()
        brush.adjustments.exposure = 3
        brush.mask = .brush(BrushMask(points: [], size: 0.4, hardness: 1))
        state.localAdjustments = [brush]
        let pipeline = ImagePipeline()

        let base = try await pipeline.render(image: source, state: .initial, lut: nil, mode: .preview(maximumDimension: 64))
        let output = try await pipeline.render(image: source, state: state, lut: nil, mode: .preview(maximumDimension: 64))
        XCTAssertEqual(pixelByteSum(output), pixelByteSum(base))
    }

    func testRasterizedBrushUsesSingleGrayChannelWithWhiteActiveAndBlackInactive() throws {
        let brush = BrushMask(points: [NormalizedPoint(x: 0.5, y: 0.5)], size: 0.4, hardness: 1)
        let image = try XCTUnwrap(LocalAdjustmentProcessor.rasterizedBrushMask(brush, width: 31, height: 19))
        let data = try XCTUnwrap(image.dataProvider?.data)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))

        XCTAssertEqual(image.bitsPerPixel, 8)
        XCTAssertEqual(image.alphaInfo, .none)
        XCTAssertLessThanOrEqual(image.bytesPerRow, 32) // 31 BPP + optional row alignment
        XCTAssertEqual(bytes[9 * image.bytesPerRow + 15], 255)
        XCTAssertEqual(bytes[0], 0)
    }

    private func pixelByteSum(_ image: CGImage) -> Int {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return 0 }
        return Array(UnsafeBufferPointer(start: bytes, count: CFDataGetLength(data))).reduce(0) { $0 + Int($1) }
    }

    private func brightCentroid(_ image: CGImage) -> (x: Double, y: Double, weight: Double) {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return (0, 0, 0) }
        var total = 0.0
        var xTotal = 0.0
        var yTotal = 0.0
        for y in 0 ..< image.height {
            let row = bytes.advanced(by: y * image.bytesPerRow)
            for x in 0 ..< image.width {
                let value = max(0, Double(row[x * 4]) - 26)
                total += value
                xTotal += Double(x) * value
                yTotal += Double(y) * value
            }
        }
        guard total > 0 else { return (0, 0, 0) }
        return (xTotal / total / Double(image.width), yTotal / total / Double(image.height), total)
    }
}
