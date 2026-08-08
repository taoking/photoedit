import CoreImage
import Foundation

enum LUTProcessor {
    /// Core Image cube bytes are RGBA float32 and use the same red-fastest ordering as .cube files.
    static func colorCubeData(for lut: LUT) -> Data {
        var rgba = [Float]()
        rgba.reserveCapacity(lut.values.count * 4)
        for value in lut.values {
            rgba.append(value.red)
            rgba.append(value.green)
            rgba.append(value.blue)
            rgba.append(1)
        }
        return rgba.withUnsafeBufferPointer(Data.init(buffer:))
    }

    /// `CIColorCubeWithColorSpace.colorSpace` 是 cube 数据的工作色彩空间。
    /// `.cube` 的 texel 是映射后的 RGB 值，因此使用已声明的输出空间；输入空间
    /// 则作为 Technical LUT 的显式匹配约束保存在 metadata 中并由调用方验证。
    static func apply(_ lut: LUT, to image: CIImage) throws -> CIImage {
        guard lut.colorMetadata.inputColorSpace != nil,
              let outputColorSpace = lut.colorMetadata.outputColorSpace else {
            throw ColorManagementError.missingLUTMetadata(name: lut.title ?? "未命名 LUT")
        }
        guard let filter = CIFilter(name: "CIColorCubeWithColorSpace") else {
            throw ImageEditorError.renderFailed
        }
        // .cube 的 DOMAIN_MIN/MAX 描述输入坐标域。CIColorCube 固定接收 0...1，
        // 因此先逐通道归一化；不能只解析 DOMAIN 却忽略它。
        filter.setValue(try domainNormalized(image, for: lut), forKey: kCIInputImageKey)
        filter.setValue(lut.dimension, forKey: "inputCubeDimension")
        filter.setValue(colorCubeData(for: lut), forKey: "inputCubeData")
        filter.setValue(outputColorSpace.cgColorSpace, forKey: "inputColorSpace")
        guard let output = filter.outputImage else { throw ImageEditorError.renderFailed }
        return output
    }

    private static func domainNormalized(_ image: CIImage, for lut: LUT) throws -> CIImage {
        let range = RGBColor(
            red: lut.domainMax.red - lut.domainMin.red,
            green: lut.domainMax.green - lut.domainMin.green,
            blue: lut.domainMax.blue - lut.domainMin.blue
        )
        guard range.red > 0, range.green > 0, range.blue > 0 else {
            throw CUBEParserError.invalidDomain
        }
        guard let filter = CIFilter(name: "CIColorMatrix") else { throw ImageEditorError.renderFailed }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: 1 / CGFloat(range.red), y: 0, z: 0, w: 0), forKey: "inputRVector")
        filter.setValue(CIVector(x: 0, y: 1 / CGFloat(range.green), z: 0, w: 0), forKey: "inputGVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 1 / CGFloat(range.blue), w: 0), forKey: "inputBVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        filter.setValue(CIVector(
            x: -CGFloat(lut.domainMin.red) / CGFloat(range.red),
            y: -CGFloat(lut.domainMin.green) / CGFloat(range.green),
            z: -CGFloat(lut.domainMin.blue) / CGFloat(range.blue),
            w: 0
        ), forKey: "inputBiasVector")
        guard let output = filter.outputImage else { throw ImageEditorError.renderFailed }
        return output
    }
}
