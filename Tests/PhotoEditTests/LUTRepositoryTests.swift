import XCTest
@testable import PhotoEdit

@MainActor
final class LUTRepositoryTests: XCTestCase {
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
}
