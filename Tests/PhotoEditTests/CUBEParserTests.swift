import XCTest
@testable import PhotoEdit

final class CUBEParserTests: XCTestCase {
    func testParsesTitleCommentsBlankLinesAndDomain() throws {
        let text = """
        # a comment

        TITLE "Identity Test" # inline comment
        LUT_3D_SIZE 17
        DOMAIN_MIN 0 0 0
        DOMAIN_MAX 1 1 1
        \(TestLUTFactory.identityText(dimension: 17).components(separatedBy: .newlines).dropFirst().joined(separator: "\n"))
        """
        let lut = try CUBEParser.parse(text: text)
        XCTAssertEqual(lut.title, "Identity Test")
        XCTAssertEqual(lut.dimension, 17)
        XCTAssertEqual(lut.domainMin, RGBColor(red: 0, green: 0, blue: 0))
        XCTAssertEqual(lut.domainMax, RGBColor(red: 1, green: 1, blue: 1))
        XCTAssertEqual(lut.values.count, 4_913)
    }

    func testSupports33And65CubeSizes() throws {
        XCTAssertEqual(try CUBEParser.parse(text: TestLUTFactory.identityText(dimension: 33)).values.count, 35_937)
        XCTAssertEqual(try CUBEParser.parse(text: TestLUTFactory.identityText(dimension: 65)).values.count, 274_625)
    }

    func testRejectsUnsupportedDimension() {
        XCTAssertThrowsError(try CUBEParser.parse(text: "LUT_3D_SIZE 16")) { error in
            XCTAssertEqual(error as? CUBEParserError, .unsupportedDimension(16))
        }
    }

    func testRejectsMalformedFloat() {
        XCTAssertThrowsError(try CUBEParser.parse(text: "LUT_3D_SIZE 17\nnot-a-number 0 0")) { error in
            XCTAssertEqual(error as? CUBEParserError, .invalidValue(line: 2))
        }
    }

    func testRejectsInsufficientAndExcessValues() {
        XCTAssertThrowsError(try CUBEParser.parse(text: "LUT_3D_SIZE 17")) { error in
            XCTAssertEqual(error as? CUBEParserError, .incorrectValueCount(expected: 4_913, actual: 0))
        }
        let text = TestLUTFactory.identityText(dimension: 17) + "\n0 0 0"
        XCTAssertThrowsError(try CUBEParser.parse(text: text)) { error in
            XCTAssertEqual(error as? CUBEParserError, .incorrectValueCount(expected: 4_913, actual: 4_914))
        }
    }

    func testRejectsOneDimensionalCube() {
        XCTAssertThrowsError(try CUBEParser.parse(text: "LUT_1D_SIZE 17")) { error in
            XCTAssertEqual(error as? CUBEParserError, .unsupportedFormat)
        }
    }

    func testRejectsAnInvertedDomain() {
        let text = """
        LUT_3D_SIZE 17
        DOMAIN_MIN 1 0 0
        DOMAIN_MAX 0 1 1
        """
        XCTAssertThrowsError(try CUBEParser.parse(text: text)) { error in
            XCTAssertEqual(error as? CUBEParserError, .invalidDomain)
        }
    }
}
