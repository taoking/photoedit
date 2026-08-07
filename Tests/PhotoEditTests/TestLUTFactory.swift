@testable import PhotoEdit

enum TestLUTFactory {
    static func identityText(dimension: Int, title: String? = nil, includeDomain: Bool = false) -> String {
        var lines: [String] = []
        if let title { lines.append("TITLE \"\(title)\"") }
        lines.append("LUT_3D_SIZE \(dimension)")
        if includeDomain {
            lines.append("DOMAIN_MIN 0.0 0.0 0.0")
            lines.append("DOMAIN_MAX 1.0 1.0 1.0")
        }
        for blue in 0 ..< dimension {
            for green in 0 ..< dimension {
                for red in 0 ..< dimension {
                    lines.append("\(Float(red) / Float(dimension - 1)) \(Float(green) / Float(dimension - 1)) \(Float(blue) / Float(dimension - 1))")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    static func identityLUT(dimension: Int = 17) -> LUT {
        try! CUBEParser.parse(text: identityText(dimension: dimension))
            .configured(kind: .creative, colorMetadata: .sRGB)
    }
}
