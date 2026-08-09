import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum EditorSecondarySurface: String, Identifiable {
    case presets
    case batch

    var id: String { rawValue }
}

struct EditorView: View {
    @StateObject private var model = EditorViewModel()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingImageImporter = false
    @State private var showingVideoImporter = false
    @State private var selectedVideoURL: URL?
    @State private var showingLUTImporter = false
    @State private var showingPresetImporter = false
    @State private var showingExportOptions = false
    @State private var showingFileExporter = false
    @State private var exportDocument = ImageExportDocument()
    @State private var exportType: UTType = .jpeg
    @State private var exportFilename = "Photo-edited.jpg"
    @State private var showingPresetFileExporter = false
    @State private var presetDocument = PresetDocument()
    @State private var presetFilename = "Preset.json"
    @State private var showingSelectivePaste = false
    @State private var showingBatchImporter = false
    @State private var showingReferenceImporter = false
    @State private var showingBatchExportOptions = false
    @State private var secondarySurface: EditorSecondarySurface?
    @State private var tool: EditorTool = .light
    @State private var isParameterPanelExpanded = false
    @State private var zoom: CGFloat = 1
    @State private var pan = CGSize.zero
    @State private var previewCanvasSize = CGSize.zero
    @GestureState private var gestureMagnification: CGFloat = 1
    @GestureState private var gestureTranslation = CGSize.zero

