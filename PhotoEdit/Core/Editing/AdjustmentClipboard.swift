import Combine
import Foundation

enum AdjustmentGroup: String, CaseIterable, Identifiable, Sendable {
    case light, color, hsl, curve, lut, local, detail, effects, crop

    var id: String { rawValue }
    var title: String {
        switch self {
        case .light: "光线"
        case .color: "颜色"
        case .hsl: "HSL"
        case .curve: "曲线"
        case .lut: "LUT"
        case .local: "局部调整"
        case .detail: "细节"
        case .effects: "效果"
        case .crop: "裁切与变换"
        }
    }
}
@MainActor
final class AdjustmentClipboard: ObservableObject {
    @Published private(set) var copiedState: EditState?

    var hasAdjustments: Bool { copiedState != nil }

    func copy(from state: EditState) {
        copiedState = state.canonicalized()
    }

    func paste(into destination: EditState, groups: Set<AdjustmentGroup> = Set(AdjustmentGroup.allCases)) -> EditState? {
        guard let source = copiedState else { return nil }
        var output = destination
        if groups.contains(.light) { output.light = source.light }
        if groups.contains(.color) { output.color = source.color }
        if groups.contains(.hsl) { output.hsl = source.hsl }
        if groups.contains(.curve) { output.curves = source.curves }
        if groups.contains(.lut) { output.lut = source.lut }
        if groups.contains(.local) { output.localAdjustments = source.localAdjustments }
        if groups.contains(.detail) { output.detail = source.detail }
        if groups.contains(.effects) { output.effects = source.effects }
        if groups.contains(.crop) { output.transform = source.transform }
        return output
    }
}
