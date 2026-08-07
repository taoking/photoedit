import Foundation

/// 所有编辑均由此值类型描述；它不持有图像或滤镜，因此可安全地保存、复制和用于撤销。
struct EditState: Codable, Equatable, Sendable {
    var light = LightAdjustments()
    var color = ColorAdjustments()
    var hsl = HSLAdjustments()
    var curves = ToneCurveAdjustments()
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

enum HSLChannel: String, Codable, CaseIterable, Identifiable, Sendable {
    case red, orange, yellow, green, aqua, blue, purple, magenta

    var id: String { rawValue }

    var title: String {
        switch self {
        case .red: "红"
        case .orange: "橙"
        case .yellow: "黄"
        case .green: "绿"
        case .aqua: "青"
        case .blue: "蓝"
        case .purple: "紫"
        case .magenta: "洋红"
        }
    }

    /// 归一化 HSL 色相；红色 0/1，顺时针依照 RGB 色环。
    var hueCenter: Double {
        switch self {
        case .red: 0
        case .orange: 30.0 / 360
        case .yellow: 60.0 / 360
        case .green: 120.0 / 360
        case .aqua: 180.0 / 360
        case .blue: 240.0 / 360
        case .purple: 270.0 / 360
        case .magenta: 330.0 / 360
        }
    }
}

struct HSLChannelAdjustment: Codable, Equatable, Sendable {
    /// Hue 使用 -100...100 映射为 -0.5...0.5 个完整色环。
    var hue: Double = 0
    var saturation: Double = 0
    var luminance: Double = 0

    var isIdentity: Bool { hue == 0 && saturation == 0 && luminance == 0 }
}

struct HSLAdjustments: Codable, Equatable, Sendable {
    var red = HSLChannelAdjustment()
    var orange = HSLChannelAdjustment()
    var yellow = HSLChannelAdjustment()
    var green = HSLChannelAdjustment()
    var aqua = HSLChannelAdjustment()
    var blue = HSLChannelAdjustment()
    var purple = HSLChannelAdjustment()
    var magenta = HSLChannelAdjustment()

    subscript(channel: HSLChannel) -> HSLChannelAdjustment {
        get {
            switch channel {
            case .red: red
            case .orange: orange
            case .yellow: yellow
            case .green: green
            case .aqua: aqua
            case .blue: blue
            case .purple: purple
            case .magenta: magenta
            }
        }
        set {
            switch channel {
            case .red: red = newValue
            case .orange: orange = newValue
            case .yellow: yellow = newValue
            case .green: green = newValue
            case .aqua: aqua = newValue
            case .blue: blue = newValue
            case .purple: purple = newValue
            case .magenta: magenta = newValue
            }
        }
    }

    var isIdentity: Bool { HSLChannel.allCases.allSatisfy { self[$0].isIdentity } }

    mutating func reset(_ channel: HSLChannel) { self[channel] = HSLChannelAdjustment() }
    mutating func resetAll() { self = HSLAdjustments() }
}

enum ToneCurveChannel: String, Codable, CaseIterable, Identifiable, Sendable {
    case master, red, green, blue

    var id: String { rawValue }
    var title: String {
        switch self {
        case .master: "RGB"
        case .red: "红"
        case .green: "绿"
        case .blue: "蓝"
        }
    }
}

struct CurvePoint: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var x: Double
    var y: Double

    init(id: String = UUID().uuidString, x: Double, y: Double) {
        self.id = id
        self.x = x
        self.y = y
    }

    static let start = CurvePoint(id: "start", x: 0, y: 0)
    static let end = CurvePoint(id: "end", x: 1, y: 1)
}

struct ToneCurve: Codable, Equatable, Sendable {
    private(set) var points: [CurvePoint]

    init(points: [CurvePoint] = [.start, .end]) {
        self.points = Self.normalized(points)
    }

    var isIdentity: Bool { points == [.start, .end] }

    func value(at x: Double) -> Double {
        let input = x.clamped(to: 0...1)
        guard let first = points.first, let last = points.last else { return input }
        if input <= first.x { return first.y }
        if input >= last.x { return last.y }
        for (left, right) in zip(points, points.dropFirst()) where input >= left.x && input <= right.x {
            let span = right.x - left.x
            guard span > 0 else { return left.y }
            let progress = (input - left.x) / span
            return (left.y + (right.y - left.y) * progress).clamped(to: 0...1)
        }
        return input
    }

    mutating func addPoint(x: Double, y: Double) {
        let candidateX = x.clamped(to: 0...1)
        guard candidateX > 0.001, candidateX < 0.999,
              !points.contains(where: { abs($0.x - candidateX) < 0.01 }) else { return }
        points.append(CurvePoint(x: candidateX, y: y.clamped(to: 0...1)))
        points = Self.normalized(points)
    }

    mutating func movePoint(id: String, x: Double, y: Double) {
        guard let index = points.firstIndex(where: { $0.id == id }) else { return }
        var point = points[index]
        let isStart = point.id == CurvePoint.start.id
        let isEnd = point.id == CurvePoint.end.id
        let lower = isStart ? 0 : points[index - 1].x + 0.001
        let upper = isEnd ? 1 : points[index + 1].x - 0.001
        point.x = (isStart ? 0 : isEnd ? 1 : x).clamped(to: lower...upper)
        point.y = y.clamped(to: 0...1)
        points[index] = point
        points = Self.normalized(points)
    }

    mutating func removePoint(id: String) {
        guard id != CurvePoint.start.id, id != CurvePoint.end.id else { return }
        points.removeAll { $0.id == id }
        points = Self.normalized(points)
    }

    mutating func reset() { points = [.start, .end] }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        points = Self.normalized(try container.decode([CurvePoint].self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(points)
    }

    private static func normalized(_ rawPoints: [CurvePoint]) -> [CurvePoint] {
        let startY = rawPoints.first(where: { $0.id == CurvePoint.start.id })?.y.clamped(to: 0...1) ?? 0
        let endY = rawPoints.first(where: { $0.id == CurvePoint.end.id })?.y.clamped(to: 0...1) ?? 1
        var interior = rawPoints.filter { $0.id != CurvePoint.start.id && $0.id != CurvePoint.end.id }
            .map { CurvePoint(id: $0.id, x: $0.x.clamped(to: 0.001...0.999), y: $0.y.clamped(to: 0...1)) }
        interior.sort { $0.x < $1.x }
        interior = interior.enumerated().map { index, point in
            let lower = index == 0 ? 0.001 : interior[index - 1].x + 0.001
            return CurvePoint(id: point.id, x: max(point.x, lower).clamped(to: 0.001...0.999), y: point.y)
        }
        return [CurvePoint(id: CurvePoint.start.id, x: 0, y: startY)] + interior + [CurvePoint(id: CurvePoint.end.id, x: 1, y: endY)]
    }
}

struct ToneCurveAdjustments: Codable, Equatable, Sendable {
    var master = ToneCurve()
    var red = ToneCurve()
    var green = ToneCurve()
    var blue = ToneCurve()

    subscript(channel: ToneCurveChannel) -> ToneCurve {
        get {
            switch channel {
            case .master: master
            case .red: red
            case .green: green
            case .blue: blue
            }
        }
        set {
            switch channel {
            case .master: master = newValue
            case .red: red = newValue
            case .green: green = newValue
            case .blue: blue = newValue
            }
        }
    }

    var isIdentity: Bool { ToneCurveChannel.allCases.allSatisfy { self[$0].isIdentity } }
    mutating func resetAll() { self = ToneCurveAdjustments() }
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
