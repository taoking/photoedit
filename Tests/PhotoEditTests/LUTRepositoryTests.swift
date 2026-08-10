import CoreImage
import XCTest
@testable import PhotoEdit

@MainActor
final class LUTRepositoryTests: XCTestCase {
    func testLatestImageLoadOwnsPreviewAndRenderingState() async throws {
        let model = EditorViewModel()
        model.loadImage(data: try jpegData(red: 0.9, green: 0.1, blue: 0.1), sourceName: "first-red.jpg")
        model.loadImage(data: try jpegData(red: 0.1, green: 0.1, blue: 0.9), sourceName: "latest-blue.jpg")

        let completed = await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            model.asset?.sourceName == "latest-blue.jpg" && model.previewImage != nil && !model.isRendering
        }
        XCTAssertTrue(completed)
        XCTAssertEqual(model.asset?.sourceName, "latest-blue.jpg")
        let image = try XCTUnwrap(model.previewImage)
        let data = try XCTUnwrap(image.dataProvider?.data)
        let bytes = Array(UnsafeBufferPointer(start: try XCTUnwrap(CFDataGetBytePtr(data)), count: CFDataGetLength(data)))
        XCTAssertGreaterThan(bytes[2], bytes[0])
    }

    func testPreviewCacheDeduplicatesInFlightRequests() {
        let cache = LUTPreviewCache()
        let id = UUID()
        XCTAssertTrue(cache.beginRequest(for: id))
        XCTAssertFalse(cache.beginRequest(for: id))
        cache.finishRequest(for: id)
        XCTAssertTrue(cache.beginRequest(for: id))
        cache.clear()
        XCTAssertTrue(cache.beginRequest(for: id))
    }

    func testImportedLUTPersistsAndCanBeRead() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("Warm.cube")
        try Data(TestLUTFactory.identityText(dimension: 17).utf8).write(to: source)

        let storage = root.appendingPathComponent("LUTs", isDirectory: true)
        let repository = LUTRepository(storageDirectory: storage)
        try repository.importLUT(from: source)
        let imported = try XCTUnwrap(repository.items.first(where: { $0.source == .imported }))
        XCTAssertEqual(try repository.lut(for: imported.id).dimension, 17)
        XCTAssertEqual(imported.kind, .creative)
        XCTAssertFalse(imported.colorMetadata.isComplete)

        try repository.configure(
            id: imported.id,
            kind: .technical,
            colorMetadata: LUTColorMetadata(inputColorSpace: .rec709, outputColorSpace: .sRGB)
        )

        let reopened = LUTRepository(storageDirectory: storage)
        XCTAssertEqual(reopened.items.first(where: { $0.id == imported.id })?.name, "Warm")
        XCTAssertEqual(reopened.items.first(where: { $0.id == imported.id })?.kind, .technical)
        XCTAssertEqual(try reopened.lut(for: imported.id).colorMetadata.inputColorSpace, .rec709)
        try reopened.rename(id: imported.id, to: "Renamed")
        try reopened.toggleFavorite(id: imported.id)
        XCTAssertEqual(reopened.visibleItems(in: .favorites).map(\.id), [imported.id])
        try reopened.delete(id: imported.id)
        XCTAssertNil(reopened.items.first(where: { $0.id == imported.id }))
    }

    func testFailedCatalogSaveRollsBackInMemoryMutation() throws {
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storage) }
        try Data([0x00]).write(to: storage)
        let repository = LUTRepository(storageDirectory: storage)

        XCTAssertThrowsError(try repository.toggleFavorite(id: LUTRepository.identityID))
        XCTAssertFalse(try XCTUnwrap(repository.items.first).isFavorite)
    }

    private func jpegData(red: CGFloat, green: CGFloat, blue: CGFloat) throws -> Data {
        let image = CIImage(color: CIColor(red: red, green: green, blue: blue, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 32, height: 32))
        return try XCTUnwrap(CIContext().jpegRepresentation(
            of: image,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            options: [:]
        ))
    }

    private func waitUntil(timeoutNanoseconds: UInt64, condition: @escaping @MainActor () -> Bool) async -> Bool {
        let interval: UInt64 = 10_000_000
        var elapsed: UInt64 = 0
        while elapsed < timeoutNanoseconds {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: interval)
            elapsed += interval
        }
        return condition()
    }
}
