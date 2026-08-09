import CoreImage
import ImageIO
import XCTest
@testable import PhotoEdit

final class ImagePipelineTests: XCTestCase {
    private let source = ImagePipelineTests.profiledImage(red: 0.22, green: 0.48, blue: 0.83, width: 1024, height: 640)

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

    func testTechnicalIdentityLUTIsAppliedBeforeTheCreativeStage() async throws {
        let pipeline = ImagePipeline()
        let base = try await pipeline.render(image: source, state: .initial, lut: nil, mode: .preview(maximumDimension: 256))
        let technical = TestLUTFactory.identityLUT().configured(
            kind: .technical,
            colorMetadata: LUTColorMetadata(inputColorSpace: .sRGB, outputColorSpace: .sRGB)
        )
        let output = try await pipeline.render(
            image: source,
            state: .initial,
            lut: nil,
            technicalLUT: technical,
            mode: .preview(maximumDimension: 256)
        )
        assertPixelsEqual(pixelBytes(base), pixelBytes(output), tolerance: 1)
    }

    func testRec709TechnicalIdentityLUTMatchesBaseRender() async throws {
        let rec709Source = Self.profiledImage(
            red: 0.22,
            green: 0.48,
            blue: 0.83,
            width: 1024,
            height: 640,
            colorSpace: .rec709
        )
        let pipeline = ImagePipeline()
        let base = try await pipeline.render(
            image: rec709Source,
            state: .initial,
            lut: nil,
            sourceColorSpace: .rec709,
            mode: .preview(maximumDimension: 256)
        )
        let technical = TestLUTFactory.identityLUT().configured(
            kind: .technical,
            colorMetadata: LUTColorMetadata(inputColorSpace: .rec709, outputColorSpace: .rec709)
        )
        let output = try await pipeline.render(
            image: rec709Source,
            state: .initial,
            lut: nil,
            technicalLUT: technical,
            sourceColorSpace: .rec709,
            mode: .preview(maximumDimension: 256)
        )

        XCTAssertEqual(base.width, output.width)
        XCTAssertEqual(base.height, output.height)
        assertPixelsEqual(pixelBytes(base), pixelBytes(output), tolerance: 1)
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
        let redSource = Self.profiledImage(red: 0.9, green: 0.1, blue: 0.1, width: 128, height: 128)
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

    func testHistogramReflectsRenderedExposureInsteadOfOriginalSource() async throws {
        let pipeline = ImagePipeline()
        let base = try await pipeline.render(image: source, state: .initial, lut: nil, mode: .preview(maximumDimension: 128))
        var brighterState = EditState()
        brighterState.light.exposure = 1
        let brighter = try await pipeline.render(image: source, state: brighterState, lut: nil, mode: .preview(maximumDimension: 128))
        let baseHistogram = try await pipeline.histogram(for: base)
        let brighterHistogram = try await pipeline.histogram(for: brighter)

        XCTAssertGreaterThan(histogramMean(brighterHistogram.red), histogramMean(baseHistogram.red))
        XCTAssertGreaterThan(histogramMean(brighterHistogram.luminance), histogramMean(baseHistogram.luminance))
    }

    func testLUTDomainNormalizesBeforeEnteringCube() throws {
        let identity = TestLUTFactory.identityLUT()
        let domainLUT = LUT(
            title: "-1 to 1 identity",
            dimension: identity.dimension,
            domainMin: RGBColor(red: -1, green: -1, blue: -1),
            domainMax: RGBColor(red: 1, green: 1, blue: 1),
            values: identity.values,
            kind: .creative,
            colorMetadata: .sRGB
        )
        let source = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        let output = try LUTProcessor.apply(domainLUT, to: source)
        let image = try XCTUnwrap(CIContext().createCGImage(output, from: output.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!))
        // Cube 输出的线性 0.5 在最终 sRGB 8-bit 编码中约为 187；若忽略 DOMAIN，
        // 黑色输入会错误落在 cube 的 0 坐标而得到 0。
        XCTAssertEqual(pixelBytes(image)[0], 187, accuracy: 3)
    }

    func testExportSanitizesOrientationDimensionsAndLocationAfterTransformAndResize() async throws {
        let metadata: [CFString: Any] = [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyPixelWidth: 1024,
            kCGImagePropertyPixelHeight: 640,
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFOrientation: 6],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifPixelXDimension: 1024,
                kCGImagePropertyExifPixelYDimension: 640,
                kCGImagePropertyExifDateTimeOriginal: "2026:07:15 18:30:21"
            ],
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 31.2]
        ]
        let asset = ImageAsset(
            id: UUID(), sourceName: "Oriented.jpg", fullResolutionImage: source, originalData: Data(),
            pixelWidth: 1024, pixelHeight: 640, metadata: metadata, sourceType: .jpeg,
            sourceColorSpace: .sRGB, sourceHeadroom: 1, rawSource: nil
        )
        var state = EditState()
        state.transform.rotation = 90
        state.transform.crop.aspectRatio = .oneToOne
        let output = try await ImageExporter.export(
            asset: asset,
            state: state,
            lut: nil,
            settings: ExportSettings(format: .jpeg, maximumDimension: 96, jpegQuality: 0.9, keepLocation: false)
        )
        defer { try? FileManager.default.removeItem(at: output.fileURL) }

        let source = try XCTUnwrap(CGImageSourceCreateWithData(output.data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual((properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue, 1)
        XCTAssertEqual((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, image.width)
        XCTAssertEqual((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, image.height)
        let tiff = try XCTUnwrap(properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])
        let exif = try XCTUnwrap(properties[kCGImagePropertyExifDictionary] as? [CFString: Any])
        XCTAssertEqual((tiff[kCGImagePropertyTIFFOrientation] as? NSNumber)?.intValue, 1)
        XCTAssertEqual((exif[kCGImagePropertyExifPixelXDimension] as? NSNumber)?.intValue, image.width)
        XCTAssertEqual((exif[kCGImagePropertyExifPixelYDimension] as? NSNumber)?.intValue, image.height)
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
    }

    func testJPEGExportCreatesNewDecodableFile() async throws {
        let asset = ImageAsset(
            id: UUID(), sourceName: "Test", fullResolutionImage: source, originalData: Data(), pixelWidth: 1024, pixelHeight: 640, metadata: [:], sourceType: .png, sourceColorSpace: .sRGB, sourceHeadroom: 1, rawSource: nil
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

    private static func profiledImage(
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        width: Int,
        height: Int,
        colorSpace descriptor: ColorSpaceDescriptor = .sRGB
    ) -> CIImage {
        let colorSpace = descriptor.cgColorSpace
        let source = CIImage(color: CIColor(red: red, green: green, blue: blue, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        let cgImage = CIContext().createCGImage(source, from: source.extent, format: .RGBA8, colorSpace: colorSpace)!
        return CIImage(cgImage: cgImage, options: [.colorSpace: colorSpace])
    }

    private func assertPixelsEqual(_ lhs: [UInt8], _ rhs: [UInt8], tolerance: UInt8, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs.count, rhs.count, file: file, line: line)
        for (left, right) in zip(lhs, rhs) {
            XCTAssertLessThanOrEqual(abs(Int(left) - Int(right)), Int(tolerance), file: file, line: line)
        }
    }

    private func histogramMean(_ bins: [Int]) -> Double {
        let total = bins.reduce(0, +)
        guard total > 0 else { return 0 }
        return bins.enumerated().reduce(0.0) { partial, element in
            partial + Double(element.offset * element.element)
        } / Double(total)
    }
}
