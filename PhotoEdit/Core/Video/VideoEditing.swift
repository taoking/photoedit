import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import Metal

/// 视频有独立的渲染和导出链。它只共享 LUT 数据模型，绝不借用静态照片的 ImagePipeline。
struct VideoEditState: Codable, Equatable, Sendable {
    var exposure: Double = 0
    var contrast: Double = 0
    var saturation: Double = 0
    var selectedLUTID: UUID?
    /// 0…1；零强度时不构建 LUT 滤镜。
    var lutIntensity: Double = 1

    var isIdentity: Bool {
        exposure == 0 && contrast == 0 && saturation == 0 && selectedLUTID == nil
    }
}

struct VideoFrameTransform: Equatable, Sendable {
    let a: CGFloat
    let b: CGFloat
    let c: CGFloat
    let d: CGFloat
    let tx: CGFloat
    let ty: CGFloat

    init(_ transform: CGAffineTransform) {
        a = transform.a
        b = transform.b
        c = transform.c
        d = transform.d
        tx = transform.tx
        ty = transform.ty
    }

    var affineTransform: CGAffineTransform {
        CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
    }
}

struct VideoAsset: Equatable, Sendable {
    /// 文件导入后立即复制到应用临时目录，避免 File Provider 授权在导出途中失效。
    let sourceURL: URL
    let sourceName: String
    let durationSeconds: Double
    let width: Int
    let height: Int
    let frameTransform: VideoFrameTransform

    static func importFromFile(url: URL) async throws -> VideoAsset {
        let copiedURL = try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let accessGranted = url.startAccessingSecurityScopedResource()
            defer {
                if accessGranted { url.stopAccessingSecurityScopedResource() }
            }
            let directory = fileManager.temporaryDirectory
                .appendingPathComponent("PhotoEdit", isDirectory: true)
                .appendingPathComponent("VideoImports", isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
            let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
            try fileManager.copyItem(at: url, to: destination)
            return destination
        }.value

        do {
            let asset = AVURLAsset(url: copiedURL)
            let duration = try await asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard duration.isNumeric, duration.seconds.isFinite, duration.seconds > 0,
                  let track = tracks.first else {
                throw VideoEditorError.noVideoTrack
            }
            let size = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let formatDescriptions = try await track.load(.formatDescriptions)
            guard !containsHDRTransferFunction(formatDescriptions) else { throw VideoEditorError.unsupportedHDRVideo }
            guard size.width > 0, size.height > 0 else { throw VideoEditorError.noVideoTrack }
            return VideoAsset(
                sourceURL: copiedURL,
                sourceName: url.lastPathComponent,
                durationSeconds: duration.seconds,
                width: Int(size.width.rounded()),
                height: Int(size.height.rounded()),
                frameTransform: VideoFrameTransform(transform)
            )
        } catch {
            try? FileManager.default.removeItem(at: copiedURL)
            throw error
        }
    }

    private static func containsHDRTransferFunction(_ descriptions: [CMFormatDescription]) -> Bool {
        let hdrFunctions = [
            kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String,
            kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String
        ]
        return descriptions.contains { description in
            guard let extensions = CMFormatDescriptionGetExtensions(description) as NSDictionary? else { return false }
            guard let transferFunction = extensions[kCMFormatDescriptionExtension_TransferFunction] as? String else { return false }
            return hdrFunctions.contains(transferFunction)
        }
    }
}

struct ExportedVideo: Equatable, Sendable {
    let fileURL: URL
    let fileType: AVFileType

    var filename: String { "Video-edited.\(fileURL.pathExtension)" }
}

enum VideoEditorError: LocalizedError, Sendable {
    case noVideoTrack
    case unsupportedHDRVideo
    case unsupportedLUTColorSpace(name: String)
    case cannotCreateExporter
    case unsupportedExportFileType

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: "该文件没有可编辑的视频轨道。"
        case .unsupportedHDRVideo: "当前视频工作流仅支持 SDR 视频；HDR HLG/PQ 视频需要单独的色彩与动态范围导出策略。"
        case let .unsupportedLUTColorSpace(name): "视频 LUT“\(name)”必须声明为 sRGB → sRGB，才能安全用于当前 SDR 视频工作流。"
        case .cannotCreateExporter: "无法创建视频导出器。"
        case .unsupportedExportFileType: "此视频无法导出为 MP4 或 MOV。"
        }
    }
}

