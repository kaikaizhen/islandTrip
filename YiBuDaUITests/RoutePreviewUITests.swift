import XCTest

/// 選方案前可以在地圖上確認，並從地圖畫面直接選定方案。
final class RoutePreviewUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testPreviewSelectedOptionOnMap() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["公司"].tap()
        app.buttons.matching(identifier: "primaryAction").firstMatch.tap()
        XCTAssertTrue(app.buttons["option-265"].waitForExistence(timeout: 5))

        app.buttons["secondaryAction"].tap()
        XCTAssertTrue(app.navigationBars["在地圖上確認"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["走到 市政府站"].exists)
        // 等 MapKit 算完步行路線與地圖載入再截圖（需要網路；離線時會顯示直線示意）。
        _ = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Apple 地圖")).firstMatch.waitForExistence(timeout: 15)
        sleep(2)
        attachScreenshot("route-preview-boarding-area")
        app.buttons["全程"].tap()
        sleep(2)
        attachScreenshot("route-preview-whole-route")

        let choose = app.buttons.matching(identifier: "primaryAction").allElementsBoundByIndex.last { $0.label.contains("選這個方案") }
        try XCTUnwrap(choose).tap()
        XCTAssertTrue(app.buttons["option-265"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
