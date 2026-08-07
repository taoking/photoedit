import CoreImage
import Foundation

/// 导出目标的动态范围。默认仍为 SDR，绝不会仅靠文件扩展名把普通图像标记为 HDR。
enum ExportDynamicRange: String, Codable, CaseIterable, Identifiable, Sendable {
    case sdr
    case hdr

    var id: String { rawValue }
    var title: String { self == .sdr ? "SDR（sRGB）" : "HDR（10-bit HEIF）" }
}

enum RenderDynamicRange: Sendable, Equatable {
    case sdr
    case hdr
}

struct HDRRenderPlan: Equatable, Sendable {
    let sourceIsHDR: Bool
    let sourceHeadroom: Float
    let target: ExportDynamicRange
    let outputColorSpace: ColorSpaceDescriptor
}

enum HDRRenderingError: LocalizedError, Sendable, Equatable {
    case hdrRequiresHEIF
    case hdrRequiresHDRSource
    case hdrEncodingUnavailable
    case toneMappingUnavailable

    var errorDescription: String? {
        switch self {
        case .hdrRequiresHEIF: "HDR 导出仅支持 HEIF。"
        case .hdrRequiresHDRSource: "HDR 导出需要带 Extended Dynamic Range 或 HDR gain map 的源照片。"
        case .hdrEncodingUnavailable: "当前设备不支持 10-bit HEIF HDR 编码。"
        case .toneMappingUnavailable: "当前系统无法对 HDR 输入执行 SDR tone mapping。"
        }
    }
}

enum HDRRendering {
    static func sourceHeadroom(for image: CIImage, colorSpace: ColorSpaceDescriptor?) -> Float {
        if #available(iOS 18.0, *) {
            let reported = image.contentHeadroom
            if reported >= 1 { return reported }
        }
        // HLG/extended 色彩空间没有在 iOS 17 上公开 contentHeadroom 时，保守地用 2x
        // 触发 SDR tone mapping；并不会据此允许不存在 HDR 内容的普通 sRGB 图像导出 HDR。
        return colorSpace?.isHDR == true ? 2 : 1
    }

    static func makePlan(
        sourceColorSpace: ColorSpaceDescriptor?,
        sourceHeadroom: Float,
        target: ExportDynamicRange,
        format: ExportFormat
    ) throws -> HDRRenderPlan {
        let sourceIsHDR = sourceHeadroom > 1 || sourceColorSpace?.isHDR == true
        switch target {
        case .sdr:
            return HDRRenderPlan(
                sourceIsHDR: sourceIsHDR,
                sourceHeadroom: max(1, sourceHeadroom),
                target: .sdr,
                outputColorSpace: .sRGB
            )
        case .hdr:
            guard format == .heif else { throw HDRRenderingError.hdrRequiresHEIF }
            guard sourceIsHDR else { throw HDRRenderingError.hdrRequiresHDRSource }
            return HDRRenderPlan(
                sourceIsHDR: true,
                sourceHeadroom: max(1, sourceHeadroom),
                target: .hdr,
                outputColorSpace: .rec2100HLG
            )
        }
    }

    static func toneMapToSDR(_ image: CIImage, sourceHeadroom: Float) throws -> CIImage {
        guard sourceHeadroom > 1 else { return image }
        guard #available(iOS 18.0, *) else { throw HDRRenderingError.toneMappingUnavailable }
        guard let filter = CIFilter(name: "CIToneMapHeadroom") else {
            throw HDRRenderingError.toneMappingUnavailable
        }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(sourceHeadroom, forKey: "inputSourceHeadroom")
        filter.setValue(Float(1), forKey: "inputTargetHeadroom")
        guard let output = filter.outputImage else { throw HDRRenderingError.toneMappingUnavailable }
        return output
    }
}
