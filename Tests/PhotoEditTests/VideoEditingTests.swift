import AVFoundation
import CoreImage
import CoreVideo
import XCTest
@testable import PhotoEdit

@MainActor
final class VideoEditingTests: XCTestCase {
    func testVideoEditStateRoundTripsThroughJSON() throws {
        let id = UUID()
        let state = VideoEditState(exposure: 1.5, contrast: -20, saturation: 35, selectedLUTID: id, lutIntensity: 0.4)

        XCTAssertEqual(try JSONDecoder().decode(VideoEditState.self, from: JSONEncoder().encode(state)), state)
    }

    func testFrameProcessorAppliesBasicColorAndNormalizesOrientationExtent() throws {
        let source = CIImage(color: CIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 80, height: 40))
        let adjusted = try VideoFrameProcessor.apply(
            source,
            state: VideoEditState(exposure: 2, contrast: 0, saturation: 0, selectedLUTID: nil, lutIntensity: 1),
            lut: nil,
            transform: VideoFrameTransform(CGAffineTransform(rotationAngle: .pi / 2))
        )
        let context = CIContext()
        let baseImage = try XCTUnwrap(context.createCGImage(source, from: source.extent))
        let adjustedImage = try XCTUnwrap(context.createCGImage(adjusted, from: adjusted.extent))

        XCTAssertGreaterThan(pixelByteSum(adjustedImage), pixelByteSum(baseImage))
        XCTAssertEqual(adjusted.extent.origin, .zero)
        XCTAssertEqual(adjusted.extent.size.width, 40, accuracy: 0.001)
        XCTAssertEqual(adjusted.extent.size.height, 80, accuracy: 0.001)
    }

    func testVideoExporterWritesDecodableFilteredVideo() async throws {
        let inputURL = try await makeVideoFixture()
        defer { try? FileManager.default.removeItem(at: inputURL) }
        let asset = try await VideoAsset.importFromFile(url: inputURL)
        defer { try? FileManager.default.removeItem(at: asset.sourceURL) }

        let output = try await VideoExporter.export(
            asset: asset,
            state: VideoEditState(exposure: 1, contrast: 10, saturation: 10, selectedLUTID: nil, lutIntensity: 1),
            lut: nil
        )
        defer { try? FileManager.default.removeItem(at: output.fileURL) }
        let rendered = AVURLAsset(url: output.fileURL)
        let tracks = try await rendered.loadTracks(withMediaType: .video)
        let duration = try await rendered.load(.duration)

        XCTAssertFalse(tracks.isEmpty)
        XCTAssertGreaterThan(duration.seconds, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.fileURL.path))
    }

    func testVideoExporterAppliesPortraitPreferredTransformExactlyOnce() async throws {
        let portraitTransform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 40, ty: 0)
        let inputURL = try await makeVideoFixture(width: 80, height: 40, transform: portraitTransform)
        defer { try? FileManager.default.removeItem(at: inputURL) }
        let asset = try await VideoAsset.importFromFile(url: inputURL)
        defer { try? FileManager.default.removeItem(at: asset.sourceURL) }
        XCTAssertEqual(asset.width, 80)
        XCTAssertEqual(asset.height, 40)

        let output = try await VideoExporter.export(asset: asset, state: .init(), lut: nil)
        defer { try? FileManager.default.removeItem(at: output.fileURL) }
        let rendered = AVURLAsset(url: output.fileURL)
        let tracks = try await rendered.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let duration = try await rendered.load(.duration)
        let display = displayedSize(size: size, transform: transform)

        XCTAssertEqual(display.width, 40, accuracy: 0.01)
        XCTAssertEqual(display.height, 80, accuracy: 0.01)
        XCTAssertEqual(abs(size.width * size.height), 80 * 40, accuracy: 0.01)
        XCTAssertEqual(duration.seconds, asset.durationSeconds, accuracy: 0.1)
    }

    func testVideoExporterRejectsTechnicalLUTBeforeReadingSource() async {
        let technical = LUT(
            title: "Technical",
            dimension: 2,
            domainMin: .clear,
            domainMax: RGBColor(red: 1, green: 1, blue: 1),
            values: Array(repeating: RGBColor(red: 0, green: 0, blue: 0), count: 8),
            kind: .technical,
            colorMetadata: .sRGB
        )
        let unavailableAsset = VideoAsset(
            sourceURL: URL(fileURLWithPath: "/not-a-video.mov"),
            sourceName: "not-a-video.mov",
            durationSeconds: 1,
            width: 1,
            height: 1,
            frameTransform: VideoFrameTransform(.identity)
        )

        do {
            _ = try await VideoExporter.export(asset: unavailableAsset, state: VideoEditState(), lut: technical)
            XCTFail("Technical LUT must not reach the SDR video exporter")
        } catch let error as VideoEditorError {
            guard case .unsupportedLUTColorSpace = error else {
                return XCTFail("Unexpected video export error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    private func makeVideoFixture(
        width: Int = 64,
        height: Int = 48,
        transform: CGAffineTransform = .identity
    ) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )
        XCTAssertTrue(writer.canAdd(input))
        writer.add(input)
        input.transform = transform
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0 ..< 6 {
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing else { throw writer.error ?? FixtureError.writerFailed }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            var buffer: CVPixelBuffer?
            XCTAssertEqual(
                CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer),
                kCVReturnSuccess
            )
            guard let buffer else { throw FixtureError.pixelBufferCreationFailed }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, Int32(frame * 30), CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
        }
        input.markAsFinished()
        let completion = expectation(description: "fixture written")
        writer.finishWriting { completion.fulfill() }
        await fulfillment(of: [completion], timeout: 10)
        guard writer.status == .completed else { throw writer.error ?? FixtureError.writerFailed }
        return url
    }

    private func displayedSize(size: CGSize, transform: CGAffineTransform) -> CGSize {
        let rect = CGRect(origin: .zero, size: size).applying(transform).standardized
        return CGSize(width: rect.width, height: rect.height)
    }

    private func pixelByteSum(_ image: CGImage) -> Int {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return 0 }
        return Array(UnsafeBufferPointer(start: bytes, count: CFDataGetLength(data))).reduce(0) { $0 + Int($1) }
    }

    private enum FixtureError: Error {
        case writerNotReady
        case pixelBufferCreationFailed
        case writerFailed
    }
}
