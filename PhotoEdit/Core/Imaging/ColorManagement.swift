import CoreGraphics
import Foundation

/// 可持久化的 RGB 色彩描述。HDR 传递函数在 Phase 6 进一步决定导出策略；此处仅保证它们不会被伪装为 sRGB。
enum ColorSpaceDescriptor: String, Codable, CaseIterable, Identifiable, Sendable {
    case sRGB
    case displayP3
    case linearSRGB
    case rec709
    case extendedLinearSRGB
    case rec709HLG
    case rec2100HLG

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sRGB: "sRGB"
        case .displayP3: "Display P3"
        case .linearSRGB: "Linear sRGB"
        case .rec709: "Rec.709"
        case .extendedLinearSRGB: "Extended Linear sRGB"
        case .rec709HLG: "Rec.709 HLG"
        case .rec2100HLG: "Rec.2100 HLG"
        }
    }

    var cgColorSpace: CGColorSpace {
        switch self {
        case .sRGB: CGColorSpace(name: CGColorSpace.sRGB)!
        case .displayP3: CGColorSpace(name: CGColorSpace.displayP3)!
        case .linearSRGB: CGColorSpace(name: CGColorSpace.linearSRGB)!
        case .rec709: CGColorSpace(name: CGColorSpace.itur_709)!
        case .extendedLinearSRGB: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        case .rec709HLG: CGColorSpace(name: CGColorSpace.itur_709_HLG)!
        case .rec2100HLG: CGColorSpace(name: CGColorSpace.itur_2100_HLG)!
        }
    }

    var isHDR: Bool { self == .rec709HLG || self == .rec2100HLG || self == .extendedLinearSRGB }

    static func detect(_ colorSpace: CGColorSpace?) -> ColorSpaceDescriptor? {
        guard let colorSpace else { return nil }
        for descriptor in Self.allCases where CFEqual(colorSpace, descriptor.cgColorSpace) {
            return descriptor
        }
        return nil
    }
}

/// 色域/原色与传递函数必须分开表达；一个颜色空间名称不足以说明 Technical LUT
/// 是否适用于输入素材。Sony/ARRI log 编码可被建模，但在本应用尚无真实转换实现时
/// 必须被拒绝，而不能伪装为 Rec.709 或 sRGB。
enum ColorPrimaries: String, Codable, CaseIterable, Sendable {
    case sRGBRec709
    case displayP3
    case rec2020
    case sonySGamut3
    case sonySGamut3Cine
}

enum TransferFunction: String, Codable, CaseIterable, Sendable {
    case sRGB
    case linear
    case gamma22
    case gamma24
    case rec709
    case hlg
    case pq
    case sLog3
}

struct ColorEncodingDescriptor: Codable, Equatable, Sendable {
    var primaries: ColorPrimaries
    var transferFunction: TransferFunction

    init(primaries: ColorPrimaries, transferFunction: TransferFunction) {
        self.primaries = primaries
        self.transferFunction = transferFunction
    }

    init?(colorSpace: ColorSpaceDescriptor?) {
        guard let colorSpace else { return nil }
        switch colorSpace {
        case .sRGB:
            self.init(primaries: .sRGBRec709, transferFunction: .sRGB)
        case .displayP3:
            self.init(primaries: .displayP3, transferFunction: .sRGB)
        case .linearSRGB, .extendedLinearSRGB:
            self.init(primaries: .sRGBRec709, transferFunction: .linear)
        case .rec709:
            self.init(primaries: .sRGBRec709, transferFunction: .rec709)
        case .rec709HLG:
            self.init(primaries: .sRGBRec709, transferFunction: .hlg)
        case .rec2100HLG:
            self.init(primaries: .rec2020, transferFunction: .hlg)
        }
    }

    /// 仅返回可由当前 Core Image 管线实际构造的色彩空间。不存在的映射（例如
    /// S-Log3/S-Gamut3.Cine）意味着“已描述，但尚不支持”，而不是回退到 sRGB。
    var colorSpaceDescriptor: ColorSpaceDescriptor? {
        switch (primaries, transferFunction) {
        case (.sRGBRec709, .sRGB): .sRGB
        case (.displayP3, .sRGB): .displayP3
        case (.sRGBRec709, .linear): .linearSRGB
        case (.sRGBRec709, .rec709): .rec709
        case (.sRGBRec709, .hlg): .rec709HLG
        case (.rec2020, .hlg): .rec2100HLG
        default: nil
        }
    }
}

enum LUTKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case creative
    case technical

    var id: String { rawValue }
    var title: String { self == .creative ? "Creative" : "Technical" }
}

struct LUTColorMetadata: Codable, Equatable, Sendable {
    /// `.cube` 本身通常不包含可靠色彩空间描述，未设置时不能按 Technical LUT 渲染。
    var inputColorSpace: ColorSpaceDescriptor?
    var outputColorSpace: ColorSpaceDescriptor?

    /// 新 schema 明确保留原色/传递函数；从 Phase 5 的旧 JSON 缺失时由已存的
    /// `ColorSpaceDescriptor` 无损迁移。
    var inputEncoding: ColorEncodingDescriptor?
    var outputEncoding: ColorEncodingDescriptor?

