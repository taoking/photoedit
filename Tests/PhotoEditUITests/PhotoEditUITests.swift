import XCTest

@MainActor
final class PhotoEditUITests: XCTestCase {
    func testEditorRemainsUsableAcrossPortraitAndLandscape() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing-editor")
        app.launch()

        let lightTool = app.buttons["光线 工具"]
        XCTAssertTrue(lightTool.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["导出"].exists)

        lightTool.tap()
        XCTAssertTrue(app.buttons["收起参数面板"].waitForExistence(timeout: 2))
        let firstSlider = app.sliders.firstMatch
        XCTAssertTrue(firstSlider.waitForExistence(timeout: 2))
        firstSlider.adjust(toNormalizedSliderPosition: 0.7)

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["收起参数面板"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["导出"].isHittable)
        XCTAssertTrue(app.buttons["关闭当前照片"].isHittable)

        app.buttons["关闭当前照片"].tap()
        XCTAssertTrue(app.buttons["保留编辑并返回首页"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["放弃编辑并关闭"].exists)
    }

    func testAccessibilityTextKeepsPrimaryEditorActionsAvailable() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing-editor",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXL"
        ]
        app.launch()

        let lightTool = app.buttons["光线 工具"]
        XCTAssertTrue(lightTool.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["导出"].isHittable)
        XCTAssertTrue(app.buttons["更多编辑操作"].isHittable)
        lightTool.tap()
        XCTAssertTrue(app.buttons["收起参数面板"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.sliders.firstMatch.isHittable)
    }
}
