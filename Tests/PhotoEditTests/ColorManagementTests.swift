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
            colorMetadata: .sRGB
        )
        let creative = TestLUTFactory.identityLUT()
        let plan = try await pipeline.colorRenderPlan(source: .sRGB, technicalLUT: technical, creativeLUT: creative)
        XCTAssertEqual(plan.source, .sRGB)
        XCTAssertEqual(plan.working, .extendedLinearSRGB)
        XCTAssertTrue(plan.hasTechnicalTransform)
        XCTAssertTrue(plan.hasCreativeLUT)
        XCTAssertEqual(plan.output, .sRGB)
    }

    func testTechnicalLUTRejectsMismatchedSourceEncoding() async throws {
        let technical = TestLUTFactory.identityLUT().configured(
            kind: .technical,
            colorMetadata: LUTColorMetadata(inputColorSpace: .rec709, outputColorSpace: .rec709)
        )
        let pipeline = ImagePipeline()
        do {
            _ = try await pipeline.colorRenderPlan(source: .sRGB, technicalLUT: technical, creativeLUT: nil)
            XCTFail("Technical LUT must not apply to a mismatched source encoding")
        } catch let error as ColorManagementError {
            guard case .incompatibleTechnicalLUT = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testTechnicalLUTRejectsCrossEncodingEvenWhenSourceMatchesInput() async throws {
        let technical = TestLUTFactory.identityLUT().configured(
            kind: .technical,
            colorMetadata: LUTColorMetadata(inputColorSpace: .rec709, outputColorSpace: .sRGB)
        )
        let pipeline = ImagePipeline()

        do {
            _ = try await pipeline.colorRenderPlan(source: .rec709, technicalLUT: technical, creativeLUT: nil)
            XCTFail("Cross-encoding Technical LUT must be rejected")
        } catch let error as ColorManagementError {
            guard case .crossEncodingTechnicalLUTUnsupported = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testTechnicalLUTRejectsUnsupportedSLog3Encoding() async throws {
        let technical = TestLUTFactory.identityLUT().configured(
            kind: .technical,
            colorMetadata: LUTColorMetadata(
                inputEncoding: ColorEncodingDescriptor(primaries: .sonySGamut3, transferFunction: .sLog3),
                outputEncoding: ColorEncodingDescriptor(primaries: .sonySGamut3, transferFunction: .sLog3)
            )
        )
        let pipeline = ImagePipeline()

        do {
            _ = try await pipeline.colorRenderPlan(source: .sRGB, technicalLUT: technical, creativeLUT: nil)
            XCTFail("Unsupported S-Log3 encoding must be rejected")
        } catch let error as ColorManagementError {
            guard case .unsupportedLUTEncoding = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testLegacyLUTMetadataMigratesToSeparateEncodingFields() throws {
        let legacy = """
        {"inputColorSpace":"sRGB","outputColorSpace":"rec709"}
        """.data(using: .utf8)!
        let metadata = try JSONDecoder().decode(LUTColorMetadata.self, from: legacy)
        XCTAssertEqual(metadata.inputEncoding, ColorEncodingDescriptor(primaries: .sRGBRec709, transferFunction: .sRGB))
        XCTAssertEqual(metadata.outputEncoding, ColorEncodingDescriptor(primaries: .sRGBRec709, transferFunction: .rec709))
        XCTAssertTrue(metadata.isImplementedByPhotoPipeline)
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
