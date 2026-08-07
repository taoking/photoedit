import CoreImage
import Foundation

enum LocalAdjustmentProcessor {
    static func apply(_ localAdjustments: [LocalAdjustment], to source: CIImage) throws -> CIImage {
        try localAdjustments.filter { $0.isEnabled && !$0.adjustments.isIdentity }.reduce(source) { image, adjustment in
            let adjusted = try adjustedImage(from: image, values: adjustment.adjustments)
            let mask = try maskImage(for: adjustment.mask, extent: image.extent)
            guard let blend = CIFilter(name: "CIBlendWithAlphaMask") else { throw ImageEditorError.renderFailed }
            blend.setValue(adjusted, forKey: kCIInputImageKey)
            blend.setValue(image, forKey: kCIInputBackgroundImageKey)
            blend.setValue(mask, forKey: kCIInputMaskImageKey)
            guard let output = blend.outputImage else { throw ImageEditorError.renderFailed }
            return output
        }
    }

    private static func adjustedImage(from source: CIImage, values: LocalAdjustmentValues) throws -> CIImage {
        var image = source
        if values.exposure != 0 {
            image = try filter("CIExposureAdjust", image: image, values: [kCIInputEVKey: AdjustmentMapper.exposureEV(values.exposure)])
        }
        if values.contrast != 0 || values.saturation != 0 {
            image = try filter("CIColorControls", image: image, values: [
                kCIInputContrastKey: AdjustmentMapper.contrast(values.contrast),
                kCIInputSaturationKey: AdjustmentMapper.saturation(values.saturation)
            ])
        }
        return image
    }

    private static func maskImage(for mask: LocalMask, extent: CGRect) throws -> CIImage {
        switch mask {
        case let .linear(gradient):
            guard let filter = CIFilter(name: "CILinearGradient") else { throw ImageEditorError.renderFailed }
            filter.setValue(vector(gradient.start, in: extent), forKey: "inputPoint0")
            filter.setValue(vector(gradient.end, in: extent), forKey: "inputPoint1")
            filter.setValue(CIColor(red: 1, green: 1, blue: 1, alpha: 1), forKey: "inputColor0")
            filter.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: 0), forKey: "inputColor1")
            guard let output = filter.outputImage else { throw ImageEditorError.renderFailed }
            return output.cropped(to: extent)
        case let .radial(gradient):
            guard let filter = CIFilter(name: "CIRadialGradient") else { throw ImageEditorError.renderFailed }
            let shortEdge = min(extent.width, extent.height)
            let radius0 = max(0, gradient.radius) * shortEdge
            let radius1 = max(radius0 + 1, (gradient.radius + gradient.feather) * shortEdge)
            filter.setValue(vector(gradient.center, in: extent), forKey: kCIInputCenterKey)
            filter.setValue(radius0, forKey: "inputRadius0")
            filter.setValue(radius1, forKey: "inputRadius1")
            filter.setValue(CIColor(red: 1, green: 1, blue: 1, alpha: 1), forKey: "inputColor0")
            filter.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: 0), forKey: "inputColor1")
            guard let output = filter.outputImage else { throw ImageEditorError.renderFailed }
            return output.cropped(to: extent)
        case let .brush(brush):
            return try brushMask(brush, extent: extent)
        }
    }

    private static func brushMask(_ brush: BrushMask, extent: CGRect) throws -> CIImage {
        guard !brush.points.isEmpty else {
            return CIImage(color: .clear).cropped(to: extent)
        }
        let shortEdge = min(extent.width, extent.height)
        let outerRadius = max(1, brush.size.clamped(to: 0.01...1) * shortEdge / 2)
        let innerRadius = outerRadius * brush.hardness.clamped(to: 0...1)
        var result = CIImage(color: .clear).cropped(to: extent)
        for point in brush.points {
            guard let filter = CIFilter(name: "CIRadialGradient") else { throw ImageEditorError.renderFailed }
            filter.setValue(vector(point, in: extent), forKey: kCIInputCenterKey)
            filter.setValue(innerRadius, forKey: "inputRadius0")
            filter.setValue(outerRadius, forKey: "inputRadius1")
            filter.setValue(CIColor(red: 1, green: 1, blue: 1, alpha: 1), forKey: "inputColor0")
            filter.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: 0), forKey: "inputColor1")
            guard let stroke = filter.outputImage?.cropped(to: extent) else { throw ImageEditorError.renderFailed }
            result = stroke.composited(over: result).cropped(to: extent)
        }
        return result
    }

    private static func vector(_ point: NormalizedPoint, in extent: CGRect) -> CIVector {
        CIVector(
            x: extent.minX + extent.width * point.x,
            y: extent.minY + extent.height * point.y
        )
    }

    private static func filter(_ name: String, image: CIImage, values: [String: Any]) throws -> CIImage {
        guard let filter = CIFilter(name: name) else { throw ImageEditorError.renderFailed }
        filter.setValue(image, forKey: kCIInputImageKey)
        for (key, value) in values { filter.setValue(value, forKey: key) }
        guard let output = filter.outputImage else { throw ImageEditorError.renderFailed }
        return output
    }
}