    var body: some View {
        Group {
            if model.asset == nil {
                importLanding
            } else {
                editor
            }
        }
        // WindowGroup 根部使用条件视图时，两个分支都必须明确占用可用窗口。
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
        .tint(.cyan)
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw ImageEditorError.imageLoadFailed
                    }
                    model.loadImage(data: data, sourceName: item.itemIdentifier ?? "Photo")
                } catch {
                    model.errorMessage = error.localizedDescription
                }
            }
        }
        .onChange(of: model.asset?.id) { _, _ in
            resetViewport()
            if tool == .raw, model.asset?.isRAW != true {
                tool = .light
            }
        }
        .onChange(of: model.isShowingReference) { _, _ in
            revalidateViewport(in: previewCanvasSize)
        }
        .fileImporter(
            isPresented: $showingImageImporter,
            allowedContentTypes: supportedImageTypes,
            onCompletion: handleImageImport
        )
        .fileImporter(
            isPresented: $showingVideoImporter,
            allowedContentTypes: [.movie],
            onCompletion: handleVideoImport
        )
        .fileImporter(
            isPresented: $showingBatchImporter,
            allowedContentTypes: supportedImageTypes,
            allowsMultipleSelection: true,
            onCompletion: handleBatchImport
        )
        .fileImporter(
            isPresented: $showingReferenceImporter,
            allowedContentTypes: supportedImageTypes,
            onCompletion: handleReferenceImport
        )
        .fileImporter(isPresented: $showingLUTImporter, allowedContentTypes: [UTType(filenameExtension: "cube") ?? .data], onCompletion: handleLUTImport)
        .fileImporter(isPresented: $showingPresetImporter, allowedContentTypes: [.json], onCompletion: handlePresetImport)
        .sheet(isPresented: $showingExportOptions) {
            ExportOptionsView(model: model)
        }
        .sheet(isPresented: $showingBatchExportOptions) {
            BatchExportOptionsView(model: model)
        }
        .sheet(isPresented: Binding(
            get: { model.exportedImage != nil },
            set: { if !$0 { model.clearExport() } }
        )) {
            if let output = model.exportedImage {
                ExportResultView(output: output) { output in
                    exportDocument = ImageExportDocument(data: output.data)
                    exportType = output.type
                    exportFilename = output.filename
                    showingFileExporter = true
                }
            }
        }
        .fileExporter(
            isPresented: $showingFileExporter,
            document: exportDocument,
            contentType: exportType,
            defaultFilename: exportFilename
        ) { result in
            if case let .failure(error) = result { model.errorMessage = error.localizedDescription }
        }
        .fileExporter(
            isPresented: $showingPresetFileExporter,
            document: presetDocument,
            contentType: .json,
            defaultFilename: presetFilename
        ) { result in
            if case let .failure(error) = result { model.errorMessage = error.localizedDescription }
        }
        .sheet(isPresented: $showingSelectivePaste) {
            SelectivePasteView(model: model)
        }
        .sheet(item: $secondarySurface) { surface in
            NavigationStack {
                secondarySurfaceContent(surface)
                    .navigationTitle(surface == .presets ? "预设" : "批量处理")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { secondarySurface = nil }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .alert("发生错误", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "未知错误")
        }
        .fullScreenCover(isPresented: Binding(
            get: { selectedVideoURL != nil },
            set: { if !$0 { selectedVideoURL = nil } }
        )) {
            if let selectedVideoURL {
                VideoEditorView(sourceURL: selectedVideoURL)
            }
        }
    }

    private var importLanding: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ContentUnavailableView {
                Label("导入照片开始编辑", systemImage: "photo.on.rectangle")
                    .foregroundStyle(.white)
            } description: {
                Text("支持 JPEG、HEIC/HEIF 与 PNG。原始照片不会被修改。")
                    .foregroundStyle(.white.opacity(0.72))
            } actions: {
                VStack(spacing: 12) {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("从照片导入", systemImage: "photo")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        showingImageImporter = true
                    } label: {
                        Label("从文件导入", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        showingVideoImporter = true
                    } label: {
                        Label("导入视频并套用 LUT", systemImage: "video")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: 280)
            }
        }
    }

    private var editor: some View {
        GeometryReader { screen in
            VStack(spacing: 0) {
                editorToolbar
                    .padding(.horizontal, 12)
                    .padding(.top, screen.safeAreaInsets.top + 8)
                    .padding(.bottom, 6)

                // 预览只占用工具栏和控制区之间实际可见的工作区，绝不在控件下方延伸。
                previewCanvas
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                editorControls(availableHeight: screen.size.height - screen.safeAreaInsets.top - screen.safeAreaInsets.bottom)
                    .padding(.bottom, screen.safeAreaInsets.bottom)
                    .background(Color.photoEditControlSurface)
            }
            // 根视图没有 NavigationStack；明确填满 WindowGroup，避免 GeometryReader
            // 以最小理想高度居中，造成预览或工具栏被截断。
            .frame(width: screen.size.width, height: screen.size.height, alignment: .top)
            .background(Color.photoEditWorkspace)
            .foregroundStyle(.white)
        }
        .background(Color.photoEditWorkspace.ignoresSafeArea())
    }

    private var editorToolbar: some View {
        EditorTopBar(
            canUndo: model.canUndo,
            close: closeCurrentPhoto,
            undo: model.undo,
            export: { showingExportOptions = true },
            setShowingBefore: { model.isShowingBefore = $0 }
        ) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("从照片重新导入", systemImage: "photo")
            }
            Button("从文件重新导入", systemImage: "folder") {
                showingImageImporter = true
            }
            Divider()
            Button("预设", systemImage: "slider.horizontal.3") {
                secondarySurface = .presets
            }
            Button("批量处理", systemImage: "photo.stack") {
                secondarySurface = .batch
            }
            Button("载入参考照片", systemImage: "rectangle.split.2x1") {
                showingReferenceImporter = true
            }
            if model.referencePreviewImage != nil {
                Button(model.isShowingReference ? "关闭参考图" : "显示参考图", systemImage: "rectangle.split.2x1") {
                    model.isShowingReference.toggle()
                }
            }
            Divider()
            Button("导入视频并套用 LUT", systemImage: "video.badge.plus") {
                showingVideoImporter = true
            }
            Button("复制全部调整", systemImage: "doc.on.doc") { model.copyAllAdjustments() }
            Button("粘贴全部调整", systemImage: "doc.on.clipboard") {
                model.pasteAdjustments()
            }
            .disabled(!model.adjustmentClipboard.hasAdjustments)
            Button("选择性粘贴", systemImage: "checklist") {
                showingSelectivePaste = true
            }
            .disabled(!model.adjustmentClipboard.hasAdjustments)
            Divider()
            Button("重置全部调整", systemImage: "arrow.counterclockwise", role: .destructive) {
                model.reset()
            }
            Button("关闭当前照片", systemImage: "xmark", role: .destructive) {
                closeCurrentPhoto()
            }
        }
    }

    private var previewCanvas: some View {
        GeometryReader { geometry in
            ZStack {
                Color.photoEditWorkspace
                if model.isShowingReference, let reference = model.referencePreviewImage {
                    let splitWidth = Swift.max(0, (geometry.size.width - 1) / 2)
                    let splitCanvasSize = CGSize(width: splitWidth, height: geometry.size.height)
                    HStack(spacing: 1) {
                        fittedPreview(reference, canvasSize: splitCanvasSize, accessibilityLabel: "参考照片")
                        if let image = displayedPreviewImage {
                            editablePreview(image, canvasSize: splitCanvasSize)
                        }
                    }
                } else if let image = displayedPreviewImage {
                    editablePreview(image, canvasSize: geometry.size)
                } else {
                    ProgressView("正在准备预览")
                        .tint(.white)
                        .foregroundStyle(.white)
                }
                if model.isRendering && model.previewImage != nil {
                    ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding()
                }
                if model.usesHDRPreview {
                    Label("HDR 预览", systemImage: "sun.max.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.55), in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding()
                }
            }
            .clipShape(Rectangle())
            .onTapGesture(count: 2) { withAnimation { resetViewport() } }
            .onAppear {
                previewCanvasSize = geometry.size
                revalidateViewport(in: geometry.size)
            }
            .onChange(of: geometry.size) { _, size in
                previewCanvasSize = size
                revalidateViewport(in: size)
            }
        }
    }

    private var displayedPreviewImage: CGImage? {
        model.isShowingBefore ? model.originalPreviewImage : model.previewImage
    }

    private func fittedPreview(_ image: CGImage, canvasSize: CGSize, accessibilityLabel: String) -> some View {
        let fittedSize = PreviewGeometry.aspectFitSize(
            imageSize: CGSize(width: image.width, height: image.height),
            in: canvasSize
        )

        return DynamicRangeImage(image: image)
            // UIKit 视图只占等比适配后的图像矩形，仍使用 .scaleAspectFit 保留 HDR 预览。
            .frame(width: fittedSize.width, height: fittedSize.height)
            .frame(width: canvasSize.width, height: canvasSize.height)
            .accessibilityLabel(accessibilityLabel)
    }

    private func editablePreview(_ image: CGImage, canvasSize: CGSize) -> some View {
        let imageSize = CGSize(width: image.width, height: image.height)
        let fittedSize = PreviewGeometry.aspectFitSize(imageSize: imageSize, in: canvasSize)
        let scale = displayedZoom
        return DynamicRangeImage(image: image)
            // 将 representable 明确限制在适配后的图像矩形；外层只提供裁切和手势区域。
            .frame(width: fittedSize.width, height: fittedSize.height)
            .scaleEffect(scale)
            .offset(clampedPan(pan.adding(gestureTranslation), imageSize: imageSize, canvasSize: canvasSize, scale: scale))
            .frame(width: canvasSize.width, height: canvasSize.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(imageGesture(for: imageSize, in: canvasSize))
            .accessibilityLabel(model.isShowingBefore ? "原图预览" : "编辑结果预览")
    }

    private func editorControls(availableHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            if isParameterPanelExpanded {
                EditorParameterPanel(tool: tool, collapse: toggleParameterPanel) {
                    parameterPanelContent
                }
                .frame(height: parameterPanelHeight(for: availableHeight))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            EditorToolRail(
                tools: availableTools,
                selection: $tool,
                selectTool: selectTool
            )
        }
        .background(Color.photoEditControlSurface)
        .overlay(alignment: .top) { Divider().overlay(.white.opacity(0.1)) }
    }

    @ViewBuilder
    private var parameterPanelContent: some View {
        switch tool {
        case .light: LightPanel(model: model)
        case .color: ColorPanel(model: model)
        case .detail: DetailPanel(model: model)
        case .hsl: HSLPanel(model: model)
        case .curves: ToneCurvePanel(model: model)
        case .lut: LUTPanel(model: model, showingImporter: $showingLUTImporter)
        case .crop: CropPanel(model: model)
        case .local: LocalAdjustmentsPanel(model: model)
        case .raw: RAWPanel(model: model)
        }
    }

    private var availableTools: [EditorTool] {
        EditorTool.allCases.filter { $0 != .raw || model.asset?.isRAW == true }
    }

    private func parameterPanelHeight(for availableHeight: CGFloat) -> CGFloat {
        let preferredHeight: CGFloat = switch tool {
        case .light, .color: 214
        case .detail: 184
        case .hsl: 204
        case .curves, .lut: 230
        case .crop: 202
        case .local, .raw: 240
        }

        // 横屏时参数区不应吞掉照片工作区；纵屏仍保持各面板的完整常用高度。
        guard availableHeight.isFinite, availableHeight > 0 else { return preferredHeight }
        let adaptiveLimit = Swift.max(132, Swift.min(260, availableHeight * 0.32))
        return Swift.min(preferredHeight, adaptiveLimit)
    }

    private var displayedZoom: CGFloat {
        (zoom * gestureMagnification).clamped(to: 1...5)
    }

    private func selectTool(_ newTool: EditorTool) {
        tool = newTool
        if !isParameterPanelExpanded {
            withAnimation(.easeInOut(duration: 0.2)) { isParameterPanelExpanded = true }
        }
    }

    private func toggleParameterPanel() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isParameterPanelExpanded.toggle()
        }
    }

    private func closeCurrentPhoto() {
        selectedPhoto = nil
        model.closeCurrentAsset()
        tool = .light
        isParameterPanelExpanded = false
        resetViewport()
    }

    private func resetViewport() {
        zoom = 1
        pan = .zero
    }

    private func imageGesture(for imageSize: CGSize, in canvasSize: CGSize) -> some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .updating($gestureMagnification) { value, state, _ in
                    state = value
                }
                .onEnded { value in
                    zoom = (zoom * value).clamped(to: 1...5)
                    pan = clampedPan(pan, imageSize: imageSize, canvasSize: canvasSize, scale: zoom)
                },
            DragGesture()
                .updating($gestureTranslation) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    pan = clampedPan(pan.adding(value.translation), imageSize: imageSize, canvasSize: canvasSize, scale: displayedZoom)
                }
        )
    }

    private func revalidateViewport(in canvasSize: CGSize) {
        guard let image = displayedPreviewImage else {
            pan = .zero
            return
        }
        let visibleCanvasSize = model.isShowingReference
            ? CGSize(width: Swift.max(0, (canvasSize.width - 1) / 2), height: canvasSize.height)
            : canvasSize
        pan = clampedPan(
            pan,
            imageSize: CGSize(width: image.width, height: image.height),
            canvasSize: visibleCanvasSize,
            scale: zoom
        )
    }

    private func clampedPan(_ candidate: CGSize, imageSize: CGSize, canvasSize: CGSize, scale: CGFloat) -> CGSize {
        let fittedSize = PreviewGeometry.aspectFitSize(imageSize: imageSize, in: canvasSize)
        return PreviewGeometry.clampedPan(candidate, fittedImageSize: fittedSize, in: canvasSize, zoom: scale)
    }

    @ViewBuilder
    private func secondarySurfaceContent(_ surface: EditorSecondarySurface) -> some View {
        switch surface {
        case .presets:
            PresetPanel(
                model: model,
                showingImporter: $showingPresetImporter,
                exportPreset: { id, name in
                    guard let data = try? model.presetRepository.exportData(id: id) else { return }
                    presetDocument = PresetDocument(data: data)
                    presetFilename = name + ".json"
                    showingPresetFileExporter = true
                }
            )
        case .batch:
            BatchPanel(
                model: model,
                showingImporter: $showingBatchImporter,
                showingReferenceImporter: $showingReferenceImporter,
                showingExportOptions: $showingBatchExportOptions
            )
        }
    }

    private var supportedImageTypes: [UTType] {
        [.jpeg, .heic, .heif, .png, UTType(filenameExtension: "dng") ?? .data, UTType(filenameExtension: "arw") ?? .data]
    }

    private func handleImageImport(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url): model.loadImage(url: url)
        case let .failure(error): model.errorMessage = error.localizedDescription
        }
    }

    private func handleVideoImport(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url): selectedVideoURL = url
        case let .failure(error): model.errorMessage = error.localizedDescription
        }
    }

    private func handleBatchImport(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls): model.addBatchPhotos(urls: urls)
        case let .failure(error): model.errorMessage = error.localizedDescription
        }
    }

    private func handleReferenceImport(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url): model.loadReference(url: url)
        case let .failure(error): model.errorMessage = error.localizedDescription
        }
    }

    private func handleLUTImport(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url): model.importLUT(url: url)
        case let .failure(error): model.errorMessage = error.localizedDescription
        }
    }

    private func handlePresetImport(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url): model.importPreset(url: url)
        case let .failure(error): model.errorMessage = error.localizedDescription
        }
    }
}

