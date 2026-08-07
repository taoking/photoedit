import CoreGraphics
import Foundation
import ImageIO
import Photos
import SwiftUI
import UniformTypeIdentifiers

enum ExportFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case jpeg
    case heif

    var id: String { rawValue }
    var title: String { self == .jpeg ? "JPEG" : "HEIF" }
    var utType: UTType { self == .jpeg ? .jpeg : .heic }
    var fileExtension: String { self == .jpeg ? "jpg" : "heic" }
}

enum ExportFilenameStrategy: String, Codable, CaseIterable, Identifiable, Sendable {
    /// 保留原始基础名称，并加上 -edited 标记。
    case originalEdited
    /// 保留原始基础名称，适合已在独立导出目录中管理的照片。
    case original
    /// 以可配置前缀和连续序号命名，避免同名来源互相混淆。
    case sequential

    var id: String { rawValue }

    var title: String {
        switch self {
        case .originalEdited: "原名 - edited"
        case .original: "仅原名"
        case .sequential: "连续编号"
        }
    }
}

struct ExportSettings: Codable, Equatable, Sendable {
    var format: ExportFormat = .jpeg
    /// nil 表示原始分辨率。
    var maximumDimension: Int?
    var jpegQuality: Double = 0.9
    var keepLocation: Bool = true
    var filenameStrategy: ExportFilenameStrategy = .originalEdited
    var filenamePrefix = "PhotoEdit"

    func filename(for sourceName: String, sequenceNumber: Int? = nil) -> String {
        let baseName = ImageExporter.sanitizedFilename(URL(fileURLWithPath: sourceName).deletingPathExtension().lastPathComponent)
        let stem: String
        switch filenameStrategy {
        case .originalEdited:
            stem = baseName + "-edited"
        case .original:
            stem = baseName
        case .sequential:
            let prefix = ImageExporter.sanitizedFilename(filenamePrefix.trimmingCharacters(in: .whitespacesAndNewlines))
            let ordinal = sequenceNumber ?? 1
            stem = "\(prefix)-\(String(format: "%03d", ordinal))"
        }
        return stem + ".\(format.fileExtension)"
    }
}

struct ExportedImage: @unchecked Sendable {
    let data: Data
    let fileURL: URL
    let type: UTType
    let filename: String
}

enum ImageExporter {
    static func export(
        asset: ImageAsset,
        state: EditState,
        lut: LUT?,
        technicalLUT: LUT? = nil,
        settings: ExportSettings,
        sequenceNumber: Int? = nil,
        pipeline: ImagePipeline = .shared
    ) async throws -> ExportedImage {
        let image = try await pipeline.render(
            asset: asset,
            state: state,
            lut: lut,
            technicalLUT: technicalLUT,
            mode: .export(maximumDimension: settings.maximumDimension)
        )
        try Task.checkCancellation()

        let data = try encode(image: image, asset: asset, settings: settings)
        let filename = settings.filename(for: asset.sourceName, sequenceNumber: sequenceNumber)
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(settings.format.fileExtension)
        try data.write(to: destination, options: .atomic)
        return ExportedImage(data: data, fileURL: destination, type: settings.format.utType, filename: filename)
    }

    private static func encode(image: CGImage, asset: ImageAsset, settings: ExportSettings) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, settings.format.utType.identifier as CFString, 1, nil) else {
            throw ImageEditorError.exportFailed
        }
        var metadata = asset.metadata
        if !settings.keepLocation {
            metadata.removeValue(forKey: kCGImagePropertyGPSDictionary)
        }
        metadata[kCGImageDestinationLossyCompressionQuality] = settings.jpegQuality.clamped(to: 0.8...1)
        CGImageDestinationAddImage(destination, image, metadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageEditorError.exportFailed }
        return data as Data
    }

    static func sanitizedFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\")
        let result = name.components(separatedBy: invalid).joined(separator: "-")
        return result.isEmpty ? "Photo" : result
    }
}

struct ImageExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.jpeg, .heic] }
    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum PhotoLibrarySaver {
    static func save(data: Data, type: UTType) async throws {
        let status = await requestAuthorization()
        guard status == .authorized || status == .limited else { throw ImageEditorError.permissionDenied }
        try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            } completionHandler: { success, error in
                if success { continuation.resume() }
                else { continuation.resume(throwing: error ?? ImageEditorError.exportFailed) }
            }
        }
    }

    private static func requestAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }
}
