import Foundation

/// 编辑预览的单一几何约定：图片始终先在可见画布内等比适配，再以该矩形计算缩放和平移边界。
struct PreviewGeometry {
    static func aspectFitSize(imageSize: CGSize, in canvasSize: CGSize) -> CGSize {
        guard imageSize.width.isFinite,
              imageSize.height.isFinite,
              canvasSize.width.isFinite,
              canvasSize.height.isFinite,
              imageSize.width > 0,
              imageSize.height > 0,
              canvasSize.width > 0,
              canvasSize.height > 0 else {
            return .zero
        }

        let scale = Swift.min(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
        guard scale.isFinite, scale > 0 else { return .zero }
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    static func maximumPan(fittedImageSize: CGSize, in canvasSize: CGSize, zoom: CGFloat) -> CGSize {
        guard fittedImageSize.width.isFinite,
              fittedImageSize.height.isFinite,
              canvasSize.width.isFinite,
              canvasSize.height.isFinite,
              zoom.isFinite,
              fittedImageSize.width > 0,
              fittedImageSize.height > 0,
              canvasSize.width > 0,
              canvasSize.height > 0 else {
            return .zero
        }

        let effectiveZoom = Swift.max(1, zoom)
        return CGSize(
            width: Swift.max(0, (fittedImageSize.width * effectiveZoom - canvasSize.width) / 2),
            height: Swift.max(0, (fittedImageSize.height * effectiveZoom - canvasSize.height) / 2)
        )
    }

    static func clampedPan(_ candidate: CGSize, fittedImageSize: CGSize, in canvasSize: CGSize, zoom: CGFloat) -> CGSize {
        guard candidate.width.isFinite, candidate.height.isFinite else { return .zero }
        let maximum = maximumPan(fittedImageSize: fittedImageSize, in: canvasSize, zoom: zoom)
        return CGSize(
            width: Swift.min(Swift.max(candidate.width, -maximum.width), maximum.width),
            height: Swift.min(Swift.max(candidate.height, -maximum.height), maximum.height)
        )
    }
}
