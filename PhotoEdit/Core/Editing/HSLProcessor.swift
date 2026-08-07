import CoreImage
import Foundation

/// Core Image 没有能正确隔离八个色相扇区的原生滤镜，故使用一个小型 CIColorKernel。
/// 每次仅在该色相通道存在非零参数时运行，并以柔和的 Hue/Saturation 权重避免色带边缘。
enum HSLProcessor {
    static func apply(_ adjustments: HSLAdjustments, to source: CIImage) throws -> CIImage {
        guard !adjustments.isIdentity else { return source }
        guard let kernel = selectiveKernel else { throw ImageEditorError.renderFailed }
        var image = source
        for channel in HSLChannel.allCases {
            let adjustment = adjustments[channel]
            guard !adjustment.isIdentity else { continue }
            guard let output = kernel.apply(extent: image.extent, arguments: [
                image,
                Float(channel.hueCenter),
                Float(adjustment.hue.clamped(to: -100...100) / 200),
                Float(adjustment.saturation.clamped(to: -100...100) / 100),
                Float(adjustment.luminance.clamped(to: -100...100) / 100)
            ]) else {
                throw ImageEditorError.renderFailed
            }
            image = output
        }
        return image
    }

    private static let selectiveKernel = CIColorKernel(source: """
    kernel vec4 selectiveHSL(__sample pixel, float targetHue, float hueShift, float saturationDelta, float luminanceDelta) {
        float maximum = max(pixel.r, max(pixel.g, pixel.b));
        float minimum = min(pixel.r, min(pixel.g, pixel.b));
        float chroma = maximum - minimum;
        float lightness = (maximum + minimum) * 0.5;
        float saturation = chroma < 0.00001 ? 0.0 : chroma / (1.0 - abs(2.0 * lightness - 1.0));
        float hue = 0.0;
        if (chroma > 0.00001) {
            if (maximum == pixel.r) { hue = (pixel.g - pixel.b) / chroma; }
            else if (maximum == pixel.g) { hue = 2.0 + (pixel.b - pixel.r) / chroma; }
            else { hue = 4.0 + (pixel.r - pixel.g) / chroma; }
            hue = fract(hue / 6.0);
        }
        float hueDistance = abs(fract(hue - targetHue + 0.5) - 0.5);
        float hueWeight = 1.0 - smoothstep(0.045, 0.18, hueDistance);
        float saturationWeight = smoothstep(0.02, 0.12, saturation);
        float weight = hueWeight * saturationWeight;
        hue = fract(hue + hueShift * weight);
        saturation = clamp(saturation + saturationDelta * weight, 0.0, 1.0);
        lightness = clamp(lightness + luminanceDelta * weight, 0.0, 1.0);

        float outputChroma = (1.0 - abs(2.0 * lightness - 1.0)) * saturation;
        float sector = hue * 6.0;
        float x = outputChroma * (1.0 - abs(fract(sector) * 2.0 - 1.0));
        vec3 rgb;
        if (sector < 1.0) { rgb = vec3(outputChroma, x, 0.0); }
        else if (sector < 2.0) { rgb = vec3(x, outputChroma, 0.0); }
        else if (sector < 3.0) { rgb = vec3(0.0, outputChroma, x); }
        else if (sector < 4.0) { rgb = vec3(0.0, x, outputChroma); }
        else if (sector < 5.0) { rgb = vec3(x, 0.0, outputChroma); }
        else { rgb = vec3(outputChroma, 0.0, x); }
        float match = lightness - outputChroma * 0.5;
        return vec4(rgb + match, pixel.a);
    }
    """)
}
