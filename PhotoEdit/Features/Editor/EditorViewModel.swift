import Combine
import CoreGraphics
import Foundation

@MainActor
final class EditorViewModel: ObservableObject {
    @Published private(set) var asset: ImageAsset?
    @Published var state = EditState()
    @Published private(set) var previewImage: CGImage?
    @Published private(set) var originalPreviewImage: CGImage?
    @Published var isShowingBefore = false
    @Published private(set) var isRendering = false
    @Published private(set) var isExporting = false
    @Published private(set) var histogram = Histogram.empty
    @Published var exportedImage: ExportedImage?
    @Published var errorMessage: String?
    @Published private(set) var batchPhotos: [BatchPhoto] = []
    @Published private(set) var batchProgress = BatchProgress(completed: 0, total: 0, currentID: nil)
    @Published private(set) var batchResults: [BatchItemResult] = []
    @Published private(set) var isBatchExporting = false
    @Published private(set) var batchState = EditState.initial
    @Published private(set) var batchAdjustmentSource = "当前调整"
    @Published private(set) var referencePreviewImage: CGImage?
    @Published var isShowingReference = false

    let lutRepository: LUTRepository
    let presetRepository: PresetRepository
    let adjustmentClipboard: AdjustmentClipboard
    let lutPreviewCache = LUTPreviewCache()
    let recentSettings: RecentSettingsStore

    private let pipeline: ImagePipeline
    private var renderTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    private var batchTask: Task<Void, Never>?
    private var histogramTask: Task<Void, Never>?
    private var referenceTask: Task<Void, Never>?
    private var renderGeneration = 0
    private var undoStack: [EditState] = []
    private var pendingContinuousUndo: EditState?

    init(
        lutRepository: LUTRepository = LUTRepository(),
        presetRepository: PresetRepository = PresetRepository(),
        adjustmentClipboard: AdjustmentClipboard = AdjustmentClipboard(),
        recentSettings: RecentSettingsStore = RecentSettingsStore(),
        pipeline: ImagePipeline = .shared
    ) {
        self.lutRepository = lutRepository
        self.presetRepository = presetRepository
        self.adjustmentClipboard = adjustmentClipboard
        self.recentSettings = recentSettings
        self.pipeline = pipeline
    }

