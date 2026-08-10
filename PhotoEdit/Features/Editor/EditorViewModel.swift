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
    @Published private(set) var isRestoringSession = false
    @Published private(set) var hasRestorableSession = false
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
    @Published var selectedLocalAdjustmentID: UUID?

    let lutRepository: LUTRepository
    let presetRepository: PresetRepository
    let adjustmentClipboard: AdjustmentClipboard
    let lutPreviewCache = LUTPreviewCache()
    let recentSettings: RecentSettingsStore

    private let pipeline: ImagePipeline
    private let sessionStore: EditorSessionStore?
    private var renderTask: Task<Void, Never>?
    private var originalPreviewTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    private var batchTask: Task<Void, Never>?
    private var histogramTask: Task<Void, Never>?
    private var referenceTask: Task<Void, Never>?
    private var renderGeneration = 0
    private var loadGeneration = 0
    private var loadTask: Task<Void, Never>?
    private var sessionRestoreTask: Task<Void, Never>?
    private var sessionSourceSaveTask: Task<Void, Never>?
    private var sessionStateSaveTask: Task<Void, Never>?
    private var sessionRevision = 0
    private var activeSessionID: UUID?
    private var undoStack: [EditState] = []
    private var pendingContinuousUndo: EditState?

    init(
        lutRepository: LUTRepository = LUTRepository(),
        presetRepository: PresetRepository = PresetRepository(),
        adjustmentClipboard: AdjustmentClipboard = AdjustmentClipboard(),
        recentSettings: RecentSettingsStore = RecentSettingsStore(),
        pipeline: ImagePipeline = .shared,
        sessionStore: EditorSessionStore? = nil,
        restoresSessionAutomatically: Bool = false
    ) {
        self.lutRepository = lutRepository
        self.presetRepository = presetRepository
        self.adjustmentClipboard = adjustmentClipboard
        self.recentSettings = recentSettings
        self.pipeline = pipeline
        self.sessionStore = sessionStore
        guard let sessionStore else { return }
        Task { [weak self] in
            let hasSavedSession = await sessionStore.hasSavedSession()
            self?.hasRestorableSession = hasSavedSession
            if restoresSessionAutomatically, hasSavedSession {
                self?.restoreSavedSession()
            }
        }
    }

    deinit {
        renderTask?.cancel()
        originalPreviewTask?.cancel()
        loadTask?.cancel()
        exportTask?.cancel()
        batchTask?.cancel()
        histogramTask?.cancel()
        referenceTask?.cancel()
        sessionRestoreTask?.cancel()
        sessionSourceSaveTask?.cancel()
        sessionStateSaveTask?.cancel()
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var hasEdits: Bool { state != Self.defaultState(for: asset) }
    /// HDR 源的主预览输出为 RGBA half-float；视图层请求 high dynamic range 显示。
    var usesHDRPreview: Bool { asset?.hasHDRContent == true }
    var batchOutputURLs: [URL] {
        batchResults.compactMap {
            if case let .succeeded(_, output) = $0 { output.fileURL } else { nil }
        }
    }
    var selectedLocalAdjustment: LocalAdjustment? {
        state.localAdjustments.first { $0.id == selectedLocalAdjustmentID }
    }

    func loadImage(data: Data, sourceName: String) {
        let generation = beginLoading()
        errorMessage = nil
        loadTask = Task { [weak self] in
            do {
                let loaded = try await Task.detached(priority: .userInitiated) {
                    try ImageLoader.load(data: data, sourceName: sourceName)
                }.value
                guard !Task.isCancelled, self?.loadGeneration == generation else { return }
                self?.install(asset: loaded)
            } catch is CancellationError {
                self?.finishLoadingCancellation(generation: generation)
            } catch {
                self?.finishLoadingWithError(error, generation: generation)
            }
        }
    }

    func loadImage(url: URL) {
        let generation = beginLoading()
        errorMessage = nil
        loadTask = Task { [weak self] in
            do {
                let loaded = try await Task.detached(priority: .userInitiated) {
                    try ImageLoader.load(url: url)
                }.value
                guard !Task.isCancelled, self?.loadGeneration == generation else { return }
                self?.install(asset: loaded)
            } catch is CancellationError {
                self?.finishLoadingCancellation(generation: generation)
            } catch {
                self?.finishLoadingWithError(error, generation: generation)
            }
        }
    }

    func update(_ change: (inout EditState) -> Void) {
        let previous = state
        change(&state)
        state.canonicalize()
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
        let previous = state
        change(&state)
        state.canonicalize()
        guard state != previous else { return }
        lutPreviewCache.clear()
        schedulePreviewRender(debounceNanoseconds: 16_000_000)
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
        let defaultState = Self.defaultState(for: asset)
        guard state != defaultState else { return }
        undoStack.append(state)
        state = defaultState
        lutPreviewCache.clear()
        schedulePreviewRender()
    }

    /// 返回导入页。默认保留自动保存的会话，用户明确放弃时才删除它。
    func closeCurrentAsset(discardSession: Bool = false) {
        loadTask?.cancel()
        renderTask?.cancel()
        originalPreviewTask?.cancel()
        histogramTask?.cancel()
        referenceTask?.cancel()
        exportTask?.cancel()
        sessionRestoreTask?.cancel()
        sessionStateSaveTask?.cancel()
        loadGeneration += 1
        renderGeneration += 1
        asset = nil
        state = .initial
        previewImage = nil
        originalPreviewImage = nil
        referencePreviewImage = nil
        isShowingReference = false
        selectedLocalAdjustmentID = nil
        histogram = .empty
        isRendering = false
        isExporting = false
        undoStack.removeAll()
        pendingContinuousUndo = nil
        lutPreviewCache.clear()
        if discardSession {
            sessionSourceSaveTask?.cancel()
            hasRestorableSession = false
            if let sessionStore {
                Task { [weak self] in
                    do { try await sessionStore.clear() }
                    catch { self?.present(error) }
                }
            }
        }
    }

    func restoreSavedSession() {
        guard let sessionStore, !isRestoringSession else { return }
        let generation = beginLoading()
        isRestoringSession = true
        errorMessage = nil
        sessionRestoreTask = Task { [weak self] in
            do {
                guard let restored = try await sessionStore.load() else {
                    self?.hasRestorableSession = false
                    self?.isRestoringSession = false
                    self?.isRendering = false
                    return
                }
                let loaded = try await Task.detached(priority: .userInitiated) {
                    try ImageLoader.load(data: restored.sourceData, sourceName: restored.record.sourceName)
                }.value
                guard !Task.isCancelled, let self, self.loadGeneration == generation else { return }
                self.install(asset: loaded, scheduleRendering: false, persistSession: false)
                self.state = restored.record.state.canonicalized()
                self.activeSessionID = restored.record.id
                self.hasRestorableSession = true
                self.isRestoringSession = false
                self.renderOriginalPreview()
                self.schedulePreviewRender()
            } catch is CancellationError {
                if self?.loadGeneration == generation {
                    self?.isRestoringSession = false
                    self?.isRendering = false
                }
            } catch {
                guard self?.loadGeneration == generation else { return }
                self?.isRestoringSession = false
                self?.isRendering = false
                self?.hasRestorableSession = false
                self?.present(error)
            }
        }
    }

    func addLocalAdjustment(mask: LocalMask) {
        let adjustment: LocalAdjustment
        switch mask {
        case .linear: adjustment = .linear()
        case .radial: adjustment = .radial()
        case .brush: adjustment = .brush()
        }
        update { $0.localAdjustments.append(adjustment) }
        selectedLocalAdjustmentID = adjustment.id
    }

    func updateLocalAdjustment(id: UUID, change: (inout LocalAdjustment) -> Void) {
        update { state in
            guard let index = state.localAdjustments.firstIndex(where: { $0.id == id }) else { return }
            change(&state.localAdjustments[index])
        }
    }

    func updateLocalAdjustmentContinuous(id: UUID, change: (inout LocalAdjustment) -> Void) {
        updateContinuous { state in
            guard let index = state.localAdjustments.firstIndex(where: { $0.id == id }) else { return }
            change(&state.localAdjustments[index])
        }
    }

    func beginLocalBrushStroke() { beginContinuousEdit() }

    func appendBrushPoint(_ point: NormalizedPoint, to id: UUID) {
        updateContinuous { state in
            guard let index = state.localAdjustments.firstIndex(where: { $0.id == id }),
                  case var .brush(brush) = state.localAdjustments[index].mask,
                  brush.points.count < 512,
                  brush.points.last.map({ hypot($0.x - point.x, $0.y - point.y) > 0.008 }) ?? true else { return }
            brush.points.append(point)
            state.localAdjustments[index].mask = .brush(brush)
        }
    }

    func endLocalBrushStroke() { endContinuousEdit() }

    func deleteLocalAdjustment(id: UUID) {
        update { $0.localAdjustments.removeAll { $0.id == id } }
        if selectedLocalAdjustmentID == id { selectedLocalAdjustmentID = state.localAdjustments.first?.id }
    }

    func selectLUT(_ id: UUID?) {
        let kind = id.flatMap { selectedID in lutRepository.items.first(where: { $0.id == selectedID })?.kind }
        update { state in
            switch kind {
            case .technical:
                state.lut.technicalLUTID = id
            case .creative:
                state.lut.selectedLUTID = id
            case nil:
                state.lut.selectedLUTID = nil
                state.lut.intensity = 1
            }
        }
        if let id { recentSettings.record(lut: id) }
    }

    func selectTechnicalLUT(_ id: UUID?) {
        update { $0.lut.technicalLUTID = id }
        if let id { recentSettings.record(lut: id) }
    }

    func configureLUT(id: UUID, kind: LUTKind, colorMetadata: LUTColorMetadata) {
        do {
            try lutRepository.configure(id: id, kind: kind, colorMetadata: colorMetadata)
            update { state in
                if state.lut.selectedLUTID == id, kind == .technical {
                    state.lut.selectedLUTID = nil
                    state.lut.technicalLUTID = id
                } else if state.lut.technicalLUTID == id, kind == .creative {
                    state.lut.technicalLUTID = nil
                    state.lut.selectedLUTID = id
                }
            }
            lutPreviewCache.clear()
            schedulePreviewRender()
        } catch {
            present(error)
        }
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
        state = pasted.canonicalized()
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
        state = applied.canonicalized()
        recentSettings.record(preset: id)
        lutPreviewCache.clear()
        schedulePreviewRender()
    }

    func importPreset(url: URL) {
        do { try presetRepository.importPreset(from: url) }
        catch { present(error) }
    }

    func togglePresetFavorite(id: UUID) {
        do { try presetRepository.toggleFavorite(id: id) }
        catch { present(error) }
    }

    func renamePreset(id: UUID, to name: String) {
        do { try presetRepository.rename(id: id, to: name) }
        catch { present(error) }
    }

    func deletePreset(id: UUID) {
        do { try presetRepository.delete(id: id) }
        catch { present(error) }
    }

    func exportPresetData(id: UUID) -> Data? {
        do { return try presetRepository.exportData(id: id) }
        catch {
            present(error)
            return nil
        }
    }

    func importLUT(url: URL) {
        do {
            try lutRepository.importLUT(from: url)
            lutPreviewCache.clear()
        } catch {
            present(error)
        }
    }

    func toggleLUTFavorite(id: UUID) {
        do { try lutRepository.toggleFavorite(id: id) }
        catch { present(error) }
    }

    func renameLUT(id: UUID, to name: String) {
        do { try lutRepository.rename(id: id, to: name) }
        catch { present(error) }
    }

    func deleteLUT(id: UUID) {
        let wasCreativeSelection = state.lut.selectedLUTID == id
        let wasTechnicalSelection = state.lut.technicalLUTID == id
        do {
            try lutRepository.delete(id: id)
            if wasCreativeSelection { selectLUT(nil) }
            if wasTechnicalSelection { selectTechnicalLUT(nil) }
            lutPreviewCache.clear()
        } catch {
            present(error)
        }
    }

    func thumbnail(for id: UUID) -> CGImage? {
        if let cached = lutPreviewCache[id] { return cached }
        guard let asset else { return nil }
        guard lutPreviewCache.beginRequest(for: id) else { return nil }
        let thumbnailState = state
        Task { [weak self, pipeline, asset, thumbnailState] in
            guard let self else { return }
            defer { self.lutPreviewCache.finishRequest(for: id) }
            guard let lut = try? self.lutRepository.lut(for: id), lut.kind == .creative else { return }
            var renderState = thumbnailState
            renderState.lut.selectedLUTID = id
            renderState.lut.intensity = 1
            let technicalLUT = self.lut(for: renderState.lut.technicalLUTID)
            guard let image = try? await pipeline.render(
                asset: asset,
                state: renderState,
                lut: lut,
                technicalLUT: technicalLUT,
                mode: .preview(maximumDimension: 256)
            ) else { return }
            self.lutPreviewCache[id] = image
            self.objectWillChange.send()
        }
        return nil
    }

    func export(settings: ExportSettings) {
        guard let asset, !isExporting else { return }
        isExporting = true
        errorMessage = nil
        recentSettings.record(export: settings)
        let state = state
        let luts = selectedLUTs(for: state)
        exportTask = Task { [weak self, pipeline, asset, state, luts] in
            do {
                let output = try await ImageExporter.export(
                    asset: asset,
                    state: state,
                    lut: luts.creative,
                    technicalLUT: luts.technical,
                    settings: settings,
                    pipeline: pipeline
                )
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

    func cancelExport() {
        exportTask?.cancel()
        exportTask = nil
        isExporting = false
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
        batchState = copied.canonicalized()
        batchAdjustmentSource = "已复制的调整"
        return true
    }

    func applyPresetToBatch(id: UUID) {
        guard let preset = presetRepository.preset(id: id) else { return }
        batchState = preset.payload.applying(to: .initial).canonicalized()
        batchAdjustmentSource = "预设：\(preset.name)"
        recentSettings.record(preset: id)
    }

    func applyLUTToBatch(id: UUID?) {
        let kind = id.flatMap { selectedID in lutRepository.items.first(where: { $0.id == selectedID })?.kind }
        switch kind {
        case .technical:
            batchState.lut.technicalLUTID = id
        case .creative:
            batchState.lut.selectedLUTID = id
            batchState.lut.intensity = 1
        case nil:
            batchState.lut.selectedLUTID = nil
            batchState.lut.intensity = 1
        }
        batchAdjustmentSource = id == nil ? "不使用 LUT" : "LUT：\(lutRepository.items.first(where: { $0.id == id })?.name ?? "已选")"
        if let id { recentSettings.record(lut: id) }
    }

    func startBatchExport(settings: ExportSettings) {
        guard !batchPhotos.isEmpty, !isBatchExporting else { return }
        let luts = selectedLUTs(for: batchState)
        guard (batchState.lut.selectedLUTID == nil || luts.creative != nil),
              (batchState.lut.technicalLUTID == nil || luts.technical != nil) else { return }
        let jobs = batchPhotos.map {
            BatchExportJob(id: $0.id, photo: $0, state: batchState, lut: luts.creative, technicalLUT: luts.technical, settings: settings)
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
                    dynamicRange: reference.hasHDRContent ? .hdr : .sdr,
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

    /// 安装与重置都必须依据资产类型建立默认状态：RAW 资产需要保留独立的 RAW
    /// decode state，不能在全局重置后变成普通图片状态。
    func install(asset: ImageAsset, scheduleRendering: Bool = true, persistSession: Bool = true) {
        self.asset = asset
        state = Self.defaultState(for: asset)
        selectedLocalAdjustmentID = nil
        undoStack.removeAll()
        pendingContinuousUndo = nil
        lutPreviewCache.clear()
        if persistSession { saveNewSession(for: asset) }
        guard scheduleRendering else { return }
        renderOriginalPreview()
        schedulePreviewRender()
    }

    static func defaultState(for asset: ImageAsset?) -> EditState {
        var state = EditState.initial
        if asset?.isRAW == true {
            state.raw = RAWAdjustments()
        }
        return state
    }

    private func beginLoading() -> Int {
        loadTask?.cancel()
        sessionRestoreTask?.cancel()
        isRestoringSession = false
        cancelRender()
        originalPreviewTask?.cancel()
        loadGeneration += 1
        previewImage = nil
        originalPreviewImage = nil
        histogram = .empty
        isRendering = true
        return loadGeneration
    }

    private func finishLoadingCancellation(generation: Int) {
        guard loadGeneration == generation else { return }
        isRendering = false
    }

    private func finishLoadingWithError(_ error: Error, generation: Int) {
        guard loadGeneration == generation else { return }
        isRendering = false
        present(error)
    }

    private func selectedLUTs(for renderState: EditState) -> (creative: LUT?, technical: LUT?) {
        (lut(for: renderState.lut.selectedLUTID), lut(for: renderState.lut.technicalLUTID))
    }

    private func lut(for id: UUID?) -> LUT? {
        guard let id else { return nil }
        do { return try lutRepository.lut(for: id) }
        catch {
            present(error)
            return nil
        }
    }

    private func renderOriginalPreview() {
        guard let asset else { return }
        originalPreviewTask?.cancel()
        let assetID = asset.id
        originalPreviewTask = Task { [weak self, pipeline, asset, assetID] in
            let image = try? await pipeline.render(
                asset: asset,
                state: .initial,
                lut: nil,
                dynamicRange: asset.hasHDRContent ? .hdr : .sdr,
                mode: .preview(maximumDimension: 2048)
            )
            guard !Task.isCancelled, self?.asset?.id == assetID else { return }
            self?.originalPreviewImage = image
        }
    }

    private func schedulePreviewRender(debounceNanoseconds: UInt64 = 0) {
        guard let asset else {
            isRendering = false
            return
        }
        renderTask?.cancel()
        histogramTask?.cancel()
        renderGeneration += 1
        let generation = renderGeneration
        let state = state
        let luts = selectedLUTs(for: state)
        if let activeSessionID {
            scheduleSessionStateSave(sessionID: activeSessionID, state: state)
        }
        isRendering = true
        renderTask = Task { [weak self, pipeline, asset, state, luts] in
            do {
                if debounceNanoseconds > 0 {
                    try await Task.sleep(nanoseconds: debounceNanoseconds)
                }
                let rendered = try await pipeline.render(
                    asset: asset,
                    state: state,
                    lut: luts.creative,
                    technicalLUT: luts.technical,
                    dynamicRange: asset.hasHDRContent ? .hdr : .sdr,
                    mode: .preview(maximumDimension: 2048)
                )
                guard !Task.isCancelled, self?.renderGeneration == generation else { return }
                self?.previewImage = rendered
                self?.isRendering = false
                self?.scheduleHistogram(for: rendered, assetID: asset.id, renderGeneration: generation)
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

    private func scheduleHistogram(for preview: CGImage, assetID: UUID, renderGeneration: Int) {
        histogramTask?.cancel()
        histogramTask = Task { [weak self, pipeline] in
            do {
                try await Task.sleep(nanoseconds: 160_000_000)
                let computed = try await pipeline.histogram(for: preview)
                guard !Task.isCancelled,
                      self?.asset?.id == assetID,
                      self?.renderGeneration == renderGeneration else { return }
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

    private func saveNewSession(for asset: ImageAsset) {
        guard let sessionStore else { return }
        sessionSourceSaveTask?.cancel()
        sessionStateSaveTask?.cancel()
        sessionRevision += 1
        let revision = sessionRevision
        let state = state
        activeSessionID = asset.id
        sessionSourceSaveTask = Task { [weak self] in
            do {
                try await sessionStore.saveNew(
                    id: asset.id,
                    sourceName: asset.sourceName,
                    sourceData: asset.originalData,
                    state: state,
                    revision: revision
                )
                guard !Task.isCancelled else { return }
                self?.hasRestorableSession = true
            } catch is CancellationError {
                // A newer import owns the persisted session.
            } catch {
                self?.present(error)
            }
        }
    }

    private func scheduleSessionStateSave(sessionID: UUID, state: EditState) {
        guard let sessionStore, !isRestoringSession else { return }
        sessionStateSaveTask?.cancel()
        sessionRevision += 1
        let revision = sessionRevision
        sessionStateSaveTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
                try await sessionStore.updateState(id: sessionID, state: state, revision: revision)
            } catch is CancellationError {
                // Debounced by a newer edit.
            } catch {
                self?.present(error)
            }
        }
    }
}
