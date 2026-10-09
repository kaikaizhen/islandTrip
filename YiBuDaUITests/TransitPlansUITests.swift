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

    @MainActor
    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
