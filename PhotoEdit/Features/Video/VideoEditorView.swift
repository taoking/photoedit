import AVFoundation
import AVKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class VideoEditorViewModel: ObservableObject {
    @Published private(set) var asset: VideoAsset?
    @Published var state = VideoEditState()
    @Published private(set) var player: AVPlayer?
    @Published private(set) var isLoading = false
    @Published private(set) var isExporting = false
    @Published var exportedVideo: ExportedVideo?
    @Published var errorMessage: String?

    let lutRepository: LUTRepository
    private let sourceURL: URL
    private var previewGeneration = 0
    private var previewTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?

    init(sourceURL: URL, lutRepository: LUTRepository = LUTRepository()) {
        self.sourceURL = sourceURL
        self.lutRepository = lutRepository
    }

    deinit {
        previewTask?.cancel()
        exportTask?.cancel()
    }

    var eligibleLUTItems: [LUTCatalogItem] {
        lutRepository.items.filter {
            $0.kind == .creative && $0.colorMetadata.inputColorSpace == .sRGB && $0.colorMetadata.outputColorSpace == .sRGB
        }
    }

    var undeclaredCreativeLUTItems: [LUTCatalogItem] {
        lutRepository.items.filter {
            $0.kind == .creative && !$0.colorMetadata.isComplete
        }
    }

    func load() {
        guard !isLoading, asset == nil else { return }
        isLoading = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await VideoAsset.importFromFile(url: self.sourceURL)
                guard !Task.isCancelled else { return }
                self.asset = loaded
                self.isLoading = false
                self.configurePreview()
            } catch is CancellationError {
                self.isLoading = false
            } catch {
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func update(_ change: (inout VideoEditState) -> Void) {
        let oldState = state
        change(&state)
        guard oldState != state else { return }
        configurePreview()
    }

    func reset() {
        guard state != VideoEditState() else { return }
        state = VideoEditState()
        configurePreview()
    }

    func selectLUT(_ id: UUID?) {
        guard let id else {
            update {
                $0.selectedLUTID = nil
                $0.lutIntensity = 1
            }
            return
        }
        do {
            let lut = try lutRepository.lut(for: id)
            guard lut.kind == .creative,
                  lut.colorMetadata.inputColorSpace == .sRGB,
                  lut.colorMetadata.outputColorSpace == .sRGB else {
                throw VideoEditorError.unsupportedLUTColorSpace(name: lut.title ?? "未命名 LUT")
            }
            update { $0.selectedLUTID = id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importLUT(url: URL) {
        do {
            try lutRepository.importLUT(from: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// `.cube` 没有可信的色彩空间字段；只有用户明确确认后才允许它进入 SDR 视频列表。
    func declareLUTAsSRGBCreative(id: UUID) {
        do {
            try lutRepository.configure(id: id, kind: .creative, colorMetadata: .sRGB)
            selectLUT(id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func export() {
        guard let asset, !isExporting else { return }
        guard let lut = selectedLUT() else {
            if state.selectedLUTID != nil { return }
            startExport(asset: asset, lut: nil)
            return
        }
        startExport(asset: asset, lut: lut)
    }

    func clearExportedVideo() {
        if let fileURL = exportedVideo?.fileURL { try? FileManager.default.removeItem(at: fileURL) }
        exportedVideo = nil
    }

    private func selectedLUT() -> LUT? {
        guard let id = state.selectedLUTID else { return nil }
        do {
            let lut = try lutRepository.lut(for: id)
            guard lut.kind == .creative,
                  lut.colorMetadata.inputColorSpace == .sRGB,
                  lut.colorMetadata.outputColorSpace == .sRGB else {
                throw VideoEditorError.unsupportedLUTColorSpace(name: lut.title ?? "未命名 LUT")
            }
            return lut
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func configurePreview() {
        guard let asset else { return }
        let lut = selectedLUT()
        guard state.selectedLUTID == nil || lut != nil else { return }
        previewTask?.cancel()
        previewGeneration += 1
        let generation = previewGeneration
        let renderState = state
        let currentTime = player?.currentTime() ?? .zero
        previewTask = Task { [weak self] in
            let playerAsset = AVURLAsset(url: asset.sourceURL)
            do {
                _ = try await playerAsset.load(.duration)
                _ = try await playerAsset.loadTracks(withMediaType: .video)
                guard !Task.isCancelled, let self, generation == self.previewGeneration else { return }
                let item = AVPlayerItem(asset: playerAsset)
                item.videoComposition = VideoFrameProcessor.videoComposition(
                    asset: playerAsset,
                    state: renderState,
                    lut: lut,
                    transform: asset.frameTransform
                )
                if let player = self.player {
                    player.replaceCurrentItem(with: item)
                    await player.seek(to: currentTime, toleranceBefore: .zero, toleranceAfter: .zero)
                } else {
                    self.player = AVPlayer(playerItem: item)
                }
            } catch is CancellationError {
                // A newer adjustment superseded this preview.
            } catch {
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    private func startExport(asset: VideoAsset, lut: LUT?) {
        exportTask?.cancel()
        isExporting = true
        errorMessage = nil
        let renderState = state
        exportTask = Task { [weak self] in
            do {
                let output = try await VideoExporter.export(asset: asset, state: renderState, lut: lut)
                guard !Task.isCancelled else { return }
                self?.exportedVideo = output
                self?.isExporting = false
            } catch is CancellationError {
                self?.isExporting = false
            } catch {
                self?.isExporting = false
                self?.errorMessage = error.localizedDescription
            }
        }
    }
}

struct VideoEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: VideoEditorViewModel
    @State private var showingLUTImporter = false

    init(sourceURL: URL) {
        _model = StateObject(wrappedValue: VideoEditorViewModel(sourceURL: sourceURL))
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoading {
                    ProgressView("正在导入视频")
                } else if let asset = model.asset {
                    editor(asset: asset)
                } else {
                    ContentUnavailableView("无法打开视频", systemImage: "exclamationmark.triangle", description: Text("请选择含有视频轨道的文件。"))
                }
            }
            .navigationTitle(model.asset?.sourceName ?? "视频 LUT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                if model.asset != nil {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("重置") { model.reset() }
                        Button {
                            model.export()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .disabled(model.isExporting)
                    }
                }
            }
        }
        .task { model.load() }
        .fileImporter(
            isPresented: $showingLUTImporter,
            allowedContentTypes: [UTType(filenameExtension: "cube") ?? .data]
        ) { result in
            if case let .success(url) = result { model.importLUT(url: url) }
            if case let .failure(error) = result { model.errorMessage = error.localizedDescription }
        }
        .alert("发生错误", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "未知错误")
        }
        .sheet(isPresented: Binding(
            get: { model.exportedVideo != nil },
            set: { if !$0 { model.clearExportedVideo() } }
        )) {
            if let output = model.exportedVideo {
                VideoExportResultView(output: output)
            }
        }
    }

    private func editor(asset: VideoAsset) -> some View {
        VStack(spacing: 0) {
            VideoPlayer(player: model.player)
                .frame(maxHeight: .infinity)
                .background(.black)
                .accessibilityLabel("视频 LUT 预览")

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(formatDuration(asset.durationSeconds), systemImage: "clock")
                        Spacer()
                        Text("\(asset.width) × \(asset.height)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    videoSlider("曝光", value: binding(\.exposure), range: -5...5, suffix: " EV")
                    videoSlider("对比度", value: binding(\.contrast), range: -100...100)
                    videoSlider("饱和度", value: binding(\.saturation), range: -100...100)

                    Divider()
                    HStack {
                        Text("Creative LUT").font(.headline)
                        Spacer()
                        Button("导入 .cube", systemImage: "square.and.arrow.down") { showingLUTImporter = true }
                    }
                    Picker("LUT", selection: lutSelection) {
                        Text("不使用 LUT").tag(Optional<UUID>.none)
                        ForEach(model.eligibleLUTItems) { item in
                            Text(item.name).tag(Optional(item.id))
                        }
                    }
                    .pickerStyle(.menu)
                    videoSlider("LUT 强度", value: binding(\.lutIntensity), range: 0...1, suffix: "")
                    if !model.undeclaredCreativeLUTItems.isEmpty {
                        Divider()
                        Text("新导入的 .cube 不携带可信色彩空间。仅在 LUT 作者明确注明 sRGB 输入与输出时，才确认以下声明：")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(model.undeclaredCreativeLUTItems) { item in
                            Button("确认 \(item.name) 为 sRGB Creative LUT") {
                                model.declareLUTAsSRGBCreative(id: item.id)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    Text("视频仅显示已声明为 sRGB → sRGB 的 Creative LUT；预览和导出使用同一 AVFoundation/Core Image 视频组合。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if model.isExporting {
                        HStack { ProgressView(); Text("正在导出视频…") }
                    }
                }
                .padding()
            }
            .frame(height: 285)
        }
    }

    private func binding(_ keyPath: WritableKeyPath<VideoEditState, Double>) -> Binding<Double> {
        Binding(
            get: { model.state[keyPath: keyPath] },
            set: { value in model.update { $0[keyPath: keyPath] = value } }
        )
    }

    private var lutSelection: Binding<UUID?> {
        Binding<UUID?>(
            get: { model.state.selectedLUTID },
            set: { selectedID in model.selectLUT(selectedID) }
        )
    }

    private func videoSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String = "") -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue, format: .number.precision(.fractionLength(range.upperBound == 5 ? 1 : range.upperBound == 1 ? 0 : 0)))\(suffix)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range)
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let value = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

private struct VideoExportResultView: View {
    let output: ExportedVideo

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
            Text("视频已导出").font(.title2.weight(.semibold))
            Text("已生成 \(output.fileType == .mp4 ? "MP4" : "MOV") 文件；请通过系统共享面板保存或发送。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            ShareLink(item: output.fileURL) {
                Label("分享或存储视频", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .presentationDetents([.medium])
    }
}
