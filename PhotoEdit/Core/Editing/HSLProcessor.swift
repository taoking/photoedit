import CoreImage
import Foundation

/// 八个通道必须基于同一个原始像素完成分类与合成。若逐通道串行执行，前一通道
/// 改变后的 hue 会被后一通道重新分类，结果会依赖通道顺序并产生可见串色。
enum HSLProcessor {
    static func apply(_ adjustments: HSLAdjustments, to source: CIImage) throws -> CIImage {
        let adjustments = adjustments.canonicalized()
        guard !adjustments.isIdentity else { return source }
        guard let kernel = selectiveKernel else { throw ImageEditorError.renderFailed }
        let vectors = HSLChannel.allCases.map { channel -> CIVector in
            let adjustment = adjustments[channel]
            return CIVector(
                x: adjustment.hue / 200,
                y: adjustment.saturation / 100,
                z: adjustment.luminance / 100,
                w: 0
            )
        }
        guard let output = kernel.apply(extent: source.extent, arguments: [source] + vectors) else {
            throw ImageEditorError.renderFailed
        }
        return output
    }

    private static let selectiveKernel = CIColorKernel(source: """
    float hslLinearToSRGB(float value) {
        float magnitude = abs(value);
        float encoded = magnitude <= 0.0031308
            ? magnitude * 12.92
            : 1.055 * pow(magnitude, 1.0 / 2.4) - 0.055;
        return value < 0.0 ? -encoded : encoded;
    }

    float hslSRGBToLinear(float value) {
        float magnitude = abs(value);
        float linear = magnitude <= 0.04045
            ? magnitude / 12.92
            : pow((magnitude + 0.055) / 1.055, 2.4);
        return value < 0.0 ? -linear : linear;
    }

    float hslHueWeight(float hue, float center) {
        float distance = abs(fract(hue - center + 0.5) - 0.5);
        return 1.0 - smoothstep(0.025, 0.125, distance);
    }

    float hslIsActive(vec4 adjustment) {
        return abs(adjustment.x) + abs(adjustment.y) + abs(adjustment.z) > 0.000001 ? 1.0 : 0.0;
    }

    kernel vec4 selectiveHSL(
        __sample pixel,
        vec4 redAdjustment,
        vec4 orangeAdjustment,
        vec4 yellowAdjustment,
        vec4 greenAdjustment,
        vec4 aquaAdjustment,
        vec4 blueAdjustment,
        vec4 purpleAdjustment,
        vec4 magentaAdjustment
    ) {
        vec3 encoded = vec3(
            hslLinearToSRGB(pixel.r),
            hslLinearToSRGB(pixel.g),
            hslLinearToSRGB(pixel.b)
        );

        // SDR 基础调整仍可能产生 >1 headroom。分类时按峰值归一化，调整完成后
        // 再恢复原始峰值；负分量作为 residual 保留，不能被无条件 clamp 掉。
        float peak = max(1.0, max(encoded.r, max(encoded.g, encoded.b)));
        vec3 analysisRGB = clamp(encoded / peak, 0.0, 1.0);
        vec3 residual = encoded - analysisRGB * peak;

        float maximum = max(analysisRGB.r, max(analysisRGB.g, analysisRGB.b));
        float minimum = min(analysisRGB.r, min(analysisRGB.g, analysisRGB.b));
        float chroma = maximum - minimum;
        float lightness = (maximum + minimum) * 0.5;
        float saturationDenominator = max(0.00001, 1.0 - abs(2.0 * lightness - 1.0));
        float saturation = chroma < 0.00001 ? 0.0 : chroma / saturationDenominator;
        float hue = 0.0;
        if (chroma > 0.00001) {
            if (maximum == analysisRGB.r) { hue = (analysisRGB.g - analysisRGB.b) / chroma; }
            else if (maximum == analysisRGB.g) { hue = 2.0 + (analysisRGB.b - analysisRGB.r) / chroma; }
            else { hue = 4.0 + (analysisRGB.r - analysisRGB.g) / chroma; }
            hue = fract(hue / 6.0);
        }

        float saturationWeight = smoothstep(0.02, 0.12, saturation);
        float redWeight = hslHueWeight(hue, 0.0) * saturationWeight * hslIsActive(redAdjustment);
        float orangeWeight = hslHueWeight(hue, 30.0 / 360.0) * saturationWeight * hslIsActive(orangeAdjustment);
        float yellowWeight = hslHueWeight(hue, 60.0 / 360.0) * saturationWeight * hslIsActive(yellowAdjustment);
        float greenWeight = hslHueWeight(hue, 120.0 / 360.0) * saturationWeight * hslIsActive(greenAdjustment);
        float aquaWeight = hslHueWeight(hue, 180.0 / 360.0) * saturationWeight * hslIsActive(aquaAdjustment);
        float blueWeight = hslHueWeight(hue, 240.0 / 360.0) * saturationWeight * hslIsActive(blueAdjustment);
        float purpleWeight = hslHueWeight(hue, 270.0 / 360.0) * saturationWeight * hslIsActive(purpleAdjustment);
        float magentaWeight = hslHueWeight(hue, 330.0 / 360.0) * saturationWeight * hslIsActive(magentaAdjustment);
        float activeWeight = redWeight + orangeWeight + yellowWeight + greenWeight
            + aquaWeight + blueWeight + purpleWeight + magentaWeight;
        float normalizer = max(1.0, activeWeight);

        vec4 combined = (
            redAdjustment * redWeight
            + orangeAdjustment * orangeWeight
            + yellowAdjustment * yellowWeight
            + greenAdjustment * greenWeight
            + aquaAdjustment * aquaWeight
            + blueAdjustment * blueWeight
            + purpleAdjustment * purpleWeight
            + magentaAdjustment * magentaWeight
        ) / normalizer;

        // 非目标像素必须逐值保持原样，尤其不能仅因某个别的通道启用就重建并裁切。
        if (abs(combined.x) + abs(combined.y) + abs(combined.z) < 0.000001) {
            return pixel;
        }

        hue = fract(hue + combined.x);
        saturation = clamp(saturation + combined.y, 0.0, 1.0);
        lightness = clamp(lightness + combined.z, 0.0, 1.0);

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
        vec3 adjustedEncoded = (rgb + match) * peak + residual;
        return vec4(
            hslSRGBToLinear(adjustedEncoded.r),
            hslSRGBToLinear(adjustedEncoded.g),
            hslSRGBToLinear(adjustedEncoded.b),
            pixel.a
        );
    }
    """)
}
