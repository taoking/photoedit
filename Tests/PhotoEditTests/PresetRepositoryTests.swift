import XCTest
@testable import PhotoEdit

@MainActor
final class PresetRepositoryTests: XCTestCase {
    func testPresetPersistsAndExcludesTransformByDefault() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appendingPathComponent("Presets.json")
        let repository = PresetRepository(storageURL: storage)

        var state = EditState()
        state.light.exposure = 1.5
        state.hsl.blue.luminance = 25
        state.transform.rotation = 90
        let preset = try repository.create(name: "Travel", state: state, includesTransform: false)
        var target = EditState()
        target.transform.horizontalFlip = true
        let applied = preset.payload.applying(to: target)
        XCTAssertEqual(applied.light.exposure, 1.5)
        XCTAssertEqual(applied.hsl.blue.luminance, 25)
        XCTAssertTrue(applied.transform.horizontalFlip)

        let reloaded = PresetRepository(storageURL: storage)
        XCTAssertEqual(reloaded.presets.count, 1)
        let exported = try reloaded.exportData(id: preset.id)
        let importURL = root.appendingPathComponent("Imported.json")
        try exported.write(to: importURL)
        try reloaded.importPreset(from: importURL)
        XCTAssertEqual(reloaded.presets.count, 2)
        try reloaded.rename(id: preset.id, to: "Renamed")
        try reloaded.toggleFavorite(id: preset.id)
        XCTAssertTrue(reloaded.preset(id: preset.id)?.isFavorite == true)
        try reloaded.delete(id: preset.id)
        XCTAssertNil(reloaded.preset(id: preset.id))
    }

    func testFailedSaveRollsBackInMemoryPresetMutation() throws {
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storage) }
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        let repository = PresetRepository(storageURL: storage)

        XCTAssertThrowsError(try repository.create(name: "Cannot Save", state: .initial, includesTransform: false))
        XCTAssertTrue(repository.presets.isEmpty)
    }
}