private extension CGSize {
    func adding(_ other: CGSize) -> CGSize {
        CGSize(width: width + other.width, height: height + other.height)
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

/// `UIImageView` 明确请求 high dynamic range；SDR 图片在该视图中保持原样。
private struct DynamicRangeImage: UIViewRepresentable {
    let image: CGImage

    func makeUIView(context _: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.preferredImageDynamicRange = .high
        return imageView
    }

    func updateUIView(_ imageView: UIImageView, context _: Context) {
        imageView.image = UIImage(cgImage: image)
        // SwiftUI 可能复用 representable；每次更新都重申内容模式，确保显式的
        // fitted frame 内仍按图像原始比例显示，而非被复用视图拉伸。
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.preferredImageDynamicRange = .high
    }
}

struct HistogramView: View {
    let histogram: Histogram

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let maximum = max(1, histogram.red.max() ?? 0, histogram.green.max() ?? 0, histogram.blue.max() ?? 0, histogram.luminance.max() ?? 0)
                draw(histogram.luminance, color: .gray.opacity(0.8), in: &context, size: size, maximum: maximum)
                draw(histogram.red, color: .red.opacity(0.65), in: &context, size: size, maximum: maximum)
                draw(histogram.green, color: .green.opacity(0.55), in: &context, size: size, maximum: maximum)
                draw(histogram.blue, color: .blue.opacity(0.55), in: &context, size: size, maximum: maximum)
            }
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func draw(_ bins: [Int], color: Color, in context: inout GraphicsContext, size: CGSize, maximum: Int) {
        guard bins.count == Histogram.binCount else { return }
        var path = Path()
        for (index, bin) in bins.enumerated() {
            let x = size.width * CGFloat(index) / CGFloat(Histogram.binCount - 1)
            let y = size.height * (1 - CGFloat(bin) / CGFloat(maximum))
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        context.stroke(path, with: .color(color), lineWidth: 1)
    }
}

private struct HSLPanel: View {
    @ObservedObject var model: EditorViewModel
    @State private var channel: HSLChannel = .red

    var body: some View {
        ScrollView {
            if model.usesHDRPreview {
                ContentUnavailableView(
                    "HDR 暂不支持 HSL",
                    systemImage: "exclamationmark.triangle",
                    description: Text("当前 HSL 算法只适用于 SDR 0…1 范围。为保留 HDR 高光，已禁用而非静默裁切。")
                )
                .padding()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Color Mixer").font(.headline)
                        Spacer()
                        Button("重置 \(channel.title)") { model.resetHSL(channel) }
                        Button("重置全部") { model.resetAllHSL() }
                    }
                    Picker("颜色", selection: $channel) {
                        ForEach(HSLChannel.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    hslSlider("色相", keyPath: \.hue)
                    hslSlider("饱和度", keyPath: \.saturation)
                    hslSlider("明度", keyPath: \.luminance)
                    Text("所有参数均保存在 EditState；色相选择以软边界覆盖相邻颜色。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding()
            }
        }
    }

    private func hslSlider(_ title: String, keyPath: WritableKeyPath<HSLChannelAdjustment, Double>) -> some View {
        let value = Binding<Double>(
            get: { model.state.hsl[channel][keyPath: keyPath] },
            set: { newValue in
                model.updateContinuous { state in
                    var adjustment = state.hsl[channel]
                    adjustment[keyPath: keyPath] = newValue
                    state.hsl[channel] = adjustment
                }
            }
        )
        return VStack(spacing: 2) {
            HStack { Text(title); Spacer(); Text("\(value.wrappedValue, format: .number.precision(.fractionLength(0)))").foregroundStyle(.secondary).monospacedDigit() }
            Slider(value: value, in: -100...100, onEditingChanged: { editing in
                if editing { model.beginContinuousEdit() } else { model.endContinuousEdit() }
            })
        }
    }
}

private struct RAWPanel: View {
    @ObservedObject var model: EditorViewModel

    var body: some View {
        ScrollView {
            if let metadata = model.asset?.cameraMetadata, model.state.raw != nil {
                VStack(alignment: .leading, spacing: 10) {
                    Text("RAW Decode").font(.headline)
                    MetadataGrid(metadata: metadata)
                    rawExposureSlider("RAW 曝光", range: -5...5)
                    rawSlider("RAW 色温增量", keyPath: \.temperature, range: -100...100)
                    rawSlider("RAW 色调增量", keyPath: \.tint, range: -100...100)
                    rawSlider("明度降噪", keyPath: \.luminanceNoiseReduction, range: 0...1)
                    rawSlider("色彩降噪", keyPath: \.colorNoiseReduction, range: 0...1)
                    rawSlider("RAW 锐化", keyPath: \.sharpness, range: 0...1)
                    rawSlider("细节", keyPath: \.detail, range: 0...3)
                    rawSlider("局部色调", keyPath: \.localTone, range: 0...1)
                    Toggle("镜头校正", isOn: Binding(get: { model.state.raw?.lensCorrectionEnabled ?? true }, set: { value in model.update { $0.raw?.lensCorrectionEnabled = value } }))
                    Text("零色温/色调增量保留相机 as-shot 白平衡。降噪、锐化、细节、局部色调和镜头校正在未触碰时保留 CIRAWFilter decoder 默认值；滑杆显示 0、开关显示开启仅为可编辑 UI 初始值。Preview 先使用 draft decode；导出重新以全分辨率 RAW decode。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding()
            } else {
                ContentUnavailableView("当前不是 RAW 照片", systemImage: "camera.aperture", description: Text("从文件导入 DNG 或 Sony ARW 后可使用 RAW 调整。"))
            }
        }
    }

    private func rawExposureSlider(_ title: String, range: ClosedRange<Double>) -> some View {
        rawSliderControl(
            title,
            value: Binding(
                get: { model.state.raw?.exposure ?? 0 },
                set: { newValue in model.updateContinuous { $0.raw?.exposure = newValue } }
            ),
            range: range
        )
    }

    private func rawSlider(_ title: String, keyPath: WritableKeyPath<RAWAdjustments, Double?>, range: ClosedRange<Double>) -> some View {
        rawSliderControl(
            title,
            value: Binding(
                get: { model.state.raw?[keyPath: keyPath] ?? 0 },
                set: { newValue in model.updateContinuous { $0.raw?[keyPath: keyPath] = newValue } }
            ),
            range: range
        )
    }

    private func rawSlider(_ title: String, keyPath: WritableKeyPath<RAWAdjustments, Double>, range: ClosedRange<Double>) -> some View {
        rawSliderControl(
            title,
            value: Binding(
                get: { model.state.raw?[keyPath: keyPath] ?? 0 },
                set: { newValue in model.updateContinuous { $0.raw?[keyPath: keyPath] = newValue } }
            ),
            range: range
        )
    }

    private func rawSliderControl(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        return VStack(spacing: 2) {
            HStack { Text(title); Spacer(); Text("\(value.wrappedValue, format: .number.precision(.fractionLength(2)))").foregroundStyle(.secondary).monospacedDigit() }
            Slider(value: value, in: range, onEditingChanged: { editing in if editing { model.beginContinuousEdit() } else { model.endContinuousEdit() } })
        }
    }
}

private struct MetadataGrid: View {
    let metadata: CameraMetadata

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
            row("相机", metadata.camera)
            row("镜头", metadata.lens)
            row("光圈", metadata.aperture.map { String(format: "f/%.1f", $0) })
            row("快门", metadata.shutterSeconds.map { String(format: "%.4f s", $0) })
            row("ISO", metadata.iso.map { String(format: "%.0f", $0) })
            row("焦距", metadata.focalLength.map { String(format: "%.0f mm", $0) })
        }
        .font(.caption)
    }

    @ViewBuilder private func row(_ label: String, _ value: String?) -> some View {
        if let value { GridRow { Text(label).foregroundStyle(.secondary); Text(value) } }
    }
}

private struct ToneCurvePanel: View {
    @ObservedObject var model: EditorViewModel
    @State private var channel: ToneCurveChannel = .master

    private var curve: ToneCurve { model.state.curves[channel] }

    var body: some View {
        if model.usesHDRPreview {
            ContentUnavailableView(
                "HDR 暂不支持曲线",
                systemImage: "exclamationmark.triangle",
                description: Text("当前 64³ Color Cube 曲线只适用于 SDR 0…1 范围。为保留 HDR 高光，已禁用而非静默裁切。")
            )
            .padding()
        } else {
            VStack(spacing: 10) {
            HStack {
                Picker("通道", selection: $channel) {
                    ForEach(ToneCurveChannel.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Button("重置全部") { model.resetCurves() }
            }
            .padding(.horizontal)

            GeometryReader { geometry in
                let size = geometry.size
                ZStack {
                    CurveGrid()
                    CurvePath(points: curve.points)
                        .stroke(channelColor, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                    ForEach(curve.points) { point in
                        Circle()
                            .fill(.white)
                            .overlay(Circle().stroke(channelColor, lineWidth: 2))
                            .frame(width: 16, height: 16)
                            .position(x: size.width * point.x, y: size.height * (1 - point.y))
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        model.beginContinuousEdit()
                                        model.moveCurvePoint(
                                            channel: channel,
                                            id: point.id,
                                            x: Double(value.location.x / size.width),
                                            y: Double(1 - value.location.y / size.height)
                                        )
                                    }
                                    .onEnded { _ in model.endContinuousEdit() }
                            )
                            .onLongPressGesture {
                                model.removeCurvePoint(channel: channel, id: point.id)
                            }
                    }
                }
                .contentShape(Rectangle())
            }
            .frame(height: 140)
            .padding(.horizontal)

            HStack {
                Button("添加控制点", systemImage: "plus") {
                    let largestGap = zip(curve.points, curve.points.dropFirst()).max { ($0.1.x - $0.0.x) < ($1.1.x - $1.0.x) }
                    if let gap = largestGap {
                        let x = (gap.0.x + gap.1.x) / 2
                        model.addCurvePoint(channel: channel, x: x, y: curve.value(at: x))
                    }
                }
                Text("拖动调整；长按中间点删除。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding([.horizontal, .bottom])
            }
        }
    }

    private var channelColor: Color {
        switch channel {
        case .master: .primary
        case .red: .red
        case .green: .green
        case .blue: .blue
        }
    }
}

private struct CurveGrid: View {
    var body: some View {
        Canvas { context, size in
            for index in 0 ... 4 {
                let point = CGFloat(index) / 4
                var vertical = Path(); vertical.move(to: CGPoint(x: size.width * point, y: 0)); vertical.addLine(to: CGPoint(x: size.width * point, y: size.height))
                var horizontal = Path(); horizontal.move(to: CGPoint(x: 0, y: size.height * point)); horizontal.addLine(to: CGPoint(x: size.width, y: size.height * point))
                context.stroke(vertical, with: .color(.secondary.opacity(0.2)), lineWidth: 1)
                context.stroke(horizontal, with: .color(.secondary.opacity(0.2)), lineWidth: 1)
            }
        }
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct CurvePath: Shape {
    let points: [CurvePoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: rect.width * first.x, y: rect.height * (1 - first.y)))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: rect.width * point.x, y: rect.height * (1 - point.y)))
        }
        return path
    }
}

private struct PresetPanel: View {
    @ObservedObject var model: EditorViewModel
    @Binding var showingImporter: Bool
    let exportPreset: (UUID, String) -> Void
    @State private var showingCreator = false
    @State private var renaming: Preset?
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 8) {
            if model.usesHDRPreview {
                Text("HDR 照片的 LUT 已暂时禁用：当前 Color Cube 不能保证保留 >1 的高光 headroom。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            HStack {
                Button("新建预设", systemImage: "plus") { showingCreator = true }
                Button("导入", systemImage: "square.and.arrow.down") { showingImporter = true }
                Spacer()
                Text("\(model.presetRepository.presets.count) 个预设").font(.caption).foregroundStyle(.secondary)
            }
            .padding([.horizontal, .top])
            if model.presetRepository.presets.isEmpty {
                ContentUnavailableView("尚无预设", systemImage: "slider.horizontal.3", description: Text("从当前调整创建一个可复用预设。"))
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.presetRepository.presets) { preset in
                            Button { model.applyPreset(id: preset.id) } label: {
                                HStack {
                                    Image(systemName: preset.isFavorite ? "star.fill" : "slider.horizontal.3")
                                        .foregroundStyle(preset.isFavorite ? .yellow : .secondary)
                                    Text(preset.name).foregroundStyle(.primary)
                                    Spacer()
                                    Text(preset.payload.transform == nil ? "不含裁切" : "含裁切").font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .contextMenu {
                                Button(preset.isFavorite ? "取消收藏" : "收藏", systemImage: preset.isFavorite ? "star.slash" : "star") { try? model.presetRepository.toggleFavorite(id: preset.id) }
                                Button("重命名", systemImage: "pencil") { renaming = preset; renameText = preset.name }
                                Button("导出 JSON", systemImage: "square.and.arrow.up") { exportPreset(preset.id, preset.name) }
                                Button("删除", systemImage: "trash", role: .destructive) { try? model.presetRepository.delete(id: preset.id) }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .sheet(isPresented: $showingCreator) { PresetCreatorView(model: model) }
        .alert("重命名预设", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("名称", text: $renameText)
            Button("取消", role: .cancel) { renaming = nil }
            Button("保存") {
                if let preset = renaming { try? model.presetRepository.rename(id: preset.id, to: renameText) }
                renaming = nil
            }
        }
    }
}

private struct PresetCreatorView: View {
    @ObservedObject var model: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var includesTransform = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("预设名称", text: $name)
                Toggle("包含裁切、旋转与翻转", isOn: $includesTransform)
                Text("默认保存光线、颜色、HSL、曲线、LUT、细节和效果。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .navigationTitle("新建预设")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { model.createPreset(name: name, includesTransform: includesTransform); dismiss() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct SelectivePasteView: View {
    @ObservedObject var model: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var groups = Set(AdjustmentGroup.allCases)

    var body: some View {
        NavigationStack {
            List {
                ForEach(AdjustmentGroup.allCases) { group in
                    Toggle(group.title, isOn: Binding(
                        get: { groups.contains(group) },
                        set: { enabled in if enabled { groups.insert(group) } else { groups.remove(group) } }
                    ))
                }
            }
            .navigationTitle("选择性粘贴")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("粘贴") { model.pasteAdjustments(groups: groups); dismiss() }
                }
            }
        }
    }
}

private struct LUTPanel: View {
    @ObservedObject var model: EditorViewModel
    @Binding var showingImporter: Bool
    @State private var section: LUTLibrarySection = .all
    @State private var renameItem: LUTCatalogItem?
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("LUT 分类", selection: $section) {
                    ForEach(LUTLibrarySection.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                Spacer()
                Button { showingImporter = true } label: { Label("导入 LUT", systemImage: "plus") }
            }
            .padding([.horizontal, .top])

            HStack {
                Text("强度")
                Slider(value: Binding(
                    get: { model.state.lut.intensity * 100 },
                    set: { value in model.updateContinuous { $0.lut.intensity = value / 100 } }
                ), in: 0...100, onEditingChanged: { editing in
                    if editing { model.beginContinuousEdit() } else { model.endContinuousEdit() }
                })
                Text("\(Int((model.state.lut.intensity * 100).rounded()))%")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .disabled(model.usesHDRPreview || model.state.lut.selectedLUTID == nil)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    LUTCard(name: "无 Creative LUT", subtitle: nil, image: nil, selected: model.state.lut.selectedLUTID == nil)
                        .onTapGesture { model.selectLUT(nil) }
                    ForEach(creativeItems) { item in
                        LUTCard(name: item.name, subtitle: item.colorMetadata.summary, image: model.thumbnail(for: item.id), selected: item.id == model.state.lut.selectedLUTID)
                            .onTapGesture { model.selectLUT(item.id) }
                            .contextMenu {
                                Button(item.isFavorite ? "取消收藏" : "收藏", systemImage: item.isFavorite ? "star.slash" : "star") {
                                    try? model.lutRepository.toggleFavorite(id: item.id)
                                }
                                colorConfigurationMenu(for: item)
                                if item.source == .imported {
                                    Button("重命名", systemImage: "pencil") {
                                        renameItem = item
                                        renameText = item.name
                                    }
                                    Button("删除", systemImage: "trash", role: .destructive) {
                                        if model.state.lut.selectedLUTID == item.id { model.selectLUT(nil) }
                                        if model.state.lut.technicalLUTID == item.id { model.selectTechnicalLUT(nil) }
                                        try? model.lutRepository.delete(id: item.id)
                                    }
                                }
                            }
                    }
                }
                .padding(.horizontal)
            }
            .disabled(model.usesHDRPreview)
            if technicalItems.isEmpty {
                Text("Technical LUT 会先完成 Log/HLG 等输入到工作空间的变换，且不参与强度混合。")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            } else {
                Picker("Technical Transform", selection: Binding(
                    get: { model.state.lut.technicalLUTID },
                    set: { model.selectTechnicalLUT($0) }
                )) {
                    Text("无 Technical LUT").tag(UUID?.none)
                    ForEach(technicalItems) { item in
                        Text("\(item.name)（\(item.colorMetadata.summary)）").tag(Optional(item.id))
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal)
                .disabled(model.usesHDRPreview)
                if let item = technicalItems.first(where: { $0.id == model.state.lut.technicalLUTID }) {
                    Menu("配置 \(item.name)") { colorConfigurationMenu(for: item) }
                        .padding(.horizontal)
                }
            }
        }
        .alert("重命名 LUT", isPresented: Binding(
            get: { renameItem != nil }, set: { if !$0 { renameItem = nil } }
        )) {
            TextField("名称", text: $renameText)
            Button("取消", role: .cancel) { renameItem = nil }
            Button("保存") {
                if let item = renameItem { try? model.lutRepository.rename(id: item.id, to: renameText) }
                renameItem = nil
            }
        }
    }

    private var creativeItems: [LUTCatalogItem] {
        model.lutRepository.visibleItems(in: section).filter { $0.kind == .creative }
    }

    private var technicalItems: [LUTCatalogItem] {
        model.lutRepository.items.filter { $0.kind == .technical }
    }

    @ViewBuilder
    private func colorConfigurationMenu(for item: LUTCatalogItem) -> some View {
        Menu("LUT 类型") {
            ForEach(LUTKind.allCases) { kind in
                Button(kind.title) { model.configureLUT(id: item.id, kind: kind, colorMetadata: item.colorMetadata) }
            }
        }
        Menu("色彩空间") {
            Button("未指定（安全地禁用套用）") {
                model.configureLUT(id: item.id, kind: item.kind, colorMetadata: .unspecified)
            }
            Button("sRGB → sRGB") {
                model.configureLUT(id: item.id, kind: item.kind, colorMetadata: .sRGB)
            }
            Button("Rec.709 → sRGB") {
                model.configureLUT(id: item.id, kind: item.kind, colorMetadata: LUTColorMetadata(inputColorSpace: .rec709, outputColorSpace: .sRGB))
            }
            Button("Rec.709 HLG → Rec.709") {
                model.configureLUT(id: item.id, kind: item.kind, colorMetadata: LUTColorMetadata(inputColorSpace: .rec709HLG, outputColorSpace: .rec709))
            }
            Button("Display P3 → sRGB") {
                model.configureLUT(id: item.id, kind: item.kind, colorMetadata: LUTColorMetadata(inputColorSpace: .displayP3, outputColorSpace: .sRGB))
            }
        }
    }
}

private struct LUTCard: View {
    let name: String
    let subtitle: String?
    let image: CGImage?
    let selected: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                if let image {
                    Image(decorative: image, scale: 1).resizable().scaledToFill().clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "nosign").foregroundStyle(.secondary)
                }
            }
            .frame(width: 92, height: 76)
            Text(name).font(.caption).lineLimit(1).frame(width: 92)
            if let subtitle {
                Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center).frame(width: 92)
            }
        }
        .padding(4)
        .background(selected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct BatchPanel: View {
    @ObservedObject var model: EditorViewModel
    @Binding var showingImporter: Bool
    @Binding var showingReferenceImporter: Bool
    @Binding var showingExportOptions: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button("选择多张照片", systemImage: "photo.stack") { showingImporter = true }
                    Spacer()
                    Text("\(model.batchPhotos.count) 张")
                        .foregroundStyle(.secondary)
                    if !model.batchPhotos.isEmpty {
                        Button("清空", role: .destructive) { model.clearBatchPhotos() }
                            .disabled(model.isBatchExporting)
                    }
                }

                GroupBox("批量调整：\(model.batchAdjustmentSource)") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button("使用当前调整") { model.applyCurrentAdjustmentsToBatch() }
                            Button("使用已复制调整") {
                                if !model.applyCopiedAdjustmentsToBatch() {
                                    model.errorMessage = "请先在编辑器中复制调整。"
                                }
                            }
                            .disabled(!model.adjustmentClipboard.hasAdjustments)
                        }
                        Menu("套用预设") {
                            ForEach(model.presetRepository.presets) { preset in
                                Button(preset.name) { model.applyPresetToBatch(id: preset.id) }
                            }
                        }
                        .disabled(model.presetRepository.presets.isEmpty)
                        Menu("套用 LUT") {
                            Button("不使用 LUT") { model.applyLUTToBatch(id: nil) }
                            ForEach(model.lutRepository.items) { item in
                                Button(item.name) { model.applyLUTToBatch(id: item.id) }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !model.recentSettings.lutIDs.isEmpty || !model.recentSettings.presetIDs.isEmpty {
                    Menu("最近使用") {
                        ForEach(model.recentSettings.presetIDs, id: \.self) { id in
                            if let preset = model.presetRepository.preset(id: id) {
                                Button("预设：\(preset.name)") { model.applyPresetToBatch(id: id) }
                            }
                        }
                        ForEach(model.recentSettings.lutIDs, id: \.self) { id in
                            if let lut = model.lutRepository.items.first(where: { $0.id == id }) {
                                Button("LUT：\(lut.name)") { model.applyLUTToBatch(id: id) }
                            }
                        }
                    }
                }

                GroupBox("参考照片") {
                    HStack {
                        Button("载入参考照片", systemImage: "rectangle.split.2x1") { showingReferenceImporter = true }
                        Toggle("左右对照", isOn: $model.isShowingReference)
                            .disabled(model.referencePreviewImage == nil)
                    }
                }

                if model.isBatchExporting {
                    ProgressView(value: Double(model.batchProgress.completed), total: Double(max(1, model.batchProgress.total))) {
                        Text("正在导出 \(model.batchProgress.completed) / \(model.batchProgress.total)")
                    }
                    Button("取消批量导出", role: .destructive) { model.cancelBatchExport() }
                } else {
                    Button("开始批量导出", systemImage: "square.and.arrow.up") { showingExportOptions = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.batchPhotos.isEmpty)
                }

                if !model.batchPhotos.isEmpty {
                    ForEach(model.batchPhotos) { photo in
                        Text(photo.sourceName).font(.caption).lineLimit(1)
                    }
                }
                if !model.batchResults.isEmpty {
                    Text("结果").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(Array(model.batchResults.enumerated()), id: \.offset) { _, result in
                        Text(result.title).font(.caption)
                    }
                    if !model.batchOutputURLs.isEmpty {
                        ShareLink(items: model.batchOutputURLs) {
                            Label("分享或存储已导出的文件", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .padding()
        }
    }
}

private extension BatchItemResult {
    var title: String {
        switch self {
        case let .succeeded(_, output): "已完成：\(output.filename)"
        case let .failed(_, message): "失败：\(message)"
        case .cancelled: "已取消"
        }
    }
}

private struct LocalAdjustmentsPanel: View {
    @ObservedObject var model: EditorViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Menu("添加蒙版", systemImage: "plus") {
                        Button("线性渐变", systemImage: "line.diagonal") { model.addLocalAdjustment(mask: .linear(LinearGradientMask())) }
                        Button("径向渐变", systemImage: "circle.dashed") { model.addLocalAdjustment(mask: .radial(RadialGradientMask())) }
                        Button("画笔", systemImage: "paintbrush") { model.addLocalAdjustment(mask: .brush(BrushMask())) }
                    }
                    Spacer()
                    if let selected = model.selectedLocalAdjustment {
                        Button("删除", systemImage: "trash", role: .destructive) { model.deleteLocalAdjustment(id: selected.id) }
                    }
                }

                if model.state.localAdjustments.isEmpty {
                    ContentUnavailableView("尚未添加局部调整", systemImage: "circle.dashed", description: Text("使用线性、径向渐变或画笔，局部套用曝光、对比度和饱和度。"))
                } else {
                    Picker("局部区域", selection: $model.selectedLocalAdjustmentID) {
                        ForEach(model.state.localAdjustments) { adjustment in
                            Text("\(adjustment.name) · \(adjustment.mask.title)").tag(Optional(adjustment.id))
                        }
                    }
                    .pickerStyle(.menu)

                    if let selected = model.selectedLocalAdjustment {
                        Toggle("启用此局部调整", isOn: binding(for: selected.id, keyPath: \.isEnabled))
                        maskControls(for: selected)
                        Divider()
                        adjustmentSlider("曝光", value: adjustmentBinding(for: selected.id, keyPath: \.exposure), range: -5...5)
                        adjustmentSlider("对比度", value: adjustmentBinding(for: selected.id, keyPath: \.contrast), range: -100...100)
                        adjustmentSlider("饱和度", value: adjustmentBinding(for: selected.id, keyPath: \.saturation), range: -100...100)
                    }
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func maskControls(for adjustment: LocalAdjustment) -> some View {
        switch adjustment.mask {
        case .linear:
            GroupBox("线性渐变（白色一端为作用区域）") {
                VStack(spacing: 6) {
                    maskSlider("起点 X", value: linearBinding(for: adjustment.id, keyPath: \.start.x))
                    maskSlider("起点 Y", value: linearBinding(for: adjustment.id, keyPath: \.start.y))
                    maskSlider("终点 X", value: linearBinding(for: adjustment.id, keyPath: \.end.x))
                    maskSlider("终点 Y", value: linearBinding(for: adjustment.id, keyPath: \.end.y))
                }
            }
        case .radial:
            GroupBox("径向渐变") {
                VStack(spacing: 6) {
                    maskSlider("中心 X", value: radialPointBinding(for: adjustment.id, keyPath: \.center.x))
                    maskSlider("中心 Y", value: radialPointBinding(for: adjustment.id, keyPath: \.center.y))
                    maskSlider("半径", value: radialBinding(for: adjustment.id, keyPath: \.radius))
                    maskSlider("羽化", value: radialBinding(for: adjustment.id, keyPath: \.feather))
                }
            }
        case let .brush(brush):
            GroupBox("画笔蒙版") {
                VStack(spacing: 8) {
                    BrushMaskCanvas(
                        points: brush.points,
                        size: brush.size,
                        begin: model.beginLocalBrushStroke,
                        append: { point in model.appendBrushPoint(point, to: adjustment.id) },
                        end: model.endLocalBrushStroke
                    )
                    maskSlider("画笔大小", value: brushBinding(for: adjustment.id, keyPath: \.size))
                    maskSlider("硬度", value: brushBinding(for: adjustment.id, keyPath: \.hardness))
                    Button("清除笔触", systemImage: "eraser") {
                        model.updateLocalAdjustment(id: adjustment.id) {
                            guard case var .brush(mask) = $0.mask else { return }
                            mask.points.removeAll()
                            $0.mask = .brush(mask)
                        }
                    }
                    .disabled(brush.points.isEmpty)
                }
            }
        }
    }

    private func adjustmentSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(spacing: 2) {
            HStack { Text(title); Spacer(); Text(value.wrappedValue, format: .number.precision(.fractionLength(0))).foregroundStyle(.secondary).monospacedDigit() }
            Slider(value: value, in: range)
        }
    }

    private func maskSlider(_ title: String, value: Binding<Double>) -> some View {
        VStack(spacing: 2) {
            HStack { Text(title); Spacer(); Text(value.wrappedValue, format: .number.precision(.fractionLength(2))).foregroundStyle(.secondary).monospacedDigit() }
            Slider(value: value, in: 0...1)
        }
    }

    private func binding(for id: UUID, keyPath: WritableKeyPath<LocalAdjustment, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.state.localAdjustments.first(where: { $0.id == id })?[keyPath: keyPath] ?? false },
            set: { value in model.updateLocalAdjustment(id: id) { $0[keyPath: keyPath] = value } }
        )
    }

    private func adjustmentBinding(for id: UUID, keyPath: WritableKeyPath<LocalAdjustmentValues, Double>) -> Binding<Double> {
        Binding(
            get: { model.state.localAdjustments.first(where: { $0.id == id })?.adjustments[keyPath: keyPath] ?? 0 },
            set: { value in model.updateLocalAdjustment(id: id) { $0.adjustments[keyPath: keyPath] = value } }
        )
    }

    private func linearBinding(for id: UUID, keyPath: WritableKeyPath<LinearGradientMask, Double>) -> Binding<Double> {
        Binding(
            get: {
                guard let adjustment = model.state.localAdjustments.first(where: { $0.id == id }), case let .linear(mask) = adjustment.mask else { return 0 }
                return mask[keyPath: keyPath]
            },
            set: { value in
                model.updateLocalAdjustment(id: id) {
                    guard case var .linear(mask) = $0.mask else { return }
                    mask[keyPath: keyPath] = value.clamped(to: 0...1)
                    $0.mask = .linear(mask)
                }
            }
        )
    }

    private func radialPointBinding(for id: UUID, keyPath: WritableKeyPath<RadialGradientMask, Double>) -> Binding<Double> {
        Binding(
            get: {
                guard let adjustment = model.state.localAdjustments.first(where: { $0.id == id }), case let .radial(mask) = adjustment.mask else { return 0 }
                return mask[keyPath: keyPath]
            },
            set: { value in
                model.updateLocalAdjustment(id: id) {
                    guard case var .radial(mask) = $0.mask else { return }
                    mask[keyPath: keyPath] = value.clamped(to: 0...1)
                    $0.mask = .radial(mask)
                }
            }
        )
    }

    private func radialBinding(for id: UUID, keyPath: WritableKeyPath<RadialGradientMask, Double>) -> Binding<Double> {
        Binding(
            get: {
                guard let adjustment = model.state.localAdjustments.first(where: { $0.id == id }), case let .radial(mask) = adjustment.mask else { return 0 }
                return mask[keyPath: keyPath]
            },
            set: { value in
                model.updateLocalAdjustment(id: id) {
                    guard case var .radial(mask) = $0.mask else { return }
                    mask[keyPath: keyPath] = value.clamped(to: 0...1)
                    $0.mask = .radial(mask)
                }
            }
        )
    }

    private func brushBinding(for id: UUID, keyPath: WritableKeyPath<BrushMask, Double>) -> Binding<Double> {
        Binding(
            get: {
                guard let adjustment = model.state.localAdjustments.first(where: { $0.id == id }), case let .brush(mask) = adjustment.mask else { return 0 }
                return mask[keyPath: keyPath]
            },
            set: { value in
                model.updateLocalAdjustment(id: id) {
                    guard case var .brush(mask) = $0.mask else { return }
                    mask[keyPath: keyPath] = value.clamped(to: 0...1)
                    $0.mask = .brush(mask)
                }
            }
        )
    }
}

private struct BrushMaskCanvas: View {
    let points: [NormalizedPoint]
    let size: Double
    let begin: () -> Void
    let append: (NormalizedPoint) -> Void
    let end: () -> Void
    @State private var isDrawing = false

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, canvasSize in
                context.fill(Path(CGRect(origin: .zero, size: canvasSize)), with: .color(.black.opacity(0.75)))
                let radius = max(3, min(canvasSize.width, canvasSize.height) * size / 2)
                for point in points {
                    let center = CGPoint(x: canvasSize.width * point.x, y: canvasSize.height * (1 - point.y))
                    context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .color(.white.opacity(0.85)))
                }
            }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard geometry.size.width > 0, geometry.size.height > 0 else { return }
                    if !isDrawing { isDrawing = true; begin() }
                    append(NormalizedPoint(x: value.location.x / geometry.size.width, y: 1 - value.location.y / geometry.size.height))
                }
                .onEnded { _ in
                    guard isDrawing else { return }
                    isDrawing = false
                    end()
                }
            )
        }
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("画笔蒙版画布")
        .accessibilityHint("在此拖动可添加局部调整笔触")
    }
}

