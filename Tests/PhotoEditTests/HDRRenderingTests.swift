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

    private func pixelByteSum(_ image: CGImage) -> Int {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return 0 }
        return Array(UnsafeBufferPointer(start: bytes, count: CFDataGetLength(data))).reduce(0) { $0 + Int($1) }
    }
}
