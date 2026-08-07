import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

private enum EditorTool: String, CaseIterable, Identifiable {
    case adjust = "基本"
    case hsl = "HSL"
    case curves = "曲线"
    case presets = "预设"
    case raw = "RAW"
    case lut = "LUT"
    case crop = "裁切"

    var id: String { rawValue }
}

struct EditorView: View {
    @StateObject private var model = EditorViewModel()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingImageImporter = false
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
    @State private var tool: EditorTool = .adjust
    @State private var zoom: CGFloat = 1
    @State private var pan = CGSize.zero

    var body: some View {
        NavigationStack {
            Group {
                if model.asset == nil {
                    importLanding
                } else {
                    editor
                }
            }
            .navigationTitle(model.asset == nil ? "PhotoEdit" : model.asset?.sourceName ?? "编辑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
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
        .fileImporter(
            isPresented: $showingImageImporter,
            allowedContentTypes: [.jpeg, .heic, .heif, .png, UTType(filenameExtension: "dng") ?? .data, UTType(filenameExtension: "arw") ?? .data]
        ) { result in
            if case let .success(url) = result { model.loadImage(url: url) }
            else if case let .failure(error) = result { model.errorMessage = error.localizedDescription }
        }
        .fileImporter(isPresented: $showingLUTImporter, allowedContentTypes: [UTType(filenameExtension: "cube") ?? .data]) { result in
            if case let .success(url) = result { model.importLUT(url: url) }
            else if case let .failure(error) = result { model.errorMessage = error.localizedDescription }
        }
        .fileImporter(isPresented: $showingPresetImporter, allowedContentTypes: [.json]) { result in
            if case let .success(url) = result { model.importPreset(url: url) }
            else if case let .failure(error) = result { model.errorMessage = error.localizedDescription }
        }
        .sheet(isPresented: $showingExportOptions) {
            ExportOptionsView(model: model)
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
        .alert("发生错误", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "未知错误")
        }
    }

    private var importLanding: some View {
        ContentUnavailableView {
            Label("导入照片开始编辑", systemImage: "photo.on.rectangle")
        } description: {
            Text("支持 JPEG、HEIC/HEIF 与 PNG。原始照片不会被修改。")
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
            }
            .frame(maxWidth: 280)
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack {
                    Color.black
                    if let image = model.isShowingBefore ? model.originalPreviewImage : model.previewImage {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(zoom)
                            .offset(pan)
                            .gesture(imageGesture(in: geometry.size))
                            .accessibilityLabel(model.isShowingBefore ? "原图预览" : "编辑结果预览")
                    } else {
                        ProgressView("正在准备预览")
                            .tint(.white)
                            .foregroundStyle(.white)
                    }
                    if model.isRendering && model.previewImage != nil {
                        ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding()
                    }
                }
                .clipShape(Rectangle())
                .onTapGesture(count: 2) { withAnimation { zoom = 1; pan = .zero } }
            }
            .frame(maxHeight: .infinity)

            Picker("工具", selection: $tool) {
                ForEach(EditorTool.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .padding([.horizontal, .top])

            Group {
                switch tool {
                case .adjust: AdjustmentPanel(model: model)
                case .hsl: HSLPanel(model: model)
                case .curves: ToneCurvePanel(model: model)
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
                case .raw: RAWPanel(model: model)
                case .lut: LUTPanel(model: model, showingImporter: $showingLUTImporter)
                case .crop: CropPanel(model: model)
                }
            }
            .frame(height: 260)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if model.asset != nil {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button {
                    model.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!model.canUndo)
                Button("重置") { model.reset() }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Text("查看原图")
                    .font(.caption)
                    .onLongPressGesture(minimumDuration: 0.05, pressing: { isPressing in
                        model.isShowingBefore = isPressing
                    }, perform: {})
                    .accessibilityHint("按住显示未编辑原图")
                Button {
                    showingExportOptions = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                Menu {
                    Button("复制全部调整", systemImage: "doc.on.doc") { model.copyAllAdjustments() }
                    Button("粘贴全部调整", systemImage: "doc.on.clipboard") {
                        model.pasteAdjustments()
                    }
                    .disabled(!model.adjustmentClipboard.hasAdjustments)
                    Button("选择性粘贴", systemImage: "checklist") {
                        showingSelectivePaste = true
                    }
                    .disabled(!model.adjustmentClipboard.hasAdjustments)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
            }
        }
    }

    private func imageGesture(in _: CGSize) -> some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .onChanged { value in zoom = min(max(value, 1), 5) }
                .onEnded { _ in if zoom < 1.02 { zoom = 1; pan = .zero } },
            DragGesture()
                .onChanged { value in pan = value.translation }
        )
    }
}

private struct AdjustmentPanel: View {
    @ObservedObject var model: EditorViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                adjustmentSection("光线") {
                    slider("曝光", value: light(\.exposure), range: -5...5, suffix: " EV")
                    slider("对比度", value: light(\.contrast), range: -100...100)
                    slider("高光", value: light(\.highlights), range: -100...100)
                    slider("阴影", value: light(\.shadows), range: -100...100)
                }
                adjustmentSection("颜色") {
                    slider("色温", value: color(\.temperature), range: -100...100)
                    slider("色调", value: color(\.tint), range: -100...100)
                    slider("饱和度", value: color(\.saturation), range: -100...100)
                    slider("自然饱和度", value: color(\.vibrance), range: -100...100)
                }
                adjustmentSection("细节与效果") {
                    slider("锐化", value: detail(\.sharpness), range: 0...100)
                    slider("暗角", value: effects(\.vignette), range: -100...100)
                }
                HistogramView(histogram: model.histogram)
                    .frame(height: 64)
                    .accessibilityLabel("RGB 和亮度直方图")
            }
            .padding()
        }
    }

    private func adjustmentSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String = "") -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue, format: .number.precision(.fractionLength(range.upperBound == 5 ? 1 : 0)))\(suffix)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, onEditingChanged: { editing in
                if editing { model.beginContinuousEdit() } else { model.endContinuousEdit() }
            })
        }
    }

    private func light(_ keyPath: WritableKeyPath<LightAdjustments, Double>) -> Binding<Double> {
        Binding(get: { model.state.light[keyPath: keyPath] }, set: { value in
            model.updateContinuous { $0.light[keyPath: keyPath] = value }
        })
    }

    private func color(_ keyPath: WritableKeyPath<ColorAdjustments, Double>) -> Binding<Double> {
        Binding(get: { model.state.color[keyPath: keyPath] }, set: { value in
            model.updateContinuous { $0.color[keyPath: keyPath] = value }
        })
    }

    private func detail(_ keyPath: WritableKeyPath<DetailAdjustments, Double>) -> Binding<Double> {
        Binding(get: { model.state.detail[keyPath: keyPath] }, set: { value in
            model.updateContinuous { $0.detail[keyPath: keyPath] = value }
        })
    }

    private func effects(_ keyPath: WritableKeyPath<EffectAdjustments, Double>) -> Binding<Double> {
        Binding(get: { model.state.effects[keyPath: keyPath] }, set: { value in
            model.updateContinuous { $0.effects[keyPath: keyPath] = value }
        })
    }
}

