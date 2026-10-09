import CoreLocation
import XCTest

/// 用模擬器 GPS 沿 Apple 地圖的真實步行路線移動，確認步驟會自動依序前進到到達。
/// 需要網路（Apple 地圖）；預設略過，執行時加上 `TEST_RUNNER_RUN_NETWORK_TESTS=1`，
/// 並先授權定位：`xcrun simctl privacy booted grant location com.zhenkaikai.yibuda`。
final class GPSWalkUITests: XCTestCase {
    @MainActor
    func testWalkTestAdvancesStepsWithSimulatedGPS() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_NETWORK_TESTS"] == "1", "需要網路，預設略過")
        continueAfterFailure = false

        // 台北市政府附近
        moveTo(latitude: 25.04080, longitude: 121.56540)
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestExposeTarget"]
        app.launch()

        app.buttons["設定"].tap()
        app.buttons["walkTest"].tap()
        let primary = app.buttons.matching(identifier: "primaryAction").firstMatch
        XCTAssertTrue(primary.waitForEnabled(timeout: 20), "定位失敗")
        primary.tap()

        let field = app.textFields["placePickerField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("誠品信義店")
        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "pick-")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15), "Apple 地圖沒有回傳地點")
        result.tap()

        let instruction = app.staticTexts["currentInstruction"].firstMatch
        XCTAssertTrue(instruction.waitForExistence(timeout: 20), "沒有開始導航")
        XCTAssertTrue(app.staticTexts["GPS 導航中"].firstMatch.waitForExistence(timeout: 10))
        attach("gps-walk-start")

        var seen: [String] = []
        for _ in 0..<12 {
            if app.staticTexts["已抵達"].firstMatch.exists { break }
            let target = app.staticTexts["uiTestTarget"].firstMatch
            guard target.waitForExistence(timeout: 5) else { break }
            let parts = target.label.split(separator: ",").compactMap { Double($0) }
            XCTAssertEqual(parts.count, 2)
            seen.append(instruction.label)
            // 走到這一步的終點：連續兩筆（小幅移動）才算到達。
            moveTo(latitude: parts[0], longitude: parts[1])
            sleep(1)
            moveTo(latitude: parts[0] + 0.00001, longitude: parts[1])
            sleep(2)
            if seen.count == 2 { attach("gps-walk-second-step") }
        }

        XCTAssertTrue(app.staticTexts["已抵達"].firstMatch.waitForExistence(timeout: 10), "走完全部步驟後應到達")
        XCTAssertGreaterThanOrEqual(seen.count, 2, "至少要依序經過 2 個步驟")
        XCTAssertEqual(seen.count, Set(seen).count, "每一步只出現一次（沒有亂跳、沒有回頭）")
        attach("gps-walk-arrived")
        print("GPS_WALK_STEPS \(seen)")
    }

    private func moveTo(latitude: Double, longitude: Double) {
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: latitude, longitude: longitude))
    }

    @MainActor
    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension XCUIElement {
    func waitForEnabled(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "isEnabled == true")
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: self)], timeout: timeout) == .completed
    }
}
