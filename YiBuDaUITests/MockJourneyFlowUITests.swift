import XCTest

/// Phase 1 完成條件：只用模擬資料（不需網路）把完整流程操作一遍。
final class MockJourneyFlowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testCompleteJourneyWithMockData() throws {
        let app = XCUIApplication()
        app.launch()
        // 推薦班次畫面在全螢幕導航底下仍存在，所以每次都找目前看得到的那個按鈕。
        let primary = app.buttons.matching(identifier: "primaryAction")

        // 首頁：搜尋並選目的地
        XCTAssertFalse(primary.firstMatch.isEnabled, "未選目的地前不能找車")
        let field = app.textFields["destinationField"]
        field.tap()
        field.typeText("台北")
        tapWhenHittable(app.buttons["台北車站"])
        attachScreenshot("1-home")
        tapVisible(primary)

        // 推薦班次：主推 265
        XCTAssertTrue(app.buttons["option-265"].waitForExistence(timeout: 5))
        XCTAssertTrue(primary.firstMatch.label.contains("265"))
        attachScreenshot("2-options")
        tapVisible(primary)

        // 步行到站：3 步
        XCTAssertTrue(app.staticTexts["currentInstruction"].waitForExistence(timeout: 5))
        attachScreenshot("3-walking")
        for _ in 0..<3 { tapVisible(primary) }

        // 確認上車側
        XCTAssertTrue(app.staticTexts["請到對面站牌搭車"].waitForExistence(timeout: 5))
        attachScreenshot("4-boarding-side")
        tapVisible(primary)

        // 候車
        XCTAssertTrue(app.buttons["waiting-265"].waitForExistence(timeout: 5))
        attachScreenshot("5-waiting")
        tapVisible(primary)

        // 搭乘中：模擬前進一站後出現「準備下車」
        tapVisible(app.buttons.matching(identifier: "secondaryAction"))
        XCTAssertTrue(app.descendants(matching: .any)["approachingAlight"].waitForExistence(timeout: 5))
        attachScreenshot("6-on-vehicle")
        tapVisible(primary)

        // 下車後步行 2 步 → 到達
        for _ in 0..<2 { tapVisible(primary) }
        XCTAssertTrue(app.staticTexts["已抵達"].waitForExistence(timeout: 5))
        attachScreenshot("7-arrived")
        tapVisible(primary)

        // 回到首頁
        XCTAssertTrue(app.textFields["destinationField"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func tapWhenHittable(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let hittable = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 5), .completed, "等不到可點擊：\(element)", file: file, line: line)
        element.tap()
    }

    /// 點擊符合條件、目前可點擊的那一個元素。
    @MainActor
    private func tapVisible(_ query: XCUIElementQuery, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let element = query.allElementsBoundByIndex.last(where: { $0.isHittable }) {
                element.tap()
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail("等不到可點擊的按鈕", file: file, line: line)
    }

    @MainActor
    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