private struct HistogramView: View {
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
                    rawSlider("RAW 曝光", keyPath: \.exposure, range: -5...5)
                    rawSlider("RAW 色温", keyPath: \.temperature, range: -100...100)
                    rawSlider("RAW 色调", keyPath: \.tint, range: -100...100)
                    rawSlider("明度降噪", keyPath: \.luminanceNoiseReduction, range: 0...1)
                    rawSlider("色彩降噪", keyPath: \.colorNoiseReduction, range: 0...1)
                    rawSlider("RAW 锐化", keyPath: \.sharpness, range: 0...1)
                    rawSlider("细节", keyPath: \.detail, range: 0...3)
                    rawSlider("局部色调", keyPath: \.localTone, range: 0...1)
                    Toggle("镜头校正", isOn: Binding(get: { model.state.raw?.lensCorrectionEnabled ?? false }, set: { value in model.update { $0.raw?.lensCorrectionEnabled = value } }))
                    Text("Preview 先使用 CIRAWFilter draft decode；导出重新以全分辨率 RAW decode。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding()
            } else {
                ContentUnavailableView("当前不是 RAW 照片", systemImage: "camera.aperture", description: Text("从文件导入 DNG 或 Sony ARW 后可使用 RAW 调整。"))
            }
        }
    }

    private func rawSlider(_ title: String, keyPath: WritableKeyPath<RAWAdjustments, Double>, range: ClosedRange<Double>) -> some View {
        let value = Binding<Double>(get: { model.state.raw?[keyPath: keyPath] ?? 0 }, set: { newValue in model.updateContinuous { $0.raw?[keyPath: keyPath] = newValue } })
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
            .disabled(model.state.lut.selectedLUTID == nil)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    LUTCard(name: "无", image: nil, selected: model.state.lut.selectedLUTID == nil)
                        .onTapGesture { model.selectLUT(nil) }
                    ForEach(model.lutRepository.visibleItems(in: section)) { item in
                        LUTCard(name: item.name, image: model.thumbnail(for: item.id), selected: item.id == model.state.lut.selectedLUTID)
                            .onTapGesture { model.selectLUT(item.id) }
                            .contextMenu {
                                Button(item.isFavorite ? "取消收藏" : "收藏", systemImage: item.isFavorite ? "star.slash" : "star") {
                                    try? model.lutRepository.toggleFavorite(id: item.id)
                                }
                                if item.source == .imported {
                                    Button("重命名", systemImage: "pencil") {
                                        renameItem = item
                                        renameText = item.name
                                    }
                                    Button("删除", systemImage: "trash", role: .destructive) {
                                        if model.state.lut.selectedLUTID == item.id { model.selectLUT(nil) }
                                        try? model.lutRepository.delete(id: item.id)
                                    }
                                }
                            }
                    }
                }
                .padding(.horizontal)
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
}

private struct LUTCard: View {
    let name: String
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
        }
        .padding(4)
        .background(selected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 10))
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
