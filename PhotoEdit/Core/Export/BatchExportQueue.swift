import Combine
import Foundation

struct BatchPhoto: Identifiable, Hashable, Sendable {
    let id: UUID
    let url: URL
    let sourceName: String

    init(url: URL) {
        id = UUID()
        self.url = url
        sourceName = url.lastPathComponent
    }
}

struct BatchExportJob: Sendable {
    let id: UUID
    let photo: BatchPhoto
    let state: EditState
    let lut: LUT?
    let technicalLUT: LUT?
    let settings: ExportSettings
}

enum BatchItemResult: Sendable {
    case succeeded(id: UUID, output: ExportedImage)
    case failed(id: UUID, message: String)
    case cancelled(id: UUID)
}

struct BatchProgress: Sendable, Equatable {
    var completed: Int
    var total: Int
    var currentID: UUID?
}

/// 严格顺序处理全分辨率任务，单项错误记录后继续，绝不同时把整批原图载入内存。
actor BatchExportQueue {
    func run(_ jobs: [BatchExportJob], progress: @escaping @Sendable (BatchProgress) async -> Void) async -> [BatchItemResult] {
        var results: [BatchItemResult] = []
        for (index, job) in jobs.enumerated() {
            if Task.isCancelled {
                results.append(contentsOf: jobs[index...].map { .cancelled(id: $0.id) })
                break
            }
            await progress(BatchProgress(completed: index, total: jobs.count, currentID: job.id))
            do {
                // Asset is deliberately created here rather than while selecting files. Once this
                // iteration finishes, no queue-owned reference keeps this source image in memory.
                let asset = try ImageLoader.load(url: job.photo.url)
                let output = try await ImageExporter.export(
                    asset: asset,
                    state: job.state,
                    lut: job.lut,
                    technicalLUT: job.technicalLUT,
                    settings: job.settings,
                    sequenceNumber: index + 1
                )
                results.append(.succeeded(id: job.id, output: output))
            } catch is CancellationError {
                results.append(.cancelled(id: job.id))
            } catch {
                results.append(.failed(id: job.id, message: error.localizedDescription))
            }
        }
        await progress(BatchProgress(completed: min(results.count, jobs.count), total: jobs.count, currentID: nil))
        return results
    }
}

@MainActor
final class RecentSettingsStore: ObservableObject {
    @Published private(set) var lutIDs: [UUID] = []
    @Published private(set) var presetIDs: [UUID] = []
    @Published private(set) var exportSettings: [ExportSettings] = []

    private let defaults: UserDefaults
    private let limit = 8

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lutIDs = (try? JSONDecoder().decode([UUID].self, from: defaults.data(forKey: "recentLUTs") ?? Data())) ?? []
        presetIDs = (try? JSONDecoder().decode([UUID].self, from: defaults.data(forKey: "recentPresets") ?? Data())) ?? []
        exportSettings = (try? JSONDecoder().decode([ExportSettings].self, from: defaults.data(forKey: "recentExports") ?? Data())) ?? []
    }

    func record(lut id: UUID) { lutIDs = prepend(id, to: lutIDs); save(lutIDs, key: "recentLUTs") }
    func record(preset id: UUID) { presetIDs = prepend(id, to: presetIDs); save(presetIDs, key: "recentPresets") }
    func record(export settings: ExportSettings) { exportSettings = prepend(settings, to: exportSettings); save(exportSettings, key: "recentExports") }

    private func prepend<T: Equatable>(_ value: T, to values: [T]) -> [T] { Array(([value] + values.filter { $0 != value }).prefix(limit)) }
    private func save<T: Encodable>(_ value: T, key: String) { defaults.set(try? JSONEncoder().encode(value), forKey: key) }
}
