import CoreGraphics
import CoreImage
import Foundation
import Metal

enum RenderMode: Sendable, Equatable {
    case preview(maximumDimension: Int)
    /// nil 表示原始输出尺寸；非 nil 时只在所有编辑完成后缩小。
    case export(maximumDimension: Int?)

    var maximumDimension: Int? {
        switch self {
        case let .preview(maximumDimension): maximumDimension
        case let .export(maximumDimension): maximumDimension
        }
    }
}

struct Histogram: Equatable, Sendable {
    static let binCount = 256
    var red: [Int]
    var green: [Int]
    var blue: [Int]
    var luminance: [Int]

    static let empty = Histogram(
        red: Array(repeating: 0, count: binCount),
        green: Array(repeating: 0, count: binCount),
        blue: Array(repeating: 0, count: binCount),
        luminance: Array(repeating: 0, count: binCount)
    )
}

/// 单例 actor 串行使用一个 Metal-backed CIContext，避免 Slider 变化反复分配 GPU context。
actor ImagePipeline {
    static let shared = ImagePipeline()

    /// SDR 编辑使用线性 sRGB；Extended Linear 作为明确的 LUT 边界保留，HDR 渲染在 Phase 6 单独开启。
    private let workingColorSpaceDescriptor = ColorSpaceDescriptor.linearSRGB
    private let outputColorSpaceDescriptor = ColorSpaceDescriptor.sRGB
    private let workingColorSpace = CGColorSpace(name: CGColorSpace.linearSRGB)!
    private let context: CIContext

    init() {
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: [
                .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!,
                .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
            ])
        } else {
            context = CIContext(options: [
                .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!,
                .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
            ])
        }
    }

    func render(
        image source: CIImage,
        state: EditState,
        lut: LUT?,
        technicalLUT: LUT? = nil,
        sourceColorSpace: ColorSpaceDescriptor = .sRGB,
        mode: RenderMode
    ) throws -> CGImage {
        try Task.checkCancellation()
        _ = try colorRenderPlan(source: sourceColorSpace, technicalLUT: technicalLUT, creativeLUT: lut)
        // CIContext 的工作/输出色彩空间负责系统级的图像色彩匹配。不要在图像图中
        // 再叠加 `matchedToWorkingSpace`：对无 ICC profile 的 CIImage 该 API 会生成黑帧。
        var image = normalizedExtent(source)
        if case let .preview(maximumDimension) = mode {
            image = downsample(image, maximumDimension: maximumDimension)
        }
        if let technicalLUT {
            image = try applyTechnicalLUT(technicalLUT, to: image)
        }
        image = try applyAdjustments(to: image, state: state)
        if let lut, state.lut.intensity > 0 {
            let lutImage = try applyCreativeLUT(lut, to: image)
            image = blend(base: image, lutImage: lutImage, amount: state.lut.intensity)
        }
        image = applyTransform(to: image, transform: state.transform)
        if case let .export(maximumDimension?) = mode {
            image = downsample(image, maximumDimension: maximumDimension)
        }
        try Task.checkCancellation()
        let extent = image.extent.integral
        guard !extent.isEmpty, let output = context.createCGImage(image, from: extent, format: .RGBA8, colorSpace: workingColorSpace) else {
            throw ImageEditorError.renderFailed
        }
        return output
    }

    func render(
        asset: ImageAsset,
        state: EditState,
        lut: LUT?,
        technicalLUT: LUT? = nil,
        mode: RenderMode,
        rawQuality: RAWRenderQuality? = nil
    ) throws -> CGImage {
        let source: CIImage
        if let raw = asset.rawSource {
            let quality: RAWRenderQuality
            if let rawQuality {
                quality = rawQuality
            } else {
                switch mode {
                case .preview:
                    quality = .fastPreview
                case .export:
                    // Resize happens after the full RAW pipeline; an export is never a draft decode.
                    quality = .fullResolution
                }
            }
            source = try raw.decode(adjustments: state.raw ?? RAWAdjustments(), quality: quality)
        } else {
            source = asset.fullResolutionImage
        }
        return try render(
            image: source,
            state: state,
            lut: lut,
            technicalLUT: technicalLUT,
            sourceColorSpace: asset.sourceColorSpace ?? .sRGB,
            mode: mode
        )
    }

    func colorRenderPlan(source: ColorSpaceDescriptor, technicalLUT: LUT?, creativeLUT: LUT?) throws -> ColorRenderPlan {
        if let technicalLUT {
            guard technicalLUT.kind == .technical else {
                throw ColorManagementError.invalidTechnicalLUT(name: technicalLUT.title ?? "未命名 LUT")
            }
            guard technicalLUT.colorMetadata.isComplete else {
                throw ColorManagementError.invalidTechnicalLUT(name: technicalLUT.title ?? "未命名 LUT")
            }
        }
        if let creativeLUT {
            guard creativeLUT.kind == .creative else {
                throw ColorManagementError.missingLUTMetadata(name: creativeLUT.title ?? "未命名 LUT")
            }
            guard creativeLUT.colorMetadata.isComplete else {
                throw ColorManagementError.missingLUTMetadata(name: creativeLUT.title ?? "未命名 LUT")
            }
        }
        return ColorRenderPlan(
            source: source,
            working: workingColorSpaceDescriptor,
            hasTechnicalTransform: technicalLUT != nil,
            hasCreativeLUT: creativeLUT != nil,
            output: outputColorSpaceDescriptor
        )
    }

    /// 直方图只读取下采样 Preview Source；不参与 Slider 的全分辨率渲染路径。
    func histogram(for source: CIImage, maximumDimension: Int = 512) throws -> Histogram {
        let image = downsample(normalizedExtent(source), maximumDimension: maximumDimension)
        guard let cgImage = context.createCGImage(image, from: image.extent.integral, format: .RGBA8, colorSpace: workingColorSpace),
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            throw ImageEditorError.renderFailed
        }
        var histogram = Histogram.empty
        let length = CFDataGetLength(data)
        let rowBytes = cgImage.bytesPerRow
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0, length >= rowBytes * height else { return histogram }
        for y in 0 ..< height {
            let row = bytes.advanced(by: y * rowBytes)
            for x in 0 ..< width {
                let pixel = row.advanced(by: x * 4)
                let red = Int(pixel[0])
                let green = Int(pixel[1])
                let blue = Int(pixel[2])
                let luminance = min(255, max(0, Int((0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue)).rounded())))
                histogram.red[red] += 1
                histogram.green[green] += 1
                histogram.blue[blue] += 1
                histogram.luminance[luminance] += 1
            }
        }
        return histogram
    }

    func histogram(for asset: ImageAsset, maximumDimension: Int = 512) throws -> Histogram {
        let source = try asset.rawSource?.decode(adjustments: RAWAdjustments(), quality: .fastPreview) ?? asset.fullResolutionImage
        return try histogram(for: source, maximumDimension: maximumDimension)
    }

    private func applyAdjustments(to source: CIImage, state: EditState) throws -> CIImage {
        var image = source
        image = try applyingFilter("CIExposureAdjust", to: image, values: [kCIInputEVKey: AdjustmentMapper.exposureEV(state.light.exposure)])
        image = try applyingFilter("CIHighlightShadowAdjust", to: image, values: [
            "inputHighlightAmount": AdjustmentMapper.highlightAmount(state.light.highlights),
            "inputShadowAmount": AdjustmentMapper.shadowAmount(state.light.shadows)
        ])
        image = try applyingFilter("CIColorControls", to: image, values: [
            kCIInputContrastKey: AdjustmentMapper.contrast(state.light.contrast),
            kCIInputSaturationKey: AdjustmentMapper.saturation(state.color.saturation)
        ])
        image = try applyingFilter("CITemperatureAndTint", to: image, values: [
            "inputNeutral": CIVector(x: 6500, y: 0),
            "inputTargetNeutral": CIVector(
                x: CGFloat(AdjustmentMapper.temperature(state.color.temperature)),
                y: CGFloat(AdjustmentMapper.tint(state.color.tint))
            )
        ])
        image = try applyingFilter("CIVibrance", to: image, values: ["inputAmount": AdjustmentMapper.vibrance(state.color.vibrance)])
        image = try HSLProcessor.apply(state.hsl, to: image)
        image = try ToneCurveProcessor.apply(state.curves, to: image, workingColorSpace: workingColorSpace)

        if state.detail.sharpness > 0 {
            image = try applyingFilter("CIUnsharpMask", to: image, values: [
                kCIInputRadiusKey: 2.5,
                kCIInputIntensityKey: AdjustmentMapper.sharpness(state.detail.sharpness)
            ])
        }
        if state.effects.vignette != 0 {
            image = try applyingFilter("CIVignette", to: image, values: [
                kCIInputIntensityKey: AdjustmentMapper.vignette(state.effects.vignette),
                kCIInputRadiusKey: 1.5
            ])
        }
        return image
    }

    private func applyTechnicalLUT(_ lut: LUT, to image: CIImage) throws -> CIImage {
        guard lut.colorMetadata.inputColorSpace != nil, lut.colorMetadata.outputColorSpace != nil else {
            throw ColorManagementError.invalidTechnicalLUT(name: lut.title ?? "未命名 LUT")
        }
        return try LUTProcessor.apply(lut, to: image)
    }

    private func applyCreativeLUT(_ lut: LUT, to image: CIImage) throws -> CIImage {
        guard lut.kind == .creative,
              lut.colorMetadata.inputColorSpace != nil,
              lut.colorMetadata.outputColorSpace != nil else {
            throw ColorManagementError.missingLUTMetadata(name: lut.title ?? "未命名 LUT")
        }
        return try LUTProcessor.apply(lut, to: image)
    }

    private func blend(base: CIImage, lutImage: CIImage, amount: Double) -> CIImage {
        let normalizedAmount = amount.clamped(to: 0...1)
        guard normalizedAmount < 1 else { return lutImage }
        let alphaAdjusted = lutImage.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(normalizedAmount))
        ])
        return alphaAdjusted.composited(over: base)
    }

    private func applyTransform(to source: CIImage, transform: TransformAdjustment) -> CIImage {
        var image = source
        switch transform.rotation {
        case 90: image = image.oriented(.right)
        case 180: image = image.oriented(.down)
        case 270: image = image.oriented(.left)
        default: break
        }
        image = normalizedExtent(image)
        if transform.horizontalFlip {
            let extent = image.extent
            image = image.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: extent.maxX + extent.minX, ty: 0))
            image = normalizedExtent(image)
        }
        return image.cropped(to: cropRect(for: image.extent, crop: transform.crop))
    }

    private func cropRect(for extent: CGRect, crop: CropState) -> CGRect {
        let raw = crop.normalizedRect.clamped()
        guard let ratio = crop.aspectRatio.ratio ?? (crop.aspectRatio == .original ? extent.width / extent.height : nil) else {
            return CGRect(
                x: extent.minX + extent.width * raw.x,
                y: extent.minY + extent.height * raw.y,
                width: extent.width * raw.width,
                height: extent.height * raw.height
            ).integral
        }

        let proposedWidth = extent.width * raw.width
        let proposedHeight = extent.height * raw.height
        var width = proposedWidth
        var height = width / ratio
        if height > proposedHeight {
            height = proposedHeight
            width = height * ratio
        }
        let centerX = extent.minX + extent.width * (raw.x + raw.width / 2)
        let centerY = extent.minY + extent.height * (raw.y + raw.height / 2)
        let x = min(max(centerX - width / 2, extent.minX), extent.maxX - width)
        let y = min(max(centerY - height / 2, extent.minY), extent.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height).integral
    }

    private func downsample(_ image: CIImage, maximumDimension: Int) -> CIImage {
        guard maximumDimension > 0 else { return image }
        let largest = max(image.extent.width, image.extent.height)
        guard largest > CGFloat(maximumDimension) else { return image }
        let scale = CGFloat(maximumDimension) / largest
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    private func normalizedExtent(_ image: CIImage) -> CIImage {
        image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }

    private func applyingFilter(_ name: String, to image: CIImage, values: [String: Any]) throws -> CIImage {
        guard let filter = CIFilter(name: name) else { throw ImageEditorError.renderFailed }
        filter.setValue(image, forKey: kCIInputImageKey)
        for (key, value) in values { filter.setValue(value, forKey: key) }
        guard let output = filter.outputImage else { throw ImageEditorError.renderFailed }
        return output
    }
}