private final class VideoRenderContext: @unchecked Sendable {
    let context: CIContext

    init() {
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: [
                .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
            ])
        } else {
            context = CIContext(options: [
                .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
            ])
        }
    }
}

enum VideoFrameProcessor {
    static func videoComposition(asset: AVAsset, state: VideoEditState, lut: LUT?, transform: VideoFrameTransform) -> AVVideoComposition {
        let renderContext = VideoRenderContext()
        return AVVideoComposition(asset: asset) { request in
            do {
                let output = try apply(request.sourceImage, state: state, lut: lut, transform: transform)
                request.finish(with: output, context: renderContext.context)
            } catch {
                request.finish(with: error)
            }
        }
    }

    static func apply(_ source: CIImage, state: VideoEditState, lut: LUT?, transform: VideoFrameTransform? = nil) throws -> CIImage {
        var image = source
        if state.exposure != 0 {
            image = try filter("CIExposureAdjust", image: image, values: [kCIInputEVKey: AdjustmentMapper.exposureEV(state.exposure)])
        }
        if state.contrast != 0 || state.saturation != 0 {
            image = try filter("CIColorControls", image: image, values: [
                kCIInputContrastKey: AdjustmentMapper.contrast(state.contrast),
                kCIInputSaturationKey: AdjustmentMapper.saturation(state.saturation)
            ])
        }
        if let lut, state.lutIntensity > 0 {
            let lutImage = try LUTProcessor.apply(lut, to: image)
            image = blend(base: image, lutImage: lutImage, amount: state.lutIntensity)
        }
        if let transform {
            let transformed = image.transformed(by: transform.affineTransform)
            image = transformed.transformed(by: CGAffineTransform(translationX: -transformed.extent.minX, y: -transformed.extent.minY))
        }
        return image
    }

    private static func filter(_ name: String, image: CIImage, values: [String: Any]) throws -> CIImage {
        guard let filter = CIFilter(name: name) else { throw ImageEditorError.renderFailed }
        filter.setValue(image, forKey: kCIInputImageKey)
        for (key, value) in values { filter.setValue(value, forKey: key) }
        guard let output = filter.outputImage else { throw ImageEditorError.renderFailed }
        return output
    }

    private static func blend(base: CIImage, lutImage: CIImage, amount: Double) -> CIImage {
        let normalizedAmount = amount.clamped(to: 0...1)
        guard normalizedAmount < 1 else { return lutImage }
        return lutImage.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(normalizedAmount))
        ]).composited(over: base)
    }
}

enum VideoExporter {
    static func export(asset videoAsset: VideoAsset, state: VideoEditState, lut: LUT?) async throws -> ExportedVideo {
        if let lut,
           (lut.kind != .creative || lut.colorMetadata.inputColorSpace != .sRGB || lut.colorMetadata.outputColorSpace != .sRGB) {
            throw VideoEditorError.unsupportedLUTColorSpace(name: lut.title ?? "未命名 LUT")
        }
        let asset = AVURLAsset(url: videoAsset.sourceURL)
        _ = try await asset.load(.duration)
        _ = try await asset.loadTracks(withMediaType: .video)
        let composition = VideoFrameProcessor.videoComposition(
            asset: asset,
            state: state,
            lut: lut,
            transform: videoAsset.frameTransform
        )
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw VideoEditorError.cannotCreateExporter
        }
        let fileType: AVFileType
        if session.supportedFileTypes.contains(.mp4) {
            fileType = .mp4
        } else if session.supportedFileTypes.contains(.mov) {
            fileType = .mov
        } else {
            throw VideoEditorError.unsupportedExportFileType
        }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileType == .mp4 ? "mp4" : "mov")
        session.videoComposition = composition
        session.shouldOptimizeForNetworkUse = true
        try await session.export(to: outputURL, as: fileType)
        return ExportedVideo(fileURL: outputURL, fileType: fileType)
    }
}
