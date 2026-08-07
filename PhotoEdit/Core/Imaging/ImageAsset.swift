import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ImageAsset: @unchecked Sendable {
    let id: UUID
    let sourceName: String
    /// 图像读取时已经应用 EXIF Orientation；原始 Data 从不被修改。
    let fullResolutionImage: CIImage
    let originalData: Data
    let pixelWidth: Int
    let pixelHeight: Int
    let metadata: [CFString: Any]
    let sourceType: UTType
}

enum ImageLoader {
    static let supportedTypes: Set<UTType> = [.jpeg, .heic, .heif, .png]

    static func load(data: Data, sourceName: String = "Photo") throws -> ImageAsset {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let typeIdentifier = CGImageSourceGetType(source),
              let type = UTType(typeIdentifier as String),
              supportedTypes.contains(type) else {
            throw ImageEditorError.unsupportedFormat
        }
        guard let image = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            throw ImageEditorError.imageLoadFailed
        }

        let properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? Int(image.extent.width)
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? Int(image.extent.height)
        return ImageAsset(
            id: UUID(),
            sourceName: sourceName,
            fullResolutionImage: image,
            originalData: data,
            pixelWidth: width,
            pixelHeight: height,
            metadata: properties,
            sourceType: type
        )
    }

    static func load(url: URL) throws -> ImageAsset {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted { url.stopAccessingSecurityScopedResource() }
        }
        let data = try Data(contentsOf: url)
        return try load(data: data, sourceName: url.deletingPathExtension().lastPathComponent)
    }
}
