import CoreImage
import ImageIO
import XCTest
@testable import PhotoEdit

final class HDRRenderingTests: XCTestCase {
    func testSDRPlanKeepsSRGBOutputForSDRAndHDRSources() throws {
        let plan = try HDRRendering.makePlan(
            sourceColorSpace: .rec2100HLG,
            sourceHeadroom: 2,
            target: .sdr,
            format: .jpeg
        )
        XCTAssertTrue(plan.sourceIsHDR)
        XCTAssertEqual(plan.target, .sdr)
        XCTAssertEqual(plan.outputColorSpace, .sRGB)
    }

    func testHDRPlanRequiresHEIFAndAnHDRSource() {
        XCTAssertThrowsError(try HDRRendering.makePlan(
            sourceColorSpace: .rec2100HLG,
            sourceHeadroom: 2,
            target: .hdr,
            format: .jpeg
        )) { XCTAssertEqual($0 as? HDRRenderingError, .hdrRequiresHEIF) }

        XCTAssertThrowsError(try HDRRendering.makePlan(
            sourceColorSpace: .sRGB,
            sourceHeadroom: 1,
            target: .hdr,
            format: .heif
        )) { XCTAssertEqual($0 as? HDRRenderingError, .hdrRequiresHDRSource) }
    }

    func testHDRPlanTargetsRec2100HLG() throws {
        let plan = try HDRRendering.makePlan(
            sourceColorSpace: .rec2100HLG,
            sourceHeadroom: 2,
            target: .hdr,
            format: .heif
        )
        XCTAssertEqual(plan.outputColorSpace, .rec2100HLG)
        XCTAssertEqual(plan.sourceHeadroom, 2)
    }

    func testHDRPreviewUsesHalfFloatWhileSDRPreviewStaysEightBit() async throws {
        let source = CIImage(color: CIColor(red: 1.6, green: 0.7, blue: 0.2, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        let pipeline = ImagePipeline()
        let hdr = try await pipeline.render(
            image: source,
            state: .initial,
            lut: nil,
            sourceColorSpace: .rec2100HLG,
            sourceHeadroom: 2,
            dynamicRange: .hdr,
            mode: .preview(maximumDimension: 64)
        )
        let sdr = try await pipeline.render(
            image: source,
            state: .initial,
            lut: nil,
            sourceColorSpace: .rec2100HLG,
            sourceHeadroom: 2,
            dynamicRange: .sdr,
            mode: .preview(maximumDimension: 64)
        )
        XCTAssertEqual(hdr.bitsPerComponent, 16)
        XCTAssertEqual(sdr.bitsPerComponent, 8)
        XCTAssertGreaterThan(pixelByteSum(sdr), 0)
    }

    func testHDRHEIFExportProducesDecodableHEIF() async throws {
        let source = CIImage(color: CIColor(red: 1.6, green: 0.7, blue: 0.2, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        let asset = ImageAsset(
            id: UUID(),
            sourceName: "HDR-Test.heic",
            fullResolutionImage: source,
            originalData: Data(),
            pixelWidth: 64,
            pixelHeight: 64,
            metadata: [:],
            sourceType: .heic,
            sourceColorSpace: .rec2100HLG,
            sourceHeadroom: 2,
            rawSource: nil
        )
        let output = try await ImageExporter.export(
            asset: asset,
            state: .initial,
            lut: nil,
            settings: ExportSettings(format: .heif, dynamicRange: .hdr, maximumDimension: nil, jpegQuality: 0.9, keepLocation: false)
        )
        defer { try? FileManager.default.removeItem(at: output.fileURL) }
        XCTAssertEqual(output.type, ExportFormat.heif.utType)
        XCTAssertNotNil(CGImageSourceCreateWithData(output.data as CFData, nil))
    }

    func testExtendedRangeIdentityHSLAndCurvePreserveHeadroom() async throws {
        let source = CIImage(color: CIColor(red: 2, green: 1.5, blue: 1.2, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
        let pipeline = ImagePipeline()
        let output = try await pipeline.render(
            image: source,
            state: .initial,
            lut: nil,
            sourceColorSpace: .rec2100HLG,
            sourceHeadroom: 2,
            dynamicRange: .hdr,
            mode: .preview(maximumDimension: 16)
        )
        XCTAssertGreaterThan(halfFloatPixel(output, component: 0), 1)
        XCTAssertGreaterThan(halfFloatPixel(output, component: 1), 1)
        XCTAssertGreaterThan(halfFloatPixel(output, component: 2), 1)
    }

    func testHDRRejectsHSLCurveAndLUTInsteadOfClippingHighlights() async throws {
        let source = CIImage(color: CIColor(red: 2, green: 1.5, blue: 1.2, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
        let pipeline = ImagePipeline()

        var hsl = EditState()
        hsl.hsl.red.saturation = -10
        await assertHDRFailure(.hslUnavailableForHDR) {
            try await pipeline.render(image: source, state: hsl, lut: nil, sourceColorSpace: .rec2100HLG, sourceHeadroom: 2, dynamicRange: .hdr, mode: .preview(maximumDimension: 16))
        }

        var curves = EditState()
        var red = curves.curves.red
        red.movePoint(id: "end", x: 1, y: 0.8)
        curves.curves.red = red
        await assertHDRFailure(.toneCurveUnavailableForHDR) {
            try await pipeline.render(image: source, state: curves, lut: nil, sourceColorSpace: .rec2100HLG, sourceHeadroom: 2, dynamicRange: .hdr, mode: .preview(maximumDimension: 16))
        }

        await assertHDRFailure(.lutUnavailableForHDR) {
            try await pipeline.render(image: source, state: .initial, lut: TestLUTFactory.identityLUT(), sourceColorSpace: .rec2100HLG, sourceHeadroom: 2, dynamicRange: .hdr, mode: .preview(maximumDimension: 16))
        }
    }

    private func pixelByteSum(_ image: CGImage) -> Int {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return 0 }
        return Array(UnsafeBufferPointer(start: bytes, count: CFDataGetLength(data))).reduce(0) { $0 + Int($1) }
    }

    private func halfFloatPixel(_ image: CGImage, component: Int) -> Float {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return 0 }
        let offset = component * MemoryLayout<UInt16>.size
        let bits = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
        return Float(Float16(bitPattern: bits))
    }

    private func assertHDRFailure(
        _ expected: HDRRenderingError,
        expression: @escaping () async throws -> CGImage,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected HDR rejection", file: file, line: line)
        } catch let error as HDRRenderingError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}
