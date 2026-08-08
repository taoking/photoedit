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

/// RAW bytes 保持不可变（与 ImageAsset 的 Data 使用 copy-on-write backing）；每一次
/// preview/export 都新建 CIRAWFilter，保证 Export 不会复用低质量 draft decode。
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
        // CIRAWFilter 在创建时已带入相机的 as-shot / decoder 白平衡。仅当用户确实
        // 修改了任一增量时才写回属性，避免 RAW 默认状态被错误重置到 6500 K / 0 tint。
        let whiteBalance = adjustments.whiteBalanceAdjustment
        if !whiteBalance.isIdentity {
            let resolved = whiteBalance.resolved(
                decoderTemperature: filter.neutralTemperature,
                decoderTint: filter.neutralTint
            )
            filter.neutralTemperature = resolved.temperature
            filter.neutralTint = resolved.tint
        }
        // 除曝光和相对 WB 外，RAW slider 的初始状态是「未覆盖」而非数值 0。只有用户
        // 实际移动滑杆或切换开关后才写入 CIRAWFilter，从而保留相机 / decoder 的默认 NR、
        // 锐化、细节、局部色调和镜头校正策略。
        let overrides = adjustments.decoderOverrides
        if filter.isLuminanceNoiseReductionSupported, let value = overrides.luminanceNoiseReduction {
            filter.luminanceNoiseReductionAmount = value
        }
        if filter.isColorNoiseReductionSupported, let value = overrides.colorNoiseReduction {
            filter.colorNoiseReductionAmount = value
        }
        if filter.isSharpnessSupported, let value = overrides.sharpness {
            filter.sharpnessAmount = value
        }
        if filter.isDetailSupported, let value = overrides.detail {
            filter.detailAmount = value
        }
        if filter.isLocalToneMapSupported, let value = overrides.localTone {
            filter.localToneMapAmount = value
        }
        if filter.isLensCorrectionSupported, let value = overrides.lensCorrectionEnabled {
            filter.isLensCorrectionEnabled = value
        }
        guard let output = filter.outputImage else { throw ImageEditorError.renderFailed }
        return output
    }

    static func metadata(from properties: [CFString: Any]) -> CameraMetadata {
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        return CameraMetadata(
            camera: tiff?[kCGImagePropertyTIFFModel] as? String,
            lens: exif?[kCGImagePropertyExifLensModel] as? String,
            aperture: (exif?[kCGImagePropertyExifFNumber] as? NSNumber)?.doubleValue,
            shutterSeconds: (exif?[kCGImagePropertyExifExposureTime] as? NSNumber)?.doubleValue,
            iso: (exif?[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber])?.first?.doubleValue,
            focalLength: (exif?[kCGImagePropertyExifFocalLength] as? NSNumber)?.doubleValue,
            captureDate: captureDate(exif: exif, tiff: tiff)
        )
    }

    /// EXIF/TIFF 日期为 `yyyy:MM:dd HH:mm:ss`，不是 ISO 8601。缺少时区时使用
    /// 系统本地时区解释墙上时间，绝不伪造成 UTC。
    static func captureDate(exif: [CFString: Any]?, tiff: [CFString: Any]?) -> Date? {
        let dateText = (exif?[kCGImagePropertyExifDateTimeOriginal] as? String)
            ?? (tiff?[kCGImagePropertyTIFFDateTime] as? String)
        guard let dateText else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.isLenient = false
        return formatter.date(from: dateText)
    }
}
