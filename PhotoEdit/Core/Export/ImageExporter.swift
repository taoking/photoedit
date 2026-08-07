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

struct ExportSettings: Codable, Equatable, Sendable {
    var format: ExportFormat = .jpeg
    /// nil 表示原始分辨率。
    var maximumDimension: Int?
    var jpegQuality: Double = 0.9
    var keepLocation: Bool = true
}

struct ExportedImage {
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
        settings: ExportSettings,
        pipeline: ImagePipeline = .shared
    ) async throws -> ExportedImage {
        let image = try await pipeline.render(
            image: asset.fullResolutionImage,
            state: state,
            lut: lut,
            mode: .export(maximumDimension: settings.maximumDimension)
        )
        try Task.checkCancellation()

        let data = try encode(image: image, asset: asset, settings: settings)
        let filename = sanitizedFilename(asset.sourceName) + "-edited.\(settings.format.fileExtension)"
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

    private static func sanitizedFilename(_ name: String) -> String {
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
