import CoreImage
import Foundation

/// 任意数量控制点经 CPU 采样为 64³ Color Cube；避免把控制点数量限制为系统 `CIToneCurve` 的五点。
enum ToneCurveProcessor {
    private static let cubeDimension = 64

    static func apply(_ curves: ToneCurveAdjustments, to image: CIImage, workingColorSpace: CGColorSpace) throws -> CIImage {
        guard !curves.isIdentity else { return image }
        guard let filter = CIFilter(name: "CIColorCubeWithColorSpace") else { throw ImageEditorError.renderFailed }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(cubeDimension, forKey: "inputCubeDimension")
        filter.setValue(cubeData(for: curves), forKey: "inputCubeData")
        filter.setValue(workingColorSpace, forKey: "inputColorSpace")
        guard let output = filter.outputImage else { throw ImageEditorError.renderFailed }
        return output
    }

    private static func cubeData(for curves: ToneCurveAdjustments) -> Data {
        var rgba = [Float]()
        rgba.reserveCapacity(cubeDimension * cubeDimension * cubeDimension * 4)
        let divisor = Double(cubeDimension - 1)
        for blue in 0 ..< cubeDimension {
            for green in 0 ..< cubeDimension {
                for red in 0 ..< cubeDimension {
                    let masterRed = curves.master.value(at: Double(red) / divisor)
                    let masterGreen = curves.master.value(at: Double(green) / divisor)
                    let masterBlue = curves.master.value(at: Double(blue) / divisor)
                    rgba.append(Float(curves.red.value(at: masterRed)))
                    rgba.append(Float(curves.green.value(at: masterGreen)))
                    rgba.append(Float(curves.blue.value(at: masterBlue)))
                    rgba.append(1)
                }
            }
        }
        return rgba.withUnsafeBufferPointer(Data.init(buffer:))
    }
}
