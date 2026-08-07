import CoreImage
import XCTest
@testable import PhotoEdit

@MainActor
final class BatchWorkflowTests: XCTestCase {
    func testFilenameStrategiesPreserveExtensionAndNumbering() {
        var settings = ExportSettings()
        settings.format = .heif
        settings.filenameStrategy = .originalEdited
        XCTAssertEqual(settings.filename(for: "DSC_0123.ARW"), "DSC_0123-edited.heic")

        settings.filenameStrategy = .original
        XCTAssertEqual(settings.filename(for: "family/photo.jpg"), "photo.heic")

        settings.filenameStrategy = .sequential
        settings.filenamePrefix = "Japan 2026"
        XCTAssertEqual(settings.filename(for: "ignored.jpg", sequenceNumber: 7), "Japan 2026-007.heic")
    }

    func testRecentSettingsDeduplicatesAndPersists() {
        let suite = "PhotoEditTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let lut = UUID()
        let preset = UUID()
        var settings = ExportSettings()
        settings.filenameStrategy = .sequential

        let store = RecentSettingsStore(defaults: defaults)
        store.record(lut: lut)
        store.record(lut: lut)
        store.record(preset: preset)
        store.record(export: settings)

        let reopened = RecentSettingsStore(defaults: defaults)
        XCTAssertEqual(reopened.lutIDs, [lut])
        XCTAssertEqual(reopened.presetIDs, [preset])
        XCTAssertEqual(reopened.exportSettings, [settings])
    }

    func testQueueContinuesAfterAnIndividualFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let validURL = root.appendingPathComponent("valid.jpg")
        let image = CIImage(color: CIColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 80, height: 48))
        let data = try XCTUnwrap(CIContext().jpegRepresentation(of: image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!))
        try data.write(to: validURL)

        let settings = ExportSettings(format: .jpeg, maximumDimension: 64, jpegQuality: 0.9, keepLocation: false, filenameStrategy: .sequential, filenamePrefix: "Batch")
        let jobs = [
            BatchExportJob(id: UUID(), photo: BatchPhoto(url: validURL), state: .initial, lut: nil, technicalLUT: nil, settings: settings),
            BatchExportJob(id: UUID(), photo: BatchPhoto(url: root.appendingPathComponent("missing.jpg")), state: .initial, lut: nil, technicalLUT: nil, settings: settings)
        ]
        let recorder = ProgressRecorder()
        let results = await BatchExportQueue().run(jobs) { progress in
            await recorder.append(progress)
        }
        defer {
            for result in results {
                if case let .succeeded(_, output) = result { try? FileManager.default.removeItem(at: output.fileURL) }
            }
        }

        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.contains { if case .succeeded = $0 { true } else { false } })
        XCTAssertTrue(results.contains { if case .failed = $0 { true } else { false } })
        let recordedProgress = await recorder.snapshot()
        XCTAssertEqual(recordedProgress.last, BatchProgress(completed: 2, total: 2, currentID: nil))
    }
}

private actor ProgressRecorder {
    private(set) var values: [BatchProgress] = []
    func append(_ progress: BatchProgress) { values.append(progress) }
    func snapshot() -> [BatchProgress] { values }
}
