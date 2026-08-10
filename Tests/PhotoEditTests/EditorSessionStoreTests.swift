import XCTest
@testable import PhotoEdit

final class EditorSessionStoreTests: XCTestCase {
    func testSessionRoundTripsStateAndSourceData() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let id = UUID()
        let sourceData = Data([0x01, 0x02, 0x03])
        var initialState = EditState.initial
        initialState.light.exposure = 1.25
        let store = EditorSessionStore(storageDirectory: root)
        try await store.saveNew(
            id: id,
            sourceName: "fixture.jpg",
            sourceData: sourceData,
            state: initialState,
            revision: 1
        )

        var updatedState = initialState
        updatedState.color.saturation = 24
        try await store.updateState(id: id, state: updatedState, revision: 2)

        let reloadedStore = EditorSessionStore(storageDirectory: root)
        let loaded = try await reloadedStore.load()
        let restored = try XCTUnwrap(loaded)
        XCTAssertEqual(restored.record.id, id)
        XCTAssertEqual(restored.record.sourceName, "fixture.jpg")
        XCTAssertEqual(restored.record.state, updatedState)
        XCTAssertEqual(restored.sourceData, sourceData)
    }

    func testOlderRevisionCannotOverwriteNewerState() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let id = UUID()
        let store = EditorSessionStore(storageDirectory: root)
        try await store.saveNew(
            id: id,
            sourceName: "fixture.jpg",
            sourceData: Data([0x01]),
            state: .initial,
            revision: 10
        )
        var newer = EditState.initial
        newer.light.contrast = 30
        try await store.updateState(id: id, state: newer, revision: 12)
        var older = EditState.initial
        older.light.contrast = -30
        try await store.updateState(id: id, state: older, revision: 11)

        let loaded = try await store.load()
        let restored = try XCTUnwrap(loaded)
        XCTAssertEqual(restored.record.state, newer)

        try await store.clear()
        let hasSavedSession = await store.hasSavedSession()
        XCTAssertFalse(hasSavedSession)
    }
}
