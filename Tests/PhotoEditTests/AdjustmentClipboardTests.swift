import XCTest
@testable import PhotoEdit

@MainActor
final class AdjustmentClipboardTests: XCTestCase {
    func testSelectivePasteTouchesOnlyRequestedGroups() {
        let clipboard = AdjustmentClipboard()
        var copied = EditState()
        copied.light.exposure = 2
        copied.hsl.red.saturation = 40
        copied.transform.rotation = 90
        clipboard.copy(from: copied)

        var destination = EditState()
        destination.color.tint = 20
        let pasted = clipboard.paste(into: destination, groups: [.light, .hsl])
        XCTAssertEqual(pasted?.light.exposure, 2)
        XCTAssertEqual(pasted?.hsl.red.saturation, 40)
        XCTAssertEqual(pasted?.color.tint, 20)
        XCTAssertEqual(pasted?.transform.rotation, 0)
    }
}
