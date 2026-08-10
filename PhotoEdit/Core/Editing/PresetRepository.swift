import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct PresetPayload: Codable, Equatable, Sendable {
    var light: LightAdjustments
    var color: ColorAdjustments
    var hsl: HSLAdjustments
    var curves: ToneCurveAdjustments
    var detail: DetailAdjustments
    var effects: EffectAdjustments
    var lut: LUTAdjustment
    /// 默认 nil，明确选择后才包括裁切、旋转与翻转。
    var transform: TransformAdjustment?

    init(state: EditState, includesTransform: Bool) {
        light = state.light
        color = state.color
        hsl = state.hsl
        curves = state.curves
        detail = state.detail
        effects = state.effects
        lut = state.lut
        transform = includesTransform ? state.transform : nil
    }

    func applying(to state: EditState) -> EditState {
        var output = state
        output.light = light
        output.color = color
        output.hsl = hsl
        output.curves = curves
        output.detail = detail
        output.effects = effects
        output.lut = lut
        if let transform { output.transform = transform }
        return output
    }
}

struct Preset: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var isFavorite: Bool
    var createdAt: Date
    var payload: PresetPayload
}

@MainActor
final class PresetRepository: ObservableObject {
    @Published private(set) var presets: [Preset] = []

    private let storageURL: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default, storageURL: URL? = nil) {
        self.fileManager = fileManager
        self.storageURL = storageURL ?? Self.defaultStorageURL(fileManager: fileManager)
        load()
    }

    @discardableResult
    func create(name: String, state: EditState, includesTransform: Bool) throws -> Preset {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImageEditorError.invalidLUT }
        let preset = Preset(
            id: UUID(),
            name: trimmed,
            isFavorite: false,
            createdAt: .now,
            payload: PresetPayload(state: state.canonicalized(), includesTransform: includesTransform)
        )
        let previous = presets
        presets.append(preset)
        do { try save() }
        catch {
            presets = previous
            throw error
        }
        return preset
    }

    func rename(id: UUID, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = presets.firstIndex(where: { $0.id == id }) else { return }
        let previous = presets
        presets[index].name = trimmed
        do { try save() }
        catch {
            presets = previous
            throw error
        }
    }

    func delete(id: UUID) throws {
        let previous = presets
        presets.removeAll { $0.id == id }
        do { try save() }
        catch {
            presets = previous
            throw error
        }
    }

    func toggleFavorite(id: UUID) throws {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
        let previous = presets
        presets[index].isFavorite.toggle()
        do { try save() }
        catch {
            presets = previous
            throw error
        }
    }

    func preset(id: UUID) -> Preset? { presets.first { $0.id == id } }

    func importPreset(from url: URL) throws {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }
        var imported = try JSONDecoder().decode(Preset.self, from: Data(contentsOf: url))
        imported.id = UUID()
        imported.createdAt = .now
        let previous = presets
        presets.append(imported)
        do { try save() }
        catch {
            presets = previous
            throw error
        }
    }

    func exportData(id: UUID) throws -> Data {
        guard let preset = preset(id: id) else { throw ImageEditorError.exportFailed }
        return try JSONEncoder.preset.encode(preset)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL), let saved = try? JSONDecoder().decode([Preset].self, from: data) else { return }
        presets = saved
    }

    private func save() throws {
        try fileManager.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.preset.encode(presets).write(to: storageURL, options: .atomic)
    }

    private static func defaultStorageURL(fileManager: FileManager) -> URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        return root.appendingPathComponent("PhotoEdit", isDirectory: true).appendingPathComponent("Presets.json")
    }
}

struct PresetDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private extension JSONEncoder {
    static var preset: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
