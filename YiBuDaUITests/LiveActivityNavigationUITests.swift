import XCTest

/// Phase 4：轉乘導航（模擬資料）時的 Live Activity，以及動態島展開後的「我已上車」按鈕（決策 D4）。
final class LiveActivityNavigationUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testBoardFromDynamicIsland() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-mockPlaceSearch", "-mockWalking", "-mockTransit"]
        app.launch()

        app.buttons["公司"].tap()
        app.buttons.matching(identifier: "primaryAction").firstMatch.tap()
        XCTAssertTrue(app.buttons["option-265"].waitForExistence(timeout: 5))
        let plan = app.descendants(matching: .any)["plan-mock-plan-metro"]
        XCTAssertTrue(plan.waitForExistence(timeout: 10))
        let bottomBar = app.buttons.matching(identifier: "secondaryAction").firstMatch
        for _ in 0..<8 where plan.frame.maxY > bottomBar.frame.minY - 8 {
            app.swipeUp()
        }
        plan.tap()
        tapPrimary(app, "開始轉乘導航")

        // 步行 → 候車（捷運，表定）
        XCTAssertTrue(app.navigationBars["步行"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        sleep(3)
        attachScreen(named: "island-walking")
        app.activate()
        tapPrimary(app, "我到了")
        XCTAssertTrue(app.navigationBars["候車"].waitForExistence(timeout: 5))

        XCUIDevice.shared.press(.home)
        sleep(3)
        attachScreen(named: "island-waiting")

        // 長按動態島展開，按「我已上車」
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let island = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.0)).withOffset(CGVector(dx: 0, dy: 25))
        island.press(forDuration: 1.2)
        sleep(1)
        attachScreen(named: "island-expanded")
        let board = springboard.buttons["我已上車"]
        XCTAssertTrue(board.waitForExistence(timeout: 5), "展開的動態島沒有「我已上車」按鈕")
        board.tap()
        sleep(2)

        app.activate()
        XCTAssertTrue(app.navigationBars["搭乘中"].waitForExistence(timeout: 5), "按動態島按鈕後沒有進入搭乘中")
        XCUIDevice.shared.press(.home)
        sleep(3)
        attachScreen(named: "island-riding")

        app.activate()
        tapPrimary(app, "我已下車")
        XCTAssertTrue(app.navigationBars["步行"].waitForExistence(timeout: 5))
        tapPrimary(app, "我到了")
        tapPrimary(app, "結束導航")
        XCTAssertTrue(app.textFields["destinationField"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func tapPrimary(_ app: XCUIApplication, _ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let query = app.buttons.matching(identifier: "primaryAction").matching(NSPredicate(format: "label CONTAINS %@", title))
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let element = query.allElementsBoundByIndex.last(where: { $0.isHittable }) {
                element.tap()
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail("等不到可點擊的「\(title)」", file: file, line: line)
    }

    @MainActor
    private func attachScreen(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
