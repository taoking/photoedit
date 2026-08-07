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

    static func apply(_ lut: LUT, to image: CIImage, workingColorSpace: CGColorSpace) throws -> CIImage {
        guard let filter = CIFilter(name: "CIColorCubeWithColorSpace") else {
            throw ImageEditorError.renderFailed
        }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(lut.dimension, forKey: "inputCubeDimension")
        filter.setValue(colorCubeData(for: lut), forKey: "inputCubeData")
        filter.setValue(workingColorSpace, forKey: "inputColorSpace")
        guard let output = filter.outputImage else { throw ImageEditorError.renderFailed }
        return output
    }
}
