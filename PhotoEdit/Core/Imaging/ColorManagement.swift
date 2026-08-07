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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sRGB: "sRGB"
        case .displayP3: "Display P3"
        case .linearSRGB: "Linear sRGB"
        case .rec709: "Rec.709"
        case .extendedLinearSRGB: "Extended Linear sRGB"
        case .rec709HLG: "Rec.709 HLG"
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
        }
    }

    var isHDR: Bool { self == .rec709HLG || self == .extendedLinearSRGB }

    static func detect(_ colorSpace: CGColorSpace?) -> ColorSpaceDescriptor? {
        guard let colorSpace else { return nil }
        for descriptor in Self.allCases where CFEqual(colorSpace, descriptor.cgColorSpace) {
            return descriptor
        }
        return nil
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

    static let unspecified = LUTColorMetadata(inputColorSpace: nil, outputColorSpace: nil)
    static let sRGB = LUTColorMetadata(inputColorSpace: .sRGB, outputColorSpace: .sRGB)

    var isComplete: Bool { inputColorSpace != nil && outputColorSpace != nil }
    var summary: String {
        guard let inputColorSpace, let outputColorSpace else { return "色彩空间未指定" }
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

    var errorDescription: String? {
        switch self {
        case let .missingLUTMetadata(name): "LUT“\(name)”未声明输入和输出色彩空间，不能安全套用。"
        case let .invalidTechnicalLUT(name): "Technical LUT“\(name)”缺少完整的色彩变换描述。"
        }
    }
}
