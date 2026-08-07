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
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(lut.dimension, forKey: "inputCubeDimension")
        filter.setValue(colorCubeData(for: lut), forKey: "inputCubeData")
        filter.setValue(outputColorSpace.cgColorSpace, forKey: "inputColorSpace")
        guard let output = filter.outputImage else { throw ImageEditorError.renderFailed }
        return output
    }
}
