import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

private enum EditorTool: String, CaseIterable, Identifiable {
    case adjust = "调整"
    case lut = "LUT"
    case crop = "裁切"

    var id: String { rawValue }
}

struct EditorView: View {
    @StateObject private var model = EditorViewModel()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingImageImporter = false
    @State private var showingLUTImporter = false
    @State private var showingExportOptions = false
    @State private var showingFileExporter = false
    @State private var exportDocument = ImageExportDocument()
    @State private var exportType: UTType = .jpeg
    @State private var exportFilename = "Photo-edited.jpg"
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
            allowedContentTypes: [.jpeg, .heic, .heif, .png]
        ) { result in
            if case let .success(url) = result { model.loadImage(url: url) }
            else if case let .failure(error) = result { model.errorMessage = error.localizedDescription }
        }
        .fileImporter(isPresented: $showingLUTImporter, allowedContentTypes: [UTType(filenameExtension: "cube") ?? .data]) { result in
            if case let .success(url) = result { model.importLUT(url: url) }
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
            .pickerStyle(.segmented)
            .padding([.horizontal, .top])

            Group {
                switch tool {
                case .adjust: AdjustmentPanel(model: model)
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
