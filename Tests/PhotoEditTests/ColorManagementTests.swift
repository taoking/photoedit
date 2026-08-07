import CoreImage
import XCTest
@testable import PhotoEdit

final class ColorManagementTests: XCTestCase {
    func testLUTMetadataRoundTripsAndDoesNotInventASRGBProfile() throws {
        let parsed = try CUBEParser.parse(text: TestLUTFactory.identityText(dimension: 17))
        XCTAssertFalse(parsed.colorMetadata.isComplete)

        let metadata = LUTColorMetadata(inputColorSpace: .rec709HLG, outputColorSpace: .displayP3)
        let decoded = try JSONDecoder().decode(LUTColorMetadata.self, from: JSONEncoder().encode(metadata))
        XCTAssertEqual(decoded, metadata)
    }

    func testColorPlanPlacesTechnicalBeforeCreativeAndUsesLinearWorkingSpace() async throws {
        let pipeline = ImagePipeline()
        let technical = TestLUTFactory.identityLUT().configured(
            kind: .technical,
            colorMetadata: LUTColorMetadata(inputColorSpace: .rec709, outputColorSpace: .sRGB)
        )
        let creative = TestLUTFactory.identityLUT()
        let plan = try await pipeline.colorRenderPlan(source: .displayP3, technicalLUT: technical, creativeLUT: creative)
        XCTAssertEqual(plan.source, .displayP3)
        XCTAssertEqual(plan.working, .linearSRGB)
        XCTAssertTrue(plan.hasTechnicalTransform)
        XCTAssertTrue(plan.hasCreativeLUT)
        XCTAssertEqual(plan.output, .sRGB)
    }

    func testPipelineRejectsCreativeLUTWithUnknownColorMetadata() async throws {
        let source = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 24, height: 24))
        let pipeline = ImagePipeline()
        let unknownCreative = try CUBEParser.parse(text: TestLUTFactory.identityText(dimension: 17))
        await XCTAssertThrowsErrorAsync {
            try await pipeline.render(image: source, state: .initial, lut: unknownCreative, mode: .preview(maximumDimension: 24))
        }
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @escaping () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {
        XCTAssertTrue(error is ColorManagementError, "Unexpected error: \(error)", file: file, line: line)
    }
}
