import Foundation

/// 所有编辑均由此值类型描述；它不持有图像或滤镜，因此可安全地保存、复制和用于撤销。
struct EditState: Codable, Equatable, Sendable {
    var light = LightAdjustments()
    var color = ColorAdjustments()
    var detail = DetailAdjustments()
    var effects = EffectAdjustments()
    var lut = LUTAdjustment()
    var transform = TransformAdjustment()

    static let initial = EditState()

    mutating func reset() {
        self = .initial
    }
}

struct LightAdjustments: Codable, Equatable, Sendable {
    /// EV，范围由 UI 限制在 -5...5。
    var exposure: Double = 0
    /// UI 单位为 -100...100。
    var contrast: Double = 0
    var highlights: Double = 0
    var shadows: Double = 0
}

struct ColorAdjustments: Codable, Equatable, Sendable {
    /// 相对 D65 的 UI 单位，范围 -100...100。
    var temperature: Double = 0
    var tint: Double = 0
    var saturation: Double = 0
    var vibrance: Double = 0
}

struct DetailAdjustments: Codable, Equatable, Sendable {
    var sharpness: Double = 0
}

struct EffectAdjustments: Codable, Equatable, Sendable {
    var vignette: Double = 0
}

struct LUTAdjustment: Codable, Equatable, Sendable {
    var selectedLUTID: UUID?
    /// 0 表示不套 LUT，1 表示完整 LUT。
    var intensity: Double = 1
}

enum CropAspectRatio: String, Codable, CaseIterable, Identifiable, Sendable {
    case free
    case original
    case oneToOne = "1:1"
    case fourToThree = "4:3"
    case threeToTwo = "3:2"
    case sixteenToNine = "16:9"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: "自由"
        case .original: "原始"
        default: rawValue
        }
    }

    var ratio: Double? {
        switch self {
        case .oneToOne: 1
        case .fourToThree: 4.0 / 3.0
        case .threeToTwo: 3.0 / 2.0
        case .sixteenToNine: 16.0 / 9.0
        case .free, .original: nil
        }
    }
}

struct NormalizedRect: Codable, Equatable, Sendable {
    var x: Double = 0
    var y: Double = 0
    var width: Double = 1
    var height: Double = 1

    static let unit = NormalizedRect()

    func clamped() -> NormalizedRect {
        let width = width.clamped(to: 0.02...1)
        let height = height.clamped(to: 0.02...1)
        return NormalizedRect(
            x: x.clamped(to: 0...(1 - width)),
            y: y.clamped(to: 0...(1 - height)),
            width: width,
            height: height
        )
    }
}

struct CropState: Codable, Equatable, Sendable {
    var aspectRatio: CropAspectRatio = .original
    /// 相对经过旋转后的图像范围；自由裁切使用它的全部四个值。
    var normalizedRect: NormalizedRect = .unit

    mutating func reset() {
        aspectRatio = .original
        normalizedRect = .unit
    }
}

struct TransformAdjustment: Codable, Equatable, Sendable {
    var crop = CropState()
    /// 仅允许 0/90/180/270，见 `rotateClockwise()`。
    var rotation: Int = 0
    var horizontalFlip = false

    mutating func rotateClockwise() {
        rotation = (rotation + 90) % 360
    }

    mutating func reset() {
        self = TransformAdjustment()
    }
}

enum AdjustmentMapper {
    static func exposureEV(_ value: Double) -> Float { Float(value.clamped(to: -5...5)) }
    static func contrast(_ value: Double) -> Float { Float(1 + value.clamped(to: -100...100) / 100) }
    /// Core Image 的 1 是中性；正的 UI 值降低高光以恢复细节。
    static func highlightAmount(_ value: Double) -> Float { Float(1 - value.clamped(to: -100...100) / 100) }
    /// Core Image 的 1 是中性；正的 UI 值抬升阴影。
    static func shadowAmount(_ value: Double) -> Float { Float(1 + value.clamped(to: -100...100) / 100) }
    static func temperature(_ value: Double) -> Float { Float((6500 + value.clamped(to: -100...100) * 20).clamped(to: 2000...10000)) }
    static func tint(_ value: Double) -> Float { Float(value.clamped(to: -100...100) * 1.5) }
    static func saturation(_ value: Double) -> Float { Float(1 + value.clamped(to: -100...100) / 100) }
    static func vibrance(_ value: Double) -> Float { Float(value.clamped(to: -100...100) / 100) }
    static func sharpness(_ value: Double) -> Float { Float(value.clamped(to: 0...100) / 50) }
    static func vignette(_ value: Double) -> Float { Float(value.clamped(to: -100...100) / 100) }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
