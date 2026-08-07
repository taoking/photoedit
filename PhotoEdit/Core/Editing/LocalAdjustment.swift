import Foundation

/// 一个局部区域只保存自身的参数和蒙版，绝不把多个局部滑杆混进全局 `EditState`。
struct LocalAdjustment: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var isEnabled: Bool
    var mask: LocalMask
    var adjustments: LocalAdjustmentValues

    init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        mask: LocalMask,
        adjustments: LocalAdjustmentValues = LocalAdjustmentValues()
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.mask = mask
        self.adjustments = adjustments
    }

    static func linear() -> LocalAdjustment {
        LocalAdjustment(name: "线性渐变", mask: .linear(LinearGradientMask()))
    }

    static func radial() -> LocalAdjustment {
        LocalAdjustment(name: "径向渐变", mask: .radial(RadialGradientMask()))
    }

    static func brush() -> LocalAdjustment {
        LocalAdjustment(name: "画笔", mask: .brush(BrushMask()))
    }
}

struct LocalAdjustmentValues: Codable, Equatable, Sendable {
    /// 与全局 Light/Color 使用相同 UI 单位；实际滤镜单位在渲染器中映射。
    var exposure: Double = 0
    var contrast: Double = 0
    var saturation: Double = 0

    var isIdentity: Bool { exposure == 0 && contrast == 0 && saturation == 0 }
}

enum LocalMask: Codable, Equatable, Sendable {
    case linear(LinearGradientMask)
    case radial(RadialGradientMask)
    case brush(BrushMask)

    var title: String {
        switch self {
        case .linear: "线性"
        case .radial: "径向"
        case .brush: "画笔"
        }
    }
}

struct NormalizedPoint: Codable, Equatable, Sendable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x.clamped(to: 0...1)
        self.y = y.clamped(to: 0...1)
    }
}

struct LinearGradientMask: Codable, Equatable, Sendable {
    /// 1.0 alpha 的起点与 0.0 alpha 的终点，均为未裁切原图坐标。
    var start = NormalizedPoint(x: 0.25, y: 0.5)
    var end = NormalizedPoint(x: 0.75, y: 0.5)
}

struct RadialGradientMask: Codable, Equatable, Sendable {
    var center = NormalizedPoint(x: 0.5, y: 0.5)
    /// 内圆半径，占原图短边比例。
    var radius: Double = 0.12
    /// 从内圆到透明边缘的额外半径，占原图短边比例。
    var feather: Double = 0.28
}

struct BrushMask: Codable, Equatable, Sendable {
    var points: [NormalizedPoint] = []
    /// 画笔直径占原图短边比例。
    var size: Double = 0.12
    /// 0 表示软边，1 表示接近硬边。
    var hardness: Double = 0.5
}
