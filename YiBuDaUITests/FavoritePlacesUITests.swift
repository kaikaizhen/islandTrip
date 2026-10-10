import XCTest

/// 常用地點由使用者設定：一開始是空的，點「設定公司」搜尋地點後就能用，也能在管理頁移除。
final class FavoritePlacesUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testSetAndRemoveFavorite() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-mockPlaceSearch", "-mockWalking", "-mockTransit", "-uiTestEmptyFavorites"]
        app.launch()

        let setWork = app.buttons["setFavorite-work"]
        XCTAssertTrue(setWork.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["manageFavorites"].exists, "沒有常用地點時不需要管理按鈕")
        attachScreen(named: "favorites-empty")
        setWork.tap()

        let field = app.textFields["placePickerField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("台大")
        let pick = app.buttons["pick-台大醫院"]
        XCTAssertTrue(pick.waitForExistence(timeout: 5))
        pick.tap()

        // 設定好的「公司」可以直接當目的地
        let work = app.buttons["公司"]
        XCTAssertTrue(work.waitForExistence(timeout: 5))
        XCTAssertEqual(work.value as? String, "台大醫院")
        attachScreen(named: "favorites-work-set")
        work.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "primaryAction").firstMatch.isEnabled)

        // 管理頁移除
        app.buttons["manageFavorites"].tap()
        let remove = app.buttons["removeFavorite-work"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        attachScreen(named: "favorites-manager")
        remove.tap()
        app.sheets.buttons["移除"].firstMatch.tap()
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["setFavorite-work"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func attachScreen(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
