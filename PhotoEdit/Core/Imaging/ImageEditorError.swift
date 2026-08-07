import Foundation

enum ImageEditorError: LocalizedError, Sendable {
    case imageLoadFailed
    case unsupportedFormat
    case invalidLUT
    case renderFailed
    case exportFailed
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .imageLoadFailed: "无法读取这张照片。"
        case .unsupportedFormat: "仅支持 JPEG、HEIC/HEIF 和 PNG 图片。"
        case .invalidLUT: "LUT 文件无效。"
        case .renderFailed: "无法渲染编辑结果。"
        case .exportFailed: "无法导出图片。"
        case .permissionDenied: "没有获得照片库权限。"
        }
    }
}