    init(
        inputColorSpace: ColorSpaceDescriptor?,
        outputColorSpace: ColorSpaceDescriptor?
    ) {
        self.inputColorSpace = inputColorSpace
        self.outputColorSpace = outputColorSpace
        inputEncoding = ColorEncodingDescriptor(colorSpace: inputColorSpace)
        outputEncoding = ColorEncodingDescriptor(colorSpace: outputColorSpace)
    }

    init(inputEncoding: ColorEncodingDescriptor?, outputEncoding: ColorEncodingDescriptor?) {
        self.inputEncoding = inputEncoding
        self.outputEncoding = outputEncoding
        inputColorSpace = inputEncoding?.colorSpaceDescriptor
        outputColorSpace = outputEncoding?.colorSpaceDescriptor
    }

    private enum CodingKeys: String, CodingKey {
        case inputColorSpace, outputColorSpace, inputEncoding, outputEncoding
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputColorSpace = try container.decodeIfPresent(ColorSpaceDescriptor.self, forKey: .inputColorSpace)
        outputColorSpace = try container.decodeIfPresent(ColorSpaceDescriptor.self, forKey: .outputColorSpace)
        inputEncoding = try container.decodeIfPresent(ColorEncodingDescriptor.self, forKey: .inputEncoding)
            ?? ColorEncodingDescriptor(colorSpace: inputColorSpace)
        outputEncoding = try container.decodeIfPresent(ColorEncodingDescriptor.self, forKey: .outputEncoding)
            ?? ColorEncodingDescriptor(colorSpace: outputColorSpace)
        // A newer JSON may describe an unsupported encoding without legacy color-space fields.
        inputColorSpace = inputColorSpace ?? inputEncoding?.colorSpaceDescriptor
        outputColorSpace = outputColorSpace ?? outputEncoding?.colorSpaceDescriptor
    }

    static let unspecified = LUTColorMetadata(inputColorSpace: nil, outputColorSpace: nil)
    static let sRGB = LUTColorMetadata(inputColorSpace: .sRGB, outputColorSpace: .sRGB)

    var isComplete: Bool { inputEncoding != nil && outputEncoding != nil }
    /// Metadata 中的 legacy color-space 字段必须与 encoding 反解结果一致。否则不能让
    /// 两套描述相互矛盾地绕过 Technical LUT 的 source/encoding 校验。
    var isImplementedByPhotoPipeline: Bool {
        guard let inputEncoding,
              let outputEncoding,
              let resolvedInput = inputEncoding.colorSpaceDescriptor,
              let resolvedOutput = outputEncoding.colorSpaceDescriptor else {
            return false
        }
        return inputColorSpace == resolvedInput && outputColorSpace == resolvedOutput
    }

    /// 当前没有跨 encoding 的 Technical transform；即使两个 encoding 都能被 Core Image
    /// 描述，也只能安全地接受严格 identity encoding 的 Technical LUT。
    var hasSameInputAndOutputEncoding: Bool {
        inputEncoding != nil && inputEncoding == outputEncoding
    }
    var summary: String {
        guard let inputEncoding, let outputEncoding else { return "色彩空间未指定" }
        guard let inputColorSpace, let outputColorSpace else {
            return "\(inputEncoding.primaries.rawValue) / \(inputEncoding.transferFunction.rawValue) → \(outputEncoding.primaries.rawValue) / \(outputEncoding.transferFunction.rawValue)（尚不支持）"
        }
        return "\(inputColorSpace.title) → \(outputColorSpace.title)"
    }
}

struct ColorRenderPlan: Equatable, Sendable {
    let source: ColorSpaceDescriptor
    let working: ColorSpaceDescriptor
    let hasTechnicalTransform: Bool
    let hasCreativeLUT: Bool
    let output: ColorSpaceDescriptor
}

enum ColorManagementError: LocalizedError, Sendable {
    case missingLUTMetadata(name: String)
    case invalidTechnicalLUT(name: String)
    case incompatibleTechnicalLUT(name: String, source: ColorSpaceDescriptor, expected: ColorSpaceDescriptor)
    case crossEncodingTechnicalLUTUnsupported(name: String, input: ColorEncodingDescriptor, output: ColorEncodingDescriptor)
    case unsupportedLUTEncoding(name: String)

    var errorDescription: String? {
        switch self {
        case let .missingLUTMetadata(name): "LUT“\(name)”未声明输入和输出色彩空间，不能安全套用。"
        case let .invalidTechnicalLUT(name): "Technical LUT“\(name)”缺少完整的色彩变换描述。"
        case let .incompatibleTechnicalLUT(name, source, expected): "Technical LUT“\(name)”需要 \(expected.title) 输入，但当前照片是 \(source.title)；应用未执行未经声明的转换。"
        case let .crossEncodingTechnicalLUTUnsupported(name, input, output): "Technical LUT“\(name)”声明了 \(input.transferFunction.rawValue) → \(output.transferFunction.rawValue) 的跨编码转换；当前版本仅支持输入和输出 encoding 完全相同的 Technical LUT。"
        case let .unsupportedLUTEncoding(name): "LUT“\(name)”使用当前照片管线尚未实现的色域或传递函数（例如 S-Log3）；已安全拒绝套用。"
        }
    }
}
