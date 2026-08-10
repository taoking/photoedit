import Foundation

struct EditorSessionRecord: Codable, Equatable, Sendable {
    let id: UUID
    let sourceName: String
    var state: EditState
    var savedAt: Date
}

struct RestoredEditorSession: Sendable {
    let record: EditorSessionRecord
    let sourceData: Data
}

/// 当前单图编辑会话的持久化存储。源文件与编辑参数分开保存，滑杆变化只重写较小的 JSON。
actor EditorSessionStore {
    static let shared = EditorSessionStore()

    private let fileManager: FileManager
    private let storageDirectory: URL
    private var activeRecord: EditorSessionRecord?
    private var latestRevision = 0

    init(fileManager: FileManager = .default, storageDirectory: URL? = nil) {
        self.fileManager = fileManager
        if let storageDirectory {
            self.storageDirectory = storageDirectory
        } else {
            let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.storageDirectory = applicationSupport
                .appendingPathComponent("PhotoEdit", isDirectory: true)
                .appendingPathComponent("CurrentSession", isDirectory: true)
        }
    }

    func saveNew(
        id: UUID,
        sourceName: String,
        sourceData: Data,
        state: EditState,
        revision: Int
    ) throws {
        guard revision >= latestRevision else { return }
        try fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)

        let record = EditorSessionRecord(id: id, sourceName: sourceName, state: state, savedAt: .now)
        try sourceData.write(to: sourceURL(for: id), options: .atomic)
        try write(record)

        if let previousID = activeRecord?.id, previousID != id {
            try? fileManager.removeItem(at: sourceURL(for: previousID))
        }
        activeRecord = record
        latestRevision = revision
    }

    func updateState(id: UUID, state: EditState, revision: Int) throws {
        guard var record = activeRecord, record.id == id, revision >= latestRevision else { return }
        record.state = state
        record.savedAt = .now
        try write(record)
        activeRecord = record
        latestRevision = revision
    }

    func load() throws -> RestoredEditorSession? {
        guard fileManager.fileExists(atPath: manifestURL.path) else { return nil }
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(EditorSessionRecord.self, from: data)
        let sourceData = try Data(contentsOf: sourceURL(for: record.id))
        activeRecord = record
        return RestoredEditorSession(record: record, sourceData: sourceData)
    }

    func hasSavedSession() -> Bool {
        fileManager.fileExists(atPath: manifestURL.path)
    }

    func clear() throws {
        if fileManager.fileExists(atPath: storageDirectory.path) {
            try fileManager.removeItem(at: storageDirectory)
        }
        activeRecord = nil
        latestRevision = 0
    }

    private var manifestURL: URL {
        storageDirectory.appendingPathComponent("session.json", isDirectory: false)
    }

    private func sourceURL(for id: UUID) -> URL {
        storageDirectory.appendingPathComponent("\(id.uuidString).source", isDirectory: false)
    }

    private func write(_ record: EditorSessionRecord) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(record).write(to: manifestURL, options: .atomic)
    }
}
