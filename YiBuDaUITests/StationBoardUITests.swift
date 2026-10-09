import XCTest

/// 附近車站 → 車站發車看板（離線模擬資料）。
final class StationBoardUITests: XCTestCase {
    @MainActor
    func testNearbyStationBoardShowsDataLevel() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-mockPlaceSearch", "-mockWalking", "-mockTransit"]
        app.launch()

        let entry = app.buttons["nearbyStations"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: entry)
        wait(for: [enabled], timeout: 10)
        entry.tap()

        let station = app.buttons["station-TRTC-BL18"]
        XCTAssertTrue(station.waitForExistence(timeout: 5))
        station.tap()

        XCTAssertTrue(app.staticTexts["市政府站"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "即時")).firstMatch.waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "station-board"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
