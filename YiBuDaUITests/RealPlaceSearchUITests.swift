import XCTest

/// 使用真實 Apple 地圖搜尋目的地（需要網路）。
/// 預設略過；執行時加上 `TEST_RUNNER_RUN_NETWORK_TESTS=1`。
final class RealPlaceSearchUITests: XCTestCase {
    @MainActor
    func testSearchRealDestinationWithMapKit() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_NETWORK_TESTS"] == "1", "需要網路，預設略過")

        let app = XCUIApplication()
        app.launch()
        let field = app.textFields["destinationField"]
        field.tap()
        field.typeText("台大醫院")

        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "suggestion-")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15), "Apple 地圖沒有回傳結果")
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "real-search"
        attachment.lifetime = .keepAlways
        add(attachment)

        result.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "primaryAction").firstMatch.isEnabled)
    }
}
