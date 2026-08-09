import SwiftUI

enum EditorTool: String, CaseIterable, Identifiable {
    case light
    case color
    case hsl
    case curves
    case detail
    case lut
    case crop
    case local
    case raw

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: "光线"
        case .color: "颜色"
        case .hsl: "HSL"
        case .curves: "曲线"
        case .detail: "细节"
        case .lut: "LUT"
        case .crop: "裁切"
        case .local: "局部"
        case .raw: "RAW"
        }
    }

    /// SF Symbols 6（iOS 26 SDK）中可用的系统图标；不依赖第三方图标字体。
    var symbolName: String {
        switch self {
        case .light: "sun.max"
        case .color: "camera.filters"
        case .hsl: "circle.lefthalf.filled"
        case .curves: "skew"
        case .detail: "slider.horizontal.3"
        case .lut: "camera.aperture"
        case .crop: "crop"
        case .local: "paintbrush"
        case .raw: "camera.aperture"
        }
    }
}

struct EditorTopBar<MoreActions: View>: View {
    let canUndo: Bool
    let close: () -> Void
    let undo: () -> Void
    let export: () -> Void
    let setShowingBefore: (Bool) -> Void
    private let moreActions: () -> MoreActions

    init(
        canUndo: Bool,
        close: @escaping () -> Void,
        undo: @escaping () -> Void,
        export: @escaping () -> Void,
        setShowingBefore: @escaping (Bool) -> Void,
        @ViewBuilder moreActions: @escaping () -> MoreActions
    ) {
        self.canUndo = canUndo
        self.close = close
        self.undo = undo
        self.export = export
        self.setShowingBefore = setShowingBefore
        self.moreActions = moreActions
    }

    var body: some View {
        HStack(spacing: 8) {
            iconButton("xmark", label: "关闭当前照片", action: close)
            iconButton("arrow.uturn.backward", label: "撤销", action: undo)
                .disabled(!canUndo)

            Image(systemName: "circle.lefthalf.filled")
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .onLongPressGesture(minimumDuration: 0.05, pressing: setShowingBefore, perform: {})
                .accessibilityLabel("查看原图")
                .accessibilityHint("按住显示未编辑原图")

            Spacer(minLength: 0)

            iconButton("square.and.arrow.up", label: "导出", action: export)

            Menu {
                moreActions()
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .accessibilityLabel("更多编辑操作")
            }
            .buttonStyle(.plain)
        }
        .font(.body.weight(.medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .background(.black.opacity(0.38), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.08), lineWidth: 1))
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct EditorToolRail: View {
    let tools: [EditorTool]
    @Binding var selection: EditorTool
    let selectTool: (EditorTool) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tools) { tool in
                        Button {
                            selectTool(tool)
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: tool.symbolName)
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(height: 20)
                                Text(tool.title)
                                    .font(.caption2.weight(.medium))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(width: 58, height: 54)
                            .foregroundStyle(selection == tool ? Color.cyan : .white.opacity(0.62))
                            .background(selection == tool ? Color.white.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(tool.title) 工具")
                        .accessibilityAddTraits(selection == tool ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .frame(minHeight: 62)
    }
}

struct EditorParameterPanel<Content: View>: View {
    let tool: EditorTool
    let collapse: () -> Void
    private let content: Content

    init(tool: EditorTool, collapse: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.tool = tool
        self.collapse = collapse
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: tool.symbolName)
                    .foregroundStyle(.cyan)
                Text(tool.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(action: collapse) {
                    Label("收起", systemImage: "chevron.down")
                        .labelStyle(.iconOnly)
                        .frame(width: 44, height: 36)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))
                .accessibilityLabel("收起参数面板")
            }
            .padding(.horizontal, 16)
            .frame(height: 42)

            Divider().overlay(.white.opacity(0.1))

            content
        }
        .background(Color.photoEditControlSurface)
    }
}

extension Color {
    static let photoEditWorkspace = Color(red: 0.018, green: 0.022, blue: 0.030)
    static let photoEditControlSurface = Color(red: 0.055, green: 0.062, blue: 0.078)
}
