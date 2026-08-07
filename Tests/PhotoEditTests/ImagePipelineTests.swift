import CoreImage
import ImageIO
import XCTest
@testable import PhotoEdit

final class ImagePipelineTests: XCTestCase {
    private let source = CIImage(color: CIColor(red: 0.22, green: 0.48, blue: 0.83, alpha: 1)).cropped(to: CGRect(x: 0, y: 0, width: 1024, height: 640))

    func testIdentityLUTMatchesBaseRender() async throws {
        let pipeline = ImagePipeline()
        let state = EditState()
        let base = try await pipeline.render(image: source, state: state, lut: nil, mode: .preview(maximumDimension: 256))
        var withLUT = state
        withLUT.lut.intensity = 1
        let output = try await pipeline.render(image: source, state: withLUT, lut: TestLUTFactory.identityLUT(), mode: .preview(maximumDimension: 256))
        XCTAssertEqual(base.width, output.width)
        XCTAssertEqual(base.height, output.height)
        assertPixelsEqual(pixelBytes(base), pixelBytes(output), tolerance: 1)
    }

    func testLUTZeroPercentMatchesBaseRender() async throws {
        let pipeline = ImagePipeline()
        let base = try await pipeline.render(image: source, state: .initial, lut: nil, mode: .preview(maximumDimension: 256))
        var state = EditState()
        state.lut.intensity = 0
        let output = try await pipeline.render(image: source, state: state, lut: TestLUTFactory.identityLUT(), mode: .preview(maximumDimension: 256))
        XCTAssertEqual(pixelBytes(base), pixelBytes(output))
    }

    func testPreviewDownsamplesButFullExportDoesNot() async throws {
        let pipeline = ImagePipeline()
        let preview = try await pipeline.render(image: source, state: .initial, lut: nil, mode: .preview(maximumDimension: 256))
        let exported = try await pipeline.render(image: source, state: .initial, lut: nil, mode: .export(maximumDimension: nil))
        XCTAssertLessThanOrEqual(max(preview.width, preview.height), 256)
        XCTAssertEqual(exported.width, 1024)
        XCTAssertEqual(exported.height, 640)
    }

    func testSquareCropIsAppliedNonDestructively() async throws {
        let pipeline = ImagePipeline()
        var state = EditState()
        state.transform.crop.aspectRatio = .oneToOne
        let output = try await pipeline.render(image: source, state: state, lut: nil, mode: .export(maximumDimension: nil))
        XCTAssertEqual(output.width, output.height)
        XCTAssertEqual(source.extent.width, 1024)
    }

    func testHSLDesaturatesSelectedRedRange() async throws {
        let redSource = CIImage(color: CIColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1)).cropped(to: CGRect(x: 0, y: 0, width: 128, height: 128))
        var state = EditState()
        state.hsl.red.saturation = -100
        let pipeline = ImagePipeline()
        let output = try await pipeline.render(image: redSource, state: state, lut: nil, mode: .preview(maximumDimension: 128))
        let pixel = pixelBytes(output)
        XCTAssertLessThanOrEqual(abs(Int(pixel[0]) - Int(pixel[1])), 2)
        XCTAssertLessThanOrEqual(abs(Int(pixel[1]) - Int(pixel[2])), 2)
    }

    func testToneCurveChangesSelectedChannel() async throws {
        var state = EditState()
        var redCurve = state.curves.red
        redCurve.movePoint(id: "end", x: 1, y: 0.4)
        state.curves.red = redCurve
        let pipeline = ImagePipeline()
        let base = try await pipeline.render(image: source, state: .initial, lut: nil, mode: .preview(maximumDimension: 128))
        let curved = try await pipeline.render(image: source, state: state, lut: nil, mode: .preview(maximumDimension: 128))
        XCTAssertLessThan(pixelBytes(curved)[0], pixelBytes(base)[0])
        XCTAssertLessThanOrEqual(abs(Int(pixelBytes(curved)[1]) - Int(pixelBytes(base)[1])), 1)
    }

    func testHistogramUsesPreviewSource() async throws {
        let pipeline = ImagePipeline()
        let histogram = try await pipeline.histogram(for: source, maximumDimension: 512)
        XCTAssertEqual(histogram.red.reduce(0, +), 512 * 320)
        XCTAssertEqual(histogram.green.reduce(0, +), 512 * 320)
        XCTAssertEqual(histogram.blue.reduce(0, +), 512 * 320)
        XCTAssertEqual(histogram.luminance.reduce(0, +), 512 * 320)
        let redPeak = histogram.red.enumerated().max { $0.element < $1.element }?.offset
        let greenPeak = histogram.green.enumerated().max { $0.element < $1.element }?.offset
        let bluePeak = histogram.blue.enumerated().max { $0.element < $1.element }?.offset
        XCTAssertNotEqual(redPeak, greenPeak)
        XCTAssertNotEqual(greenPeak, bluePeak)
    }

    func testJPEGExportCreatesNewDecodableFile() async throws {
        let asset = ImageAsset(
            id: UUID(), sourceName: "Test", fullResolutionImage: source, originalData: Data(), pixelWidth: 1024, pixelHeight: 640, metadata: [:], sourceType: .png
        )
        let output = try await ImageExporter.export(asset: asset, state: .initial, lut: nil, settings: ExportSettings(format: .jpeg, maximumDimension: nil, jpegQuality: 0.9, keepLocation: false))
        defer { try? FileManager.default.removeItem(at: output.fileURL) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.fileURL.path))
        XCTAssertNotNil(CGImageSourceCreateWithData(output.data as CFData, nil))
        XCTAssertEqual(output.type, .jpeg)
    }

    private func pixelBytes(_ image: CGImage) -> [UInt8] {
        guard let data = image.dataProvider?.data else { return [] }
        guard let bytes = CFDataGetBytePtr(data) else { return [] }
        return Array(UnsafeBufferPointer(start: bytes, count: CFDataGetLength(data)))
    }

    private func assertPixelsEqual(_ lhs: [UInt8], _ rhs: [UInt8], tolerance: UInt8, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs.count, rhs.count, file: file, line: line)
        for (left, right) in zip(lhs, rhs) {
            XCTAssertLessThanOrEqual(abs(Int(left) - Int(right)), Int(tolerance), file: file, line: line)
        }
    }
}
