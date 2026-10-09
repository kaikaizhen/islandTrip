import XCTest

/// 模擬器煙霧測試：走一遍模擬導航流程。
/// 回到主畫面時會停留數秒，方便以 `xcrun simctl io booted screenshot` 擷取動態島。
final class LiveActivitySmokeUITests: XCTestCase {
    static let homeScreenPause: UInt32 = 5

    @MainActor
    func testSimulatedNavigationFlow() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["設定"].tap()
        app.buttons["能力測試：動態島與通知"].tap()

        app.buttons["開始模擬導航"].tap()
        let card = app.descendants(matching: .any)["instructionCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.label.contains("120 公尺後右轉"))
        XCTAssertFalse(app.descendants(matching: .any)["noticeBanner"].exists, "啟動即時動態時出現警告")

        XCUIDevice.shared.press(.home)
        sleep(3)
        attachScreen(named: "dynamic-island-120m")
        sleep(Self.homeScreenPause)

        app.activate()
        tapWhenHittable(app.buttons["模擬下一步"])
        let updated = NSPredicate(format: "label CONTAINS %@", "80 公尺後右轉")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: updated, evaluatedWith: card)], timeout: 5), .completed)
        XCUIDevice.shared.press(.home)
        sleep(3)
        attachScreen(named: "dynamic-island-80m")
        sleep(Self.homeScreenPause)

        app.activate()
        tapWhenHittable(app.buttons["結束模擬"].firstMatch)
        XCTAssertTrue(app.buttons["開始模擬導航"].waitForExistence(timeout: 5))
    }

    /// 從背景回到前景的轉場期間點擊會被吞掉，先等元素可點擊。
    @MainActor
    private func tapWhenHittable(_ element: XCUIElement) {
        let hittable = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 5), .completed)
        element.tap()
    }

    /// 擷取整個裝置螢幕（含動態島區域）。
    @MainActor
    private func attachScreen(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
