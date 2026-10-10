import XCTest

/// 推薦班次頁下方可以查看轉乘方案，並標示即時／表定（模擬資料）。
final class TransitPlansUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTransitPlanDetailShowsStepsAndDataLevel() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-mockPlaceSearch", "-mockWalking", "-mockTransit"]
        app.launch()

        app.buttons["公司"].tap()
        app.buttons.matching(identifier: "primaryAction").firstMatch.tap()
        XCTAssertTrue(app.buttons["option-265"].waitForExistence(timeout: 5))

        // 卡片合併成單一無障礙元素，類型不一定是 button，用識別碼找。
        let plan = app.descendants(matching: .any)["plan-mock-plan-bus-metro"]
        XCTAssertTrue(plan.waitForExistence(timeout: 10))
        // 捲動視圖外的元素 isHittable 仍可能為 true；捲到卡片完全在底部按鈕列上方再點，避免點到按鈕列。
        let bottomBar = app.buttons.matching(identifier: "secondaryAction").firstMatch
        for _ in 0..<8 where plan.frame.maxY > bottomBar.frame.minY - 8 {
            app.swipeUp()
        }
        attachScreenshot("transit-plans-section")
        plan.tap()

        XCTAssertTrue(app.navigationBars["轉乘方案"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["模擬資料"].exists)
        let busStep = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "搭 公車 忠孝幹線")).firstMatch
        XCTAssertTrue(busStep.waitForExistence(timeout: 5))
        sleep(2)
        attachScreenshot("transit-plan-detail")
        busStep.swipeUp() // 不要在地圖上滑，否則只會拖動地圖
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "表定")).firstMatch.exists)
        attachScreenshot("transit-plan-detail-steps")

        app.buttons["關閉"].tap()
        XCTAssertTrue(plan.waitForExistence(timeout: 5))
    }

    /// 轉乘導航全程（模擬資料）：步行 → 上車側 → 候車 → 公車 → 站內 → 候車 → 捷運 → 步行 → 到達。
    @MainActor
    func testTransferNavigationWithMockData() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-mockPlaceSearch", "-mockWalking", "-mockTransit"]
        app.launch()

        app.buttons["公司"].tap()
        app.buttons.matching(identifier: "primaryAction").firstMatch.tap()
        XCTAssertTrue(app.buttons["option-265"].waitForExistence(timeout: 5))
        let plan = app.descendants(matching: .any)["plan-mock-plan-bus-metro"]
        XCTAssertTrue(plan.waitForExistence(timeout: 10))
        let bottomBar = app.buttons.matching(identifier: "secondaryAction").firstMatch
        for _ in 0..<8 where plan.frame.maxY > bottomBar.frame.minY - 8 {
            app.swipeUp()
        }
        plan.tap()
        XCTAssertTrue(app.navigationBars["轉乘方案"].waitForExistence(timeout: 5))
        tapPrimary("開始轉乘導航")

        // 1. 步行到公車站（直線估計）
        XCTAssertTrue(app.navigationBars["步行"].waitForExistence(timeout: 5))
        attachScreenshot("plan-nav-1-walk")
        tapPrimary("我到了")

        // 2. 上車側：回答「旁邊這一側就是」
        XCTAssertTrue(app.navigationBars["確認上車側"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "忠孝幹線")).firstMatch.exists)
        attachScreenshot("plan-nav-2-boarding-side")
        tapPrimary("我在正確的站牌了")

        // 3. 候車：公車有即時
        XCTAssertTrue(app.navigationBars["候車"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["第 1 段車，共 2 段"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "即時")).firstMatch.exists)
        attachScreenshot("plan-nav-3-waiting-bus")
        tapPrimary("我已上車")

        // 4. 搭公車
        XCTAssertTrue(app.navigationBars["搭乘中"].waitForExistence(timeout: 5))
        attachScreenshot("plan-nav-4-riding-bus")
        tapPrimary("我已下車")

        // 5. 站內走到月台
        XCTAssertTrue(app.navigationBars["車站內"].waitForExistence(timeout: 5))
        attachScreenshot("plan-nav-5-station")
        tapPrimary("我到月台了")

        // 6. 候車：捷運只有表定
        XCTAssertTrue(app.navigationBars["候車"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["第 2 段車，共 2 段"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "表定")).firstMatch.exists)
        attachScreenshot("plan-nav-6-waiting-metro")
        tapPrimary("我已上車")

        // 7. 搭捷運 → 下車 → 走到目的地 → 到達
        XCTAssertTrue(app.navigationBars["搭乘中"].waitForExistence(timeout: 5))
        attachScreenshot("plan-nav-7-riding-metro")
        tapPrimary("我已下車")
        XCTAssertTrue(app.navigationBars["步行"].waitForExistence(timeout: 5))
        tapPrimary("我到了")
        XCTAssertTrue(app.staticTexts["已抵達"].waitForExistence(timeout: 5))
        attachScreenshot("plan-nav-8-arrived")
        tapPrimary("結束導航")

        XCTAssertTrue(app.textFields["destinationField"].waitForExistence(timeout: 5))
    }

    /// 點目前可點擊、標題含指定文字的主要按鈕（全螢幕畫面下層也有同 ID 的按鈕）。
    @MainActor
    private func tapPrimary(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let query = XCUIApplication().buttons.matching(identifier: "primaryAction")
            .matching(NSPredicate(format: "label CONTAINS %@", title))
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
    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
