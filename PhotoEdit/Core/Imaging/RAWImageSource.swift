import CoreImage
import Foundation
import ImageIO

enum RAWRenderQuality: Sendable {
    case fastPreview
    case highQualityPreview
    case fullResolution
}

struct CameraMetadata: Codable, Equatable, Sendable {
    var camera: String?
    var lens: String?
    var aperture: Double?
    var shutterSeconds: Double?
    var iso: Double?
    var focalLength: Double?
    var captureDate: Date?
}

/// RAW bytes 保持不可变；每一次 preview/export 都新建 CIRAWFilter，保证 Export 不会复用低质量 draft decode。
struct RAWImageSource: @unchecked Sendable {
    let data: Data
    let identifierHint: String?
    let metadata: CameraMetadata

    func decode(adjustments: RAWAdjustments, quality: RAWRenderQuality) throws -> CIImage {
        guard let filter = CIRAWFilter(imageData: data, identifierHint: identifierHint) else {
            throw ImageEditorError.imageLoadFailed
        }
        switch quality {
        case .fastPreview:
            filter.isDraftModeEnabled = true
            filter.scaleFactor = 0.25
        case .highQualityPreview:
            filter.isDraftModeEnabled = false
            filter.scaleFactor = 0.5
        case .fullResolution:
            filter.isDraftModeEnabled = false
            filter.scaleFactor = 1
        }
        filter.exposure = Float(adjustments.exposure.clamped(to: -5...5))
        filter.neutralTemperature = Float((6500 + adjustments.temperature * 20).clamped(to: 2000...50000))
        filter.neutralTint = Float(adjustments.tint.clamped(to: -150...150))
        if filter.isLuminanceNoiseReductionSupported { filter.luminanceNoiseReductionAmount = Float(adjustments.luminanceNoiseReduction.clamped(to: 0...1)) }
        if filter.isColorNoiseReductionSupported { filter.colorNoiseReductionAmount = Float(adjustments.colorNoiseReduction.clamped(to: 0...1)) }
        if filter.isSharpnessSupported { filter.sharpnessAmount = Float(adjustments.sharpness.clamped(to: 0...1)) }
        if filter.isDetailSupported { filter.detailAmount = Float(adjustments.detail.clamped(to: 0...3)) }
        if filter.isLocalToneMapSupported { filter.localToneMapAmount = Float(adjustments.localTone.clamped(to: 0...1)) }
        if filter.isLensCorrectionSupported { filter.isLensCorrectionEnabled = adjustments.lensCorrectionEnabled }
        guard let output = filter.outputImage else { throw ImageEditorError.renderFailed }
        return output
    }

    static func metadata(from properties: [CFString: Any]) -> CameraMetadata {
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let dateFormatter = ISO8601DateFormatter()
        let dateText = exif?[kCGImagePropertyExifDateTimeOriginal] as? String
        return CameraMetadata(
            camera: tiff?[kCGImagePropertyTIFFModel] as? String,
            lens: exif?[kCGImagePropertyExifLensModel] as? String,
            aperture: (exif?[kCGImagePropertyExifFNumber] as? NSNumber)?.doubleValue,
            shutterSeconds: (exif?[kCGImagePropertyExifExposureTime] as? NSNumber)?.doubleValue,
            iso: (exif?[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber])?.first?.doubleValue,
            focalLength: (exif?[kCGImagePropertyExifFocalLength] as? NSNumber)?.doubleValue,
            captureDate: dateText.flatMap { dateFormatter.date(from: $0.replacingOccurrences(of: " ", with: "T")) }
        )
    }
}
