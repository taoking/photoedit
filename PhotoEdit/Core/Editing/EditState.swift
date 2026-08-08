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
    /// 局部区域持有独立 mask 和参数，渲染时在全局调整之后混合。
    var localAdjustments: [LocalAdjustment] = []
    var transform = TransformAdjustment()
    /// 仅 RAW 资产存在；标准 JPEG/HEIF/PNG 保持 nil，避免混入通用调色层。
    var raw: RAWAdjustments?

    static let initial = EditState()

    private enum CodingKeys: String, CodingKey {
        case light, color, hsl, curves, detail, effects, lut, localAdjustments, transform, raw
    }

    init() {}

    /// 编辑预设会跨版本保留。新字段必须在这里提供默认值，才能继续打开旧版本保存的 JSON。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        light = try container.decodeIfPresent(LightAdjustments.self, forKey: .light) ?? .init()
        color = try container.decodeIfPresent(ColorAdjustments.self, forKey: .color) ?? .init()
        hsl = try container.decodeIfPresent(HSLAdjustments.self, forKey: .hsl) ?? .init()
        curves = try container.decodeIfPresent(ToneCurveAdjustments.self, forKey: .curves) ?? .init()
        detail = try container.decodeIfPresent(DetailAdjustments.self, forKey: .detail) ?? .init()
        effects = try container.decodeIfPresent(EffectAdjustments.self, forKey: .effects) ?? .init()
        lut = try container.decodeIfPresent(LUTAdjustment.self, forKey: .lut) ?? .init()
        localAdjustments = try container.decodeIfPresent([LocalAdjustment].self, forKey: .localAdjustments) ?? []
        transform = try container.decodeIfPresent(TransformAdjustment.self, forKey: .transform) ?? .init()
        raw = try container.decodeIfPresent(RAWAdjustments.self, forKey: .raw)
    }

    mutating func reset() {
        self = .initial
    }
}

struct RAWAdjustments: Codable, Equatable, Sendable {
    var exposure: Double = 0
    /// 相对 RAW decoder / as-shot 白平衡的温度增量；0 必须保持 decoder 默认值。
    var temperature: Double = 0
    /// 相对 RAW decoder / as-shot 白平衡的 tint 增量；0 必须保持 decoder 默认值。
    var tint: Double = 0
    /// `nil` 表示从未由用户覆盖，必须保留 CIRAWFilter decoder 默认值。
    var luminanceNoiseReduction: Double?
    /// `nil` 表示从未由用户覆盖，必须保留 CIRAWFilter decoder 默认值。
    var colorNoiseReduction: Double?
    /// `nil` 表示从未由用户覆盖，必须保留 CIRAWFilter decoder 默认值。
    var sharpness: Double?
    /// `nil` 表示从未由用户覆盖，必须保留 CIRAWFilter decoder 默认值。
    var detail: Double?
    /// `nil` 表示从未由用户覆盖，必须保留 CIRAWFilter decoder 默认值。
    var localTone: Double?
    /// `nil` 表示从未由用户覆盖，必须保留 CIRAWFilter decoder 默认值。
    var lensCorrectionEnabled: Bool?

    /// 新 schema 使用 Optional 表达「未覆盖」。旧版本 JSON 没有这个标记，无法区分
    /// 用户手动设为 0 与旧 UI 的默认 0，因此为保持既有编辑结果，把旧值迁移为显式覆盖。
    private static let decoderOverrideSchemaVersion = 1

    private enum CodingKeys: String, CodingKey {
        case decoderOverrideSchemaVersion
        case exposure, temperature, tint
        case luminanceNoiseReduction, colorNoiseReduction, sharpness, detail, localTone, lensCorrectionEnabled
    }

