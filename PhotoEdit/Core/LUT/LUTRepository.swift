import Combine
import CoreGraphics
import Foundation

@MainActor
final class LUTRepository: ObservableObject {
    static let identityID = UUID(uuidString: "4989A1C9-C4E4-4C44-8A88-8719BB0DB001")!

    @Published private(set) var items: [LUTCatalogItem] = []

    private let fileManager: FileManager
    private let storageDirectory: URL
    private let metadataURL: URL

    init(fileManager: FileManager = .default, storageDirectory: URL? = nil) {
        self.fileManager = fileManager
        let root = storageDirectory ?? Self.defaultStorageDirectory(fileManager: fileManager)
        self.storageDirectory = root
        self.metadataURL = root.appendingPathComponent("metadata.json")
        loadCatalog()
    }

    func importLUT(from url: URL) throws {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted { url.stopAccessingSecurityScopedResource() }
        }
        let data = try Data(contentsOf: url)
        let parsed = try CUBEParser.parse(data: data)
        try ensureStorageDirectory()
        let id = UUID()
        let filename = "\(id.uuidString).cube"
        try data.write(to: storageDirectory.appendingPathComponent(filename), options: .atomic)
        let originalName = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        items.append(LUTCatalogItem(
            id: id,
            name: originalName.isEmpty ? (parsed.title ?? "Imported LUT") : originalName,
            source: .imported,
            isFavorite: false,
            fileName: filename,
            dimension: parsed.dimension,
            importedAt: .now
        ))
        try saveCatalog()
    }

    func rename(id: UUID, to newName: String) throws {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].name = name
        try saveCatalog()
    }

    func delete(id: UUID) throws {
        guard let item = items.first(where: { $0.id == id }), item.source == .imported else { return }
        if let fileName = item.fileName {
            let url = storageDirectory.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
        }
        items.removeAll { $0.id == id }
        try saveCatalog()
    }

    func toggleFavorite(id: UUID) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isFavorite.toggle()
        try saveCatalog()
    }

    func configure(id: UUID, kind: LUTKind, colorMetadata: LUTColorMetadata) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].kind = kind
        items[index].colorMetadata = colorMetadata
        try saveCatalog()
    }

    func lut(for id: UUID) throws -> LUT {
        if id == Self.identityID { return Self.identityLUT() }
        guard let item = items.first(where: { $0.id == id }), let filename = item.fileName else {
            throw ImageEditorError.invalidLUT
        }
        do {
            let parsed = try CUBEParser.parse(data: Data(contentsOf: storageDirectory.appendingPathComponent(filename)))
            return parsed.configured(kind: item.kind, colorMetadata: item.colorMetadata)
        } catch {
            throw ImageEditorError.invalidLUT
        }
    }

    func visibleItems(in section: LUTLibrarySection) -> [LUTCatalogItem] {
        switch section {
        case .all: items
        case .builtIn: items.filter { $0.source == .builtIn }
        case .imported: items.filter { $0.source == .imported }
        case .creative: items.filter { $0.kind == .creative }
        case .technical: items.filter { $0.kind == .technical }
        case .favorites: items.filter(\.isFavorite)
        }
    }

    private func loadCatalog() {
        let builtIn = LUTCatalogItem(
            id: Self.identityID,
            name: "Neutral",
            source: .builtIn,
            isFavorite: false,
            fileName: nil,
            dimension: 17,
            importedAt: .distantPast,
            kind: .creative,
            colorMetadata: .sRGB
        )
        guard let data = try? Data(contentsOf: metadataURL),
              let imported = try? JSONDecoder().decode([LUTCatalogItem].self, from: data) else {
            items = [builtIn]
            return
        }
        items = [builtIn] + imported.filter { $0.source == .imported }
    }

    private func saveCatalog() throws {
        try ensureStorageDirectory()
        let imported = items.filter { $0.source == .imported }
        let data = try JSONEncoder.pretty.encode(imported)
        try data.write(to: metadataURL, options: .atomic)
    }

    private func ensureStorageDirectory() throws {
        try fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
    }

    private static func defaultStorageDirectory(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return applicationSupport
            .appendingPathComponent("PhotoEdit", isDirectory: true)
            .appendingPathComponent("LUTs", isDirectory: true)
            .appendingPathComponent("imported", isDirectory: true)
    }

    private static func identityLUT(dimension: Int = 17) -> LUT {
        var values: [RGBColor] = []
        values.reserveCapacity(dimension * dimension * dimension)
        for blue in 0 ..< dimension {
            for green in 0 ..< dimension {
                for red in 0 ..< dimension {
                    values.append(RGBColor(
                        red: Float(red) / Float(dimension - 1),
                        green: Float(green) / Float(dimension - 1),
                        blue: Float(blue) / Float(dimension - 1)
                    ))
                }
            }
        }
        return LUT(
            title: "Neutral",
            dimension: dimension,
            domainMin: .clear,
            domainMax: RGBColor(red: 1, green: 1, blue: 1),
            values: values,
            kind: .creative,
            colorMetadata: .sRGB
        )
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

/// 缩略图只缓存低分辨率渲染结果，避免 LUT 网格持有全分辨率照片。
@MainActor
final class LUTPreviewCache {
    private let cache = NSCache<NSUUID, CGImage>()
    private var inFlight = Set<UUID>()

    subscript(id: UUID) -> CGImage? {
        get { cache.object(forKey: id as NSUUID) }
        set {
            if let newValue { cache.setObject(newValue, forKey: id as NSUUID) }
            else { cache.removeObject(forKey: id as NSUUID) }
        }
    }

    /// 同一个卡片在 SwiftUI 刷新期间可能重复请求；只允许第一个请求启动 render。
    func beginRequest(for id: UUID) -> Bool {
        guard cache.object(forKey: id as NSUUID) == nil, !inFlight.contains(id) else { return false }
        inFlight.insert(id)
        return true
    }

    func finishRequest(for id: UUID) { inFlight.remove(id) }

    func clear() {
        cache.removeAllObjects()
        inFlight.removeAll()
    }
}
