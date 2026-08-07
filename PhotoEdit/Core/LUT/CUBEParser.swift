import Foundation

enum CUBEParserError: LocalizedError, Equatable {
    case missingDimension
    case unsupportedDimension(Int)
    case invalidDirective(line: Int)
    case invalidValue(line: Int)
    case incorrectValueCount(expected: Int, actual: Int)
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .missingDimension:
            "LUT 文件缺少 LUT_3D_SIZE。"
        case let .unsupportedDimension(size):
            "不支持 \(size)³ LUT；目前支持 17³、33³ 和 65³。"
        case let .invalidDirective(line):
            "第 \(line) 行的 LUT 指令无效。"
        case let .invalidValue(line):
            "第 \(line) 行的 RGB 数值无效。"
        case let .incorrectValueCount(expected, actual):
            "LUT 应有 \(expected) 个颜色值，实际有 \(actual) 个。"
        case .unsupportedFormat:
            "仅支持 3D .cube LUT。"
        }
    }
}
enum CUBEParser {
    static let supportedDimensions: Set<Int> = [17, 33, 65]

    static func parse(data: Data) throws -> LUT {
        guard let text = String(data: data, encoding: .utf8) else {
            throw CUBEParserError.unsupportedFormat
        }
        return try parse(text: text)
    }

    static func parse(text: String) throws -> LUT {
        var title: String?
        var dimension: Int?
        var domainMin = RGBColor(red: 0, green: 0, blue: 0)
        var domainMax = RGBColor(red: 1, green: 1, blue: 1)
        var values: [RGBColor] = []

        for (offset, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let lineNumber = offset + 1
            let line = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let directive = parts.first else { continue }

            switch directive.uppercased() {
            case "TITLE":
                let remainder = line.dropFirst(directive.count).trimmingCharacters(in: .whitespaces)
                guard !remainder.isEmpty else { throw CUBEParserError.invalidDirective(line: lineNumber) }
                title = remainder.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            case "LUT_3D_SIZE":
                guard parts.count == 2, let size = Int(parts[1]), supportedDimensions.contains(size) else {
                    if parts.count == 2, let size = Int(parts[1]) {
                        throw CUBEParserError.unsupportedDimension(size)
                    }
                    throw CUBEParserError.invalidDirective(line: lineNumber)
                }
                guard dimension == nil else { throw CUBEParserError.invalidDirective(line: lineNumber) }
                dimension = size
            case "LUT_1D_SIZE":
                throw CUBEParserError.unsupportedFormat
            case "DOMAIN_MIN":
                domainMin = try parseTriple(parts, lineNumber: lineNumber)
            case "DOMAIN_MAX":
                domainMax = try parseTriple(parts, lineNumber: lineNumber)
            default:
                values.append(try parseColorValue(parts, lineNumber: lineNumber))
            }
        }

        guard let dimension else { throw CUBEParserError.missingDimension }
        let expected = dimension * dimension * dimension
        guard values.count == expected else {
            throw CUBEParserError.incorrectValueCount(expected: expected, actual: values.count)
        }
        return LUT(title: title, dimension: dimension, domainMin: domainMin, domainMax: domainMax, values: values)
    }

    private static func parseTriple(_ parts: [Substring], lineNumber: Int) throws -> RGBColor {
        guard parts.count == 4,
              let red = Float(parts[1]), let green = Float(parts[2]), let blue = Float(parts[3]),
              red.isFinite, green.isFinite, blue.isFinite else {
            throw CUBEParserError.invalidDirective(line: lineNumber)
        }
        return RGBColor(red: red, green: green, blue: blue)
    }

    private static func parseColorValue(_ parts: [Substring], lineNumber: Int) throws -> RGBColor {
        guard parts.count == 3,
              let red = Float(parts[0]), let green = Float(parts[1]), let blue = Float(parts[2]),
              red.isFinite, green.isFinite, blue.isFinite else {
            throw CUBEParserError.invalidValue(line: lineNumber)
        }
        return RGBColor(red: red, green: green, blue: blue)
    }
}