    deinit {
        renderTask?.cancel()
        exportTask?.cancel()
        batchTask?.cancel()
        histogramTask?.cancel()
        referenceTask?.cancel()
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var batchOutputURLs: [URL] {
        batchResults.compactMap {
            if case let .succeeded(_, output) = $0 { output.fileURL } else { nil }
        }
    }

    func loadImage(data: Data, sourceName: String) {
        cancelRender()
        errorMessage = nil
        isRendering = true
        Task { [weak self] in
            do {
                let loaded = try await Task.detached(priority: .userInitiated) {
                    try ImageLoader.load(data: data, sourceName: sourceName)
                }.value
                guard !Task.isCancelled else { return }
                self?.install(asset: loaded)
            } catch {
                self?.finishLoadingWithError(error)
            }
        }
    }

    func loadImage(url: URL) {
        cancelRender()
        errorMessage = nil
        isRendering = true
        Task { [weak self] in
            do {
                let loaded = try await Task.detached(priority: .userInitiated) {
                    try ImageLoader.load(url: url)
                }.value
                guard !Task.isCancelled else { return }
                self?.install(asset: loaded)
            } catch {
                self?.finishLoadingWithError(error)
            }
        }
    }

    func update(_ change: (inout EditState) -> Void) {
        let previous = state
        change(&state)
        guard state != previous else { return }
        if pendingContinuousUndo == nil { undoStack.append(previous) }
        lutPreviewCache.clear()
        schedulePreviewRender()
    }

    func beginContinuousEdit() {
        guard pendingContinuousUndo == nil else { return }
        pendingContinuousUndo = state
    }

    func updateContinuous(_ change: (inout EditState) -> Void) {
        change(&state)
        lutPreviewCache.clear()
        schedulePreviewRender()
    }

    func endContinuousEdit() {
        guard let previous = pendingContinuousUndo else { return }
        pendingContinuousUndo = nil
        if previous != state { undoStack.append(previous) }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        pendingContinuousUndo = nil
        state = previous
        lutPreviewCache.clear()
        schedulePreviewRender()
    }

    func reset() {
        guard state != .initial else { return }
        undoStack.append(state)
        state.reset()
        lutPreviewCache.clear()
        schedulePreviewRender()
    }

    func selectLUT(_ id: UUID?) {
        update { state in
            state.lut.selectedLUTID = id
            if id == nil { state.lut.intensity = 1 }
        }
        if let id { recentSettings.record(lut: id) }
    }

    func resetHSL(_ channel: HSLChannel) {
        update { $0.hsl.reset(channel) }
    }

    func resetAllHSL() {
        update { $0.hsl.resetAll() }
    }

    func addCurvePoint(channel: ToneCurveChannel, x: Double, y: Double) {
        update { state in
            var curve = state.curves[channel]
            curve.addPoint(x: x, y: y)
            state.curves[channel] = curve
        }
    }

    func moveCurvePoint(channel: ToneCurveChannel, id: String, x: Double, y: Double) {
        updateContinuous { state in
            var curve = state.curves[channel]
            curve.movePoint(id: id, x: x, y: y)
            state.curves[channel] = curve
        }
    }

    func removeCurvePoint(channel: ToneCurveChannel, id: String) {
        update { state in
            var curve = state.curves[channel]
            curve.removePoint(id: id)
            state.curves[channel] = curve
        }
    }

    func resetCurves() {
        update { $0.curves.resetAll() }
    }

    func copyAllAdjustments() {
        adjustmentClipboard.copy(from: state)
    }

    func pasteAdjustments(groups: Set<AdjustmentGroup> = Set(AdjustmentGroup.allCases)) {
        guard let pasted = adjustmentClipboard.paste(into: state, groups: groups), pasted != state else { return }
        undoStack.append(state)
        state = pasted
        lutPreviewCache.clear()
        schedulePreviewRender()
    }

    func createPreset(name: String, includesTransform: Bool) {
        do {
            try presetRepository.create(name: name, state: state, includesTransform: includesTransform)
        } catch {
            present(error)
        }
    }

    func applyPreset(id: UUID) {
        guard let preset = presetRepository.preset(id: id) else { return }
        let applied = preset.payload.applying(to: state)
        guard applied != state else { return }
        undoStack.append(state)
        state = applied
        recentSettings.record(preset: id)
        lutPreviewCache.clear()
        schedulePreviewRender()
    }

    func importPreset(url: URL) {
        do { try presetRepository.importPreset(from: url) }
        catch { present(error) }
    }

    func importLUT(url: URL) {
        do {
            try lutRepository.importLUT(from: url)
            lutPreviewCache.clear()
        } catch {
            present(error)
        }
    }

    func thumbnail(for id: UUID) -> CGImage? {
        if let cached = lutPreviewCache[id] { return cached }
        guard let asset else { return nil }
        let thumbnailState = state
        Task { [weak self, pipeline, asset, thumbnailState] in
            guard let self, let lut = try? self.lutRepository.lut(for: id) else { return }
            var renderState = thumbnailState
            renderState.lut.selectedLUTID = id
            renderState.lut.intensity = 1
            guard let image = try? await pipeline.render(
                asset: asset,
                state: renderState,
                lut: lut,
                mode: .preview(maximumDimension: 256)
            ) else { return }
            self.lutPreviewCache[id] = image
            self.objectWillChange.send()
        }
        return nil
    }

    func export(settings: ExportSettings) {
        guard let asset else { return }
        exportTask?.cancel()
        isExporting = true
        errorMessage = nil
        recentSettings.record(export: settings)
        let state = state
        let lut = selectedLUT()
        exportTask = Task { [weak self, pipeline, asset, state, lut] in
            do {
                let output = try await ImageExporter.export(asset: asset, state: state, lut: lut, settings: settings, pipeline: pipeline)
                guard !Task.isCancelled else { return }
                self?.exportedImage = output
                self?.isExporting = false
            } catch is CancellationError {
                self?.isExporting = false
            } catch {
                self?.isExporting = false
                self?.present(error)
            }
        }
    }

    func clearExport() {
        if let url = exportedImage?.fileURL { try? FileManager.default.removeItem(at: url) }
        exportedImage = nil
    }

    /// 仅保存安全作用域文件 URL；真正的图像解码由顺序队列在导出到该项时执行。
    func addBatchPhotos(urls: [URL]) {
        if batchPhotos.isEmpty, !urls.isEmpty {
            batchState = state
            batchAdjustmentSource = "当前调整"
        }
        let existing = Set(batchPhotos.map { $0.url.standardizedFileURL.path })
        let newPhotos = urls
            .filter { !existing.contains($0.standardizedFileURL.path) }
            .map(BatchPhoto.init(url:))
        batchPhotos.append(contentsOf: newPhotos)
    }

    func removeBatchPhotos(at offsets: IndexSet) {
        guard !isBatchExporting else { return }
        batchPhotos.remove(atOffsets: offsets)
    }

    func clearBatchPhotos() {
        guard !isBatchExporting else { return }
        batchPhotos.removeAll()
        batchResults.removeAll()
        batchProgress = BatchProgress(completed: 0, total: 0, currentID: nil)
    }

    func applyCurrentAdjustmentsToBatch() {
        batchState = state
        batchAdjustmentSource = "当前照片调整"
    }

    func applyCopiedAdjustmentsToBatch() -> Bool {
        guard let copied = adjustmentClipboard.paste(into: .initial) else { return false }
        batchState = copied
        batchAdjustmentSource = "已复制的调整"
        return true
    }

    func applyPresetToBatch(id: UUID) {
        guard let preset = presetRepository.preset(id: id) else { return }
        batchState = preset.payload.applying(to: .initial)
        batchAdjustmentSource = "预设：\(preset.name)"
        recentSettings.record(preset: id)
    }

    func applyLUTToBatch(id: UUID?) {
        batchState.lut.selectedLUTID = id
        batchState.lut.intensity = 1
        batchAdjustmentSource = id == nil ? "不使用 LUT" : "LUT：\(lutRepository.items.first(where: { $0.id == id })?.name ?? "已选")"
        if let id { recentSettings.record(lut: id) }
    }

    func startBatchExport(settings: ExportSettings) {
        guard !batchPhotos.isEmpty, !isBatchExporting else { return }
        let lut = lut(for: batchState)
        guard batchState.lut.selectedLUTID == nil || lut != nil else { return }
        let jobs = batchPhotos.map {
            BatchExportJob(id: $0.id, photo: $0, state: batchState, lut: lut, settings: settings)
        }
        batchTask?.cancel()
        batchResults.removeAll()
        batchProgress = BatchProgress(completed: 0, total: jobs.count, currentID: nil)
        isBatchExporting = true
        errorMessage = nil
        recentSettings.record(export: settings)
        let queue = BatchExportQueue()
        batchTask = Task { [weak self] in
            let results = await queue.run(jobs) { [weak self] progress in
                await MainActor.run { self?.batchProgress = progress }
            }
            self?.batchResults = results
            self?.isBatchExporting = false
        }
    }

    func cancelBatchExport() {
        batchTask?.cancel()
        isBatchExporting = false
    }

    func loadReference(url: URL) {
        referenceTask?.cancel()
        errorMessage = nil
        referenceTask = Task { [weak self, pipeline] in
            do {
                let reference = try await Task.detached(priority: .userInitiated) {
                    try ImageLoader.load(url: url)
                }.value
                let preview = try await pipeline.render(
                    asset: reference,
                    state: .initial,
                    lut: nil,
                    mode: .preview(maximumDimension: 1600)
                )
                guard !Task.isCancelled else { return }
                self?.referencePreviewImage = preview
                self?.isShowingReference = true
            } catch is CancellationError {
                // A newer reference selection replaced this work.
            } catch {
                self?.present(error)
            }
        }
    }

    private func install(asset: ImageAsset) {
        self.asset = asset
        state = .initial
        if asset.isRAW { state.raw = RAWAdjustments() }
        undoStack.removeAll()
        pendingContinuousUndo = nil
        lutPreviewCache.clear()
        renderOriginalPreview()
        scheduleHistogram()
        schedulePreviewRender()
    }

    private func finishLoadingWithError(_ error: Error) {
        isRendering = false
        present(error)
    }

    private func selectedLUT() -> LUT? {
        lut(for: state)
    }

    private func lut(for renderState: EditState) -> LUT? {
        guard let id = renderState.lut.selectedLUTID else { return nil }
        do { return try lutRepository.lut(for: id) }
        catch {
            present(error)
            return nil
        }
    }

    private func renderOriginalPreview() {
        guard let asset else { return }
        Task { [weak self, pipeline, asset] in
            let image = try? await pipeline.render(
                asset: asset,
                state: .initial,
                lut: nil,
                mode: .preview(maximumDimension: 2048)
            )
            self?.originalPreviewImage = image
        }
    }

    private func schedulePreviewRender() {
        guard let asset else {
            isRendering = false
            return
        }
        renderTask?.cancel()
        renderGeneration += 1
        let generation = renderGeneration
        let state = state
        let lut = selectedLUT()
        isRendering = true
        renderTask = Task { [weak self, pipeline, asset, state, lut] in
            do {
                let rendered = try await pipeline.render(
                    asset: asset,
                    state: state,
                    lut: lut,
                    mode: .preview(maximumDimension: 2048)
                )
                guard !Task.isCancelled, self?.renderGeneration == generation else { return }
                self?.previewImage = rendered
                self?.isRendering = false
            } catch is CancellationError {
                // Newer render owns UI state.
            } catch {
                guard self?.renderGeneration == generation else { return }
                self?.isRendering = false
                self?.present(error)
            }
        }
    }

    private func cancelRender() {
        renderTask?.cancel()
        renderGeneration += 1
    }

    private func scheduleHistogram() {
        histogramTask?.cancel()
        guard let asset else {
            histogram = .empty
            return
        }
        let id = asset.id
        histogramTask = Task { [weak self, pipeline, asset] in
            do {
                try await Task.sleep(nanoseconds: 160_000_000)
                let computed = try await pipeline.histogram(for: asset, maximumDimension: 512)
                guard !Task.isCancelled, self?.asset?.id == id else { return }
                self?.histogram = computed
            } catch is CancellationError {
                // Replaced by a newly loaded image.
            } catch {
                self?.histogram = .empty
            }
        }
    }

    private func present(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