    init(
        exposure: Double = 0,
        temperature: Double = 0,
        tint: Double = 0,
        luminanceNoiseReduction: Double? = nil,
        colorNoiseReduction: Double? = nil,
        sharpness: Double? = nil,
        detail: Double? = nil,
        localTone: Double? = nil,
        lensCorrectionEnabled: Bool? = nil
    ) {
        self.exposure = exposure
        self.temperature = temperature
        self.tint = tint
        self.luminanceNoiseReduction = luminanceNoiseReduction
        self.colorNoiseReduction = colorNoiseReduction
        self.sharpness = sharpness
        self.detail = detail
        self.localTone = localTone
        self.lensCorrectionEnabled = lensCorrectionEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exposure = try container.decodeIfPresent(Double.self, forKey: .exposure) ?? 0
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 0
        tint = try container.decodeIfPresent(Double.self, forKey: .tint) ?? 0

        // Phase 8.5 前的 JSON 中，这些字段全是非 Optional。保留其写入语义，避免
        // 已保存的 RAW 编辑被无声改变；所有新建 RAW state 则会以 nil 保留 decoder。
        let isLegacy = !container.contains(.decoderOverrideSchemaVersion)
        luminanceNoiseReduction = try container.decodeIfPresent(Double.self, forKey: .luminanceNoiseReduction)
        colorNoiseReduction = try container.decodeIfPresent(Double.self, forKey: .colorNoiseReduction)
        sharpness = try container.decodeIfPresent(Double.self, forKey: .sharpness)
        detail = try container.decodeIfPresent(Double.self, forKey: .detail)
        localTone = try container.decodeIfPresent(Double.self, forKey: .localTone)
        lensCorrectionEnabled = try container.decodeIfPresent(Bool.self, forKey: .lensCorrectionEnabled)

        if !isLegacy {
            // 读取版本标记以拒绝损坏的非整数值；当前仅有一个 schema。
            _ = try container.decode(Int.self, forKey: .decoderOverrideSchemaVersion)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.decoderOverrideSchemaVersion, forKey: .decoderOverrideSchemaVersion)
        try container.encode(exposure, forKey: .exposure)
        try container.encode(temperature, forKey: .temperature)
        try container.encode(tint, forKey: .tint)
        try container.encodeIfPresent(luminanceNoiseReduction, forKey: .luminanceNoiseReduction)
        try container.encodeIfPresent(colorNoiseReduction, forKey: .colorNoiseReduction)
        try container.encodeIfPresent(sharpness, forKey: .sharpness)
        try container.encodeIfPresent(detail, forKey: .detail)
        try container.encodeIfPresent(localTone, forKey: .localTone)
        try container.encodeIfPresent(lensCorrectionEnabled, forKey: .lensCorrectionEnabled)
    }

    var whiteBalanceAdjustment: RAWWhiteBalanceAdjustment {
        RAWWhiteBalanceAdjustment(temperatureDelta: temperature, tintDelta: tint)
    }

    /// 将 UI 值转换为可安全写入 CIRAWFilter 的显式请求。所有 nil 均意味着完全不触碰
    /// 对应 decoder 属性，因此新打开 RAW 的初始效果等于相机 / decoder 默认效果。
    var decoderOverrides: RAWDecoderOverrides {
        RAWDecoderOverrides(
            luminanceNoiseReduction: luminanceNoiseReduction.map { Float($0.clamped(to: 0...1)) },
            colorNoiseReduction: colorNoiseReduction.map { Float($0.clamped(to: 0...1)) },
            sharpness: sharpness.map { Float($0.clamped(to: 0...1)) },
            detail: detail.map { Float($0.clamped(to: 0...3)) },
            localTone: localTone.map { Float($0.clamped(to: 0...1)) },
            lensCorrectionEnabled: lensCorrectionEnabled
        )
    }
}

/// CIRAWFilter 相关参数的最终覆盖请求。Optional 表示「不设置该 filter 属性」。
struct RAWDecoderOverrides: Equatable, Sendable {
    var luminanceNoiseReduction: Float?
    var colorNoiseReduction: Float?
    var sharpness: Float?
    var detail: Float?
    var localTone: Float?
    var lensCorrectionEnabled: Bool?

    init(
        luminanceNoiseReduction: Float? = nil,
        colorNoiseReduction: Float? = nil,
        sharpness: Float? = nil,
        detail: Float? = nil,
        localTone: Float? = nil,
        lensCorrectionEnabled: Bool? = nil
    ) {
        self.luminanceNoiseReduction = luminanceNoiseReduction
        self.colorNoiseReduction = colorNoiseReduction
        self.sharpness = sharpness
        self.detail = detail
        self.localTone = localTone
        self.lensCorrectionEnabled = lensCorrectionEnabled
    }
}

/// RAW 白平衡保存用户相对于解码器 as-shot 默认值的增量，而不是固定的绝对白点。
struct RAWWhiteBalanceAdjustment: Codable, Equatable, Sendable {
    var temperatureDelta: Double = 0
    var tintDelta: Double = 0

    var isIdentity: Bool { temperatureDelta == 0 && tintDelta == 0 }

    func resolved(decoderTemperature: Float, decoderTint: Float) -> (temperature: Float, tint: Float) {
        (
            Float((Double(decoderTemperature) + temperatureDelta * 20).clamped(to: 2_000...50_000)),
            Float((Double(decoderTint) + tintDelta).clamped(to: -150...150))
        )
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
    /// Creative LUT 在常规调整之后执行，并支持强度混合。
    var selectedLUTID: UUID?
    /// Technical LUT 在常规调整之前执行，且始终以 100% 作为色彩变换。
    var technicalLUTID: UUID?
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