private struct CropPanel: View {
    @ObservedObject var model: EditorViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Picker("比例", selection: Binding(
                    get: { model.state.transform.crop.aspectRatio },
                    set: { value in model.update { $0.transform.crop.aspectRatio = value } }
                )) {
                    ForEach(CropAspectRatio.allCases) { ratio in Text(ratio.title).tag(ratio) }
                }
                .pickerStyle(.segmented)

                cropSlider("缩放", value: Binding(
                    get: { min(model.state.transform.crop.normalizedRect.width, model.state.transform.crop.normalizedRect.height) },
                    set: { value in model.updateContinuous { state in
                        let old = state.transform.crop.normalizedRect
                        state.transform.crop.normalizedRect = NormalizedRect(
                            x: (old.x + old.width / 2 - value / 2).clamped(to: 0...(1 - value)),
                            y: (old.y + old.height / 2 - value / 2).clamped(to: 0...(1 - value)),
                            width: value,
                            height: value
                        )
                    } }
                ), range: 0.1...1)
                cropSlider("水平位置", value: cropComponent(\.x), range: 0...0.98)
                cropSlider("垂直位置", value: cropComponent(\.y), range: 0...0.98)

                HStack {
                    Button { model.update { $0.transform.rotateClockwise() } } label: { Label("旋转 90°", systemImage: "rotate.right") }
                    Button { model.update { $0.transform.horizontalFlip.toggle() } } label: { Label("水平翻转", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") }
                    Spacer()
                    Button("还原") { model.update { $0.transform.reset() } }
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
    }

    private func cropSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(spacing: 2) {
            HStack { Text(title); Spacer(); Text("\(value.wrappedValue, format: .number.precision(.fractionLength(2)))").foregroundStyle(.secondary).monospacedDigit() }
            Slider(value: value, in: range, onEditingChanged: { editing in
                if editing { model.beginContinuousEdit() } else { model.endContinuousEdit() }
            })
        }
    }

    private func cropComponent(_ keyPath: WritableKeyPath<NormalizedRect, Double>) -> Binding<Double> {
        Binding(get: { model.state.transform.crop.normalizedRect[keyPath: keyPath] }, set: { value in
            model.updateContinuous { state in
                state.transform.crop.normalizedRect[keyPath: keyPath] = value
                state.transform.crop.normalizedRect = state.transform.crop.normalizedRect.clamped()
            }
        })
    }
}

private struct ExportOptionsView: View {
    @ObservedObject var model: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var settings = ExportSettings()

