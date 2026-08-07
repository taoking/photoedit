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

/// 单例 actor 串行使用一个 Metal-backed CIContext，避免 Slider 变化反复分配 GPU context。
actor ImagePipeline {
    static let shared = ImagePipeline()

    private let workingColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let context: CIContext

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

    func render(image source: CIImage, state: EditState, lut: LUT?, mode: RenderMode) throws -> CGImage {
        try Task.checkCancellation()
        var image = normalizedExtent(source)
        if case let .preview(maximumDimension) = mode {
            image = downsample(image, maximumDimension: maximumDimension)
        }
        image = try applyAdjustments(to: image, state: state, lut: lut)
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

    private func applyAdjustments(to source: CIImage, state: EditState, lut: LUT?) throws -> CIImage {
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

        if let lut, state.lut.intensity > 0 {
            let lutImage = try LUTProcessor.apply(lut, to: image, workingColorSpace: workingColorSpace)
            image = blend(base: image, lutImage: lutImage, amount: state.lut.intensity)
        }
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
