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
    /// ImageIO/CIImage 可识别时保留；无 profile 的标准照片会在读取时明确附着 sRGB fallback。
    let sourceColorSpace: ColorSpaceDescriptor?
    let rawSource: RAWImageSource?

    var isRAW: Bool { rawSource != nil }
    var cameraMetadata: CameraMetadata? { rawSource?.metadata }
}

enum ImageLoader {
    static let supportedTypes: Set<UTType> = [.jpeg, .heic, .heif, .png]
    static let rawExtensions: Set<String> = ["dng", "arw"]

    static func load(data: Data, sourceName: String = "Photo") throws -> ImageAsset {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let typeIdentifier = CGImageSourceGetType(source) else {
            throw ImageEditorError.unsupportedFormat
        }
        let properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        let type = UTType(typeIdentifier as String) ?? .data
        let extensionName = URL(fileURLWithPath: sourceName).pathExtension.lowercased()
        if rawExtensions.contains(extensionName) {
            let rawSource = RAWImageSource(data: data, identifierHint: type.identifier, metadata: RAWImageSource.metadata(from: properties))
            let image = try rawSource.decode(adjustments: RAWAdjustments(), quality: .fastPreview)
            return ImageAsset(
                id: UUID(), sourceName: sourceName, fullResolutionImage: image, originalData: data,
                pixelWidth: (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? Int(image.extent.width),
                pixelHeight: (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? Int(image.extent.height),
                metadata: properties, sourceType: type, sourceColorSpace: ColorSpaceDescriptor.detect(image.colorSpace), rawSource: rawSource
            )
        }
        guard supportedTypes.contains(type), let loadedImage = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            throw ImageEditorError.unsupportedFormat
        }
        let sourceColorSpace = ColorSpaceDescriptor.detect(loadedImage.colorSpace)
        let image: CIImage
        if sourceColorSpace == nil {
            guard let fallbackImage = CIImage(data: data, options: [
                .applyOrientationProperty: true,
                .colorSpace: ColorSpaceDescriptor.sRGB.cgColorSpace
            ]) else { throw ImageEditorError.imageLoadFailed }
            image = fallbackImage
        } else {
            image = loadedImage
        }
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
            sourceType: type,
            sourceColorSpace: sourceColorSpace ?? .sRGB,
            rawSource: nil
        )
    }

    static func load(url: URL) throws -> ImageAsset {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted { url.stopAccessingSecurityScopedResource() }
        }
        let data = try Data(contentsOf: url)
        return try load(data: data, sourceName: url.lastPathComponent)
    }
}