    var body: some View {
        NavigationStack {
            Form {
                Section("格式") {
                    Picker("文件格式", selection: $settings.format) {
                        ForEach(ExportFormat.allCases) { Text($0.title).tag($0) }
                    }
                    .disabled(settings.dynamicRange == .hdr)
                    Picker("动态范围", selection: Binding(
                        get: { settings.dynamicRange },
                        set: { range in
                            settings.dynamicRange = range
                            if range == .hdr { settings.format = .heif }
                        }
                    )) {
                        ForEach(ExportDynamicRange.allCases) { Text($0.title).tag($0) }
                    }
                    if settings.dynamicRange == .hdr {
                        Text("HDR 仅适用于真实 HDR 源，并导出为 10-bit HEIF。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Picker("尺寸", selection: Binding(
                        get: { settings.maximumDimension ?? 0 },
                        set: { settings.maximumDimension = $0 == 0 ? nil : $0 }
                    )) {
                        Text("原始分辨率").tag(0)
                        Text("4096 px").tag(4096)
                        Text("2048 px").tag(2048)
                    }
                }
                if settings.format == .jpeg {
                    Section("JPEG 质量") {
                        Picker("质量", selection: $settings.jpegQuality) {
                            Text("80%").tag(0.8)
                            Text("90%").tag(0.9)
                            Text("100%").tag(1.0)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Section("文件名") {
                    Picker("命名方式", selection: $settings.filenameStrategy) {
                        ForEach(ExportFilenameStrategy.allCases) { Text($0.title).tag($0) }
                    }
                    if settings.filenameStrategy == .sequential {
                        TextField("编号前缀", text: $settings.filenamePrefix)
                    }
                }
                Section("隐私") { Toggle("保留位置", isOn: $settings.keepLocation) }
                if model.isExporting { ProgressView("正在按原始管线导出") }
            }
            .navigationTitle("导出")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("生成") {
                        model.export(settings: settings)
                        dismiss()
                    }
                    .disabled(model.isExporting)
                }
            }
        }
    }
}

private struct BatchExportOptionsView: View {
    @ObservedObject var model: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var settings = ExportSettings()

