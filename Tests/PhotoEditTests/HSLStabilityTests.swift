import CoreImage
import XCTest
@testable import PhotoEdit

@MainActor
final class HSLStabilityTests: XCTestCase {
    func testDisplayedNeutralValuesCanonicalizeToExactIdentity() {
        var state = EditState.initial
        state.light.contrast = 0.49
        state.color.tint = -0.49
        state.hsl.orange.hue = 0.49
        state.localAdjustments = [.linear()]
        state.localAdjustments[0].adjustments.saturation = -0.49

        let canonical = state.canonicalized()

        XCTAssertEqual(canonical.light.contrast, 0)
        XCTAssertEqual(canonical.color.tint, 0)
        XCTAssertTrue(canonical.hsl.isIdentity)
        XCTAssertTrue(canonical.localAdjustments[0].adjustments.isIdentity)
    }

    func testRepeatedHueExcursionsReturnExactlyToInitialPixels() async throws {
        let pipeline = ImagePipeline()
        let source = try profiledImage(red: 0.78, green: 0.31, blue: 0.12)
        let baseline = try await render(source, state: .initial, pipeline: pipeline)
        var state = EditState.initial
        for value in [90.0, -90, 65, -40, 15, -15, 0] {
            state.hsl.orange.hue = value
            _ = try await render(source, state: state, pipeline: pipeline)
        }
        let returned = try await render(source, state: state, pipeline: pipeline)

        XCTAssertTrue(state.hsl.isIdentity)
        XCTAssertEqual(pixelBytes(returned), pixelBytes(baseline))
    }

    func testDisplayedZeroResidueDoesNotChangePixels() async throws {
        let pipeline = ImagePipeline()
        let source = try profiledImage(red: 0.78, green: 0.31, blue: 0.12)
        let baseline = try await render(source, state: .initial, pipeline: pipeline)
        var state = EditState.initial
        state.hsl.orange.hue = 0.49
        let output = try await render(source, state: state, pipeline: pipeline)

        XCTAssertEqual(pixelBytes(output), pixelBytes(baseline))
    }

    func testUnmatchedHSLChannelPreservesExtendedRangePixels() async throws {
        let pipeline = ImagePipeline()
        let source = try profiledImage(red: 0.72, green: 0.24, blue: 0.08)
        var exposureOnly = EditState.initial
        exposureOnly.light.exposure = 2
        let baseline = try await render(source, state: exposureOnly, pipeline: pipeline)

        var adjusted = exposureOnly
        adjusted.hsl.green.hue = 45
        let output = try await render(source, state: adjusted, pipeline: pipeline)

        XCTAssertEqual(pixelBytes(output), pixelBytes(baseline))
    }

    func testOverlappingChannelsWithSameAdjustmentDoNotDoubleTheEffect() async throws {
        let pipeline = ImagePipeline()
        let source = try profiledImage(red: 1, green: 0.5, blue: 0)
        var orangeOnly = EditState.initial
        orangeOnly.hsl.orange.hue = 30
        let single = try await render(source, state: orangeOnly, pipeline: pipeline)

        var overlapping = orangeOnly
        overlapping.hsl.red.hue = 30
        let combined = try await render(source, state: overlapping, pipeline: pipeline)

        XCTAssertEqual(pixelBytes(combined), pixelBytes(single))
    }

    func testRapidViewModelUpdatesPublishFinalNeutralState() async throws {
        let model = EditorViewModel(pipeline: ImagePipeline())
        let source = try profiledImage(red: 0.78, green: 0.31, blue: 0.12)
        let data = try XCTUnwrap(CIContext().jpegRepresentation(
            of: source,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            options: [:]
        ))
        model.loadImage(data: data, sourceName: "rapid.jpg")
        let initialRenderCompleted = await waitUntil {
            model.previewImage != nil && model.originalPreviewImage != nil && !model.isRendering
        }
        XCTAssertTrue(initialRenderCompleted)

        model.beginContinuousEdit()
        for value in [90.0, -90, 65, -40, 15, -15, 0.49] {
            model.updateContinuous { $0.hsl.orange.hue = value }
        }
        model.endContinuousEdit()
        let finalRenderCompleted = await waitUntil { !model.isRendering && model.state.hsl.isIdentity }
        XCTAssertTrue(finalRenderCompleted)

        XCTAssertEqual(
            pixelBytes(try XCTUnwrap(model.previewImage)),
            pixelBytes(try XCTUnwrap(model.originalPreviewImage))
        )
    }

    private func render(_ image: CIImage, state: EditState, pipeline: ImagePipeline) async throws -> CGImage {
        try await pipeline.render(image: image, state: state, lut: nil, mode: .preview(maximumDimension: 64))
    }

    private func profiledImage(red: CGFloat, green: CGFloat, blue: CGFloat) throws -> CIImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let source = CIImage(color: CIColor(red: red, green: green, blue: blue, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        let cgImage = try XCTUnwrap(CIContext().createCGImage(
            source,
            from: source.extent,
            format: .RGBA8,
            colorSpace: colorSpace
        ))
        return CIImage(cgImage: cgImage, options: [.colorSpace: colorSpace])
    }

    private func pixelBytes(_ image: CGImage) -> [UInt8] {
        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return [] }
        return Array(UnsafeBufferPointer(start: bytes, count: CFDataGetLength(data)))
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async -> Bool {
        for _ in 0..<300 {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }
}
