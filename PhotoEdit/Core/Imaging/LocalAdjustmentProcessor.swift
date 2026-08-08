import CoreGraphics
import CoreImage
import Foundation

enum LocalAdjustmentProcessor {
    private static let brushMaskCacheLimit = 16 * 1024 * 1024
    /// NSCache 的读写本身是线程安全的，缓存的 CIImage 也不可变；封装后避免把
    /// Foundation 的非 Sendable 类型直接作为全局可变状态暴露给 Swift 6。
    private final class BrushMaskCache: @unchecked Sendable {
        private let storage = NSCache<NSString, CIImage>()

        init() { storage.totalCostLimit = brushMaskCacheLimit }

        func mask(for key: NSString) -> CIImage? { storage.object(forKey: key) }
        func store(_ mask: CIImage, for key: NSString, cost: Int) { storage.setObject(mask, forKey: key, cost: cost) }
    }

    private static let brushMaskCache = BrushMaskCache()

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
        let width = max(1, Int(extent.width.rounded(.up)))
        let height = max(1, Int(extent.height.rounded(.up)))
        let key = brushCacheKey(brush, width: width, height: height)
        if let cached = brushMaskCache.mask(for: key) {
            return cached.transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY)).cropped(to: extent)
        }
        guard let raster = rasterizedBrushMask(brush, width: width, height: height) else {
            throw ImageEditorError.renderFailed
        }
        let mask = CIImage(cgImage: raster)
        let cost = width * height * 4
        if cost <= brushMaskCacheLimit {
            brushMaskCache.store(mask, for: key, cost: cost)
        }
        return mask.transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY)).cropped(to: extent)
    }

    /// 将归一化笔画一次栅格化为 alpha mask；调节曝光/对比度/饱和度只复用该 mask，
    /// 不再为每次 render 拼接最多 512 个 CIRadialGradient 节点。
    private static func rasterizedBrushMask(_ brush: BrushMask, width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))

        let shortEdge = CGFloat(min(width, height))
        let outerRadius = max(1, CGFloat(brush.size.clamped(to: 0.01...1)) * shortEdge / 2)
        let hardness = CGFloat(brush.hardness.clamped(to: 0...1))
        let opaque = CGColor(colorSpace: colorSpace, components: [1, 1, 1, 1])!
        let transparent = CGColor(colorSpace: colorSpace, components: [1, 1, 1, 0])!
        let gradient: CGGradient? = hardness >= 0.999 ? nil : CGGradient(
            colorsSpace: colorSpace,
            colors: [opaque, opaque, transparent] as CFArray,
            locations: [0, hardness, 1]
        )

        for point in brush.points {
            // Quartz bitmap context 与 CI 的未翻转坐标都以左下为原点；因此直接使用
            // 原始 normalized geometry，Preview 和 Export 会保持相同对齐。
            let center = CGPoint(x: CGFloat(point.x) * CGFloat(width), y: CGFloat(point.y) * CGFloat(height))
            if let gradient {
                context.drawRadialGradient(
                    gradient,
                    startCenter: center,
                    startRadius: 0,
                    endCenter: center,
                    endRadius: outerRadius,
                    options: []
                )
            } else {
                context.setFillColor(opaque)
                context.fillEllipse(in: CGRect(
                    x: center.x - outerRadius,
                    y: center.y - outerRadius,
                    width: outerRadius * 2,
                    height: outerRadius * 2
                ))
            }
        }
        return context.makeImage()
    }

    private static func brushCacheKey(_ brush: BrushMask, width: Int, height: Int) -> NSString {
        let points = brush.points.map { String(format: "%.6f,%.6f", $0.x, $0.y) }.joined(separator: ";")
        return "\(width)x\(height)|\(String(format: "%.6f", brush.size))|\(String(format: "%.6f", brush.hardness))|\(points)" as NSString
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