    var body: some View {
        NavigationStack {
            Form {
                Section("格式与尺寸") {
                    Picker("文件格式", selection: $settings.format) {
                        ForEach(ExportFormat.allCases) { Text($0.title).tag($0) }
                    }
                    .disabled(settings.dynamicRange == .hdr)
                    Picker("动态范围", selection: Binding(
                        get: { settings.dynamicRange },
                        set: { range in
                            settings.dynamicRange = range
                            if range == .hdr { settings.format = .heif }
                        }
                    )) {
                        ForEach(ExportDynamicRange.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("最长边", selection: Binding(
                        get: { settings.maximumDimension ?? 0 },
                        set: { settings.maximumDimension = $0 == 0 ? nil : $0 }
                    )) {
                        Text("原始分辨率").tag(0)
                        Text("4096 px").tag(4096)
                        Text("2048 px").tag(2048)
                    }
                    if settings.format == .jpeg {
                        Picker("JPEG 质量", selection: $settings.jpegQuality) {
                            Text("80%").tag(0.8)
                            Text("90%").tag(0.9)
                            Text("100%").tag(1.0)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Section("文件名") {
                    Picker("命名方式", selection: $settings.filenameStrategy) {
                        ForEach(ExportFilenameStrategy.allCases) { Text($0.title).tag($0) }
                    }
                    if settings.filenameStrategy == .sequential {
                        TextField("编号前缀", text: $settings.filenamePrefix)
                    }
                }
                Section("隐私") { Toggle("保留位置", isOn: $settings.keepLocation) }
                if let recent = model.recentSettings.exportSettings.first {
                    Button("使用最近导出设置") { settings = recent }
                }
            }
            .navigationTitle("批量导出")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("开始") {
                        model.startBatchExport(settings: settings)
                        dismiss()
                    }
                    .disabled(model.batchPhotos.isEmpty || model.isBatchExporting)
                }
            }
        }
    }
}

private struct ExportResultView: View {
    let output: ExportedImage
    let saveToFiles: (ExportedImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section("已生成新文件") {
                    Text(output.filename)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(output.data.count), countStyle: .file)).foregroundStyle(.secondary)
                }
                Section {
                    Button("存到照片", systemImage: "photo.badge.arrow.down") {
                        Task {
                            do {
                                try await PhotoLibrarySaver.save(data: output.data, type: output.type)
                                message = "已保存到照片。"
                            } catch { message = error.localizedDescription }
                        }
                    }
                    ShareLink(item: output.fileURL) { Label("分享", systemImage: "square.and.arrow.up") }
                    Button("存到文件", systemImage: "folder.badge.plus") { saveToFiles(output) }
                }
                if let message { Section { Text(message) } }
            }
            .navigationTitle("导出完成")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
