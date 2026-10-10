import SwiftUI
import Testing
@testable import YiBuDa

/// 回歸測試：iPhone 為淺色模式時，手錶 Smart Stack（黑底）上的文字仍需看得見。
@MainActor
struct WatchNavigationViewTests {
    @Test(arguments: [ColorScheme.light, .dark])
    func textStaysVisibleOnWatchBackground(phoneScheme: ColorScheme) throws {
        let state = try #require(SimulatedNavigationScript.phase0.state(at: 0, updatedAt: .now))
        let view = WatchNavigationView(state: state, isSimulated: true, isStale: false)
            .frame(width: 180, height: 120)
            .background(WatchNavigationView.background)
            .environment(\.colorScheme, phoneScheme)

        let brightPixels = try countNearWhitePixels(in: view)

        // 箭頭是藍色不計入；只有白色文字會產生近白像素。
        #expect(brightPixels > 200)
    }

    /// 回歸測試：40mm 手錶上文字被截成「…」。每個步驟的理想寬度都需在預算內。
    @Test(arguments: [false, true])
    func everyStepFitsSmallWatchWidth(isStale: Bool) throws {
        let script = SimulatedNavigationScript.phase0
        for index in 0..<script.count {
            let state = try #require(script.state(at: index, updatedAt: .now))
            let view = WatchNavigationView(state: state, isSimulated: true, isStale: isStale).fixedSize()
            let width = try #require(ImageRenderer(content: view).uiImage).size.width
            #expect(width <= WatchNavigationView.widthBudget, "步驟 \(index)「\(state.title)」寬 \(width)pt")
        }
    }

    /// Phase 4 各階段（D4）在 40mm 手錶也不能被截斷。
    @Test func everyStageFitsSmallWatchWidth() throws {
        let now = Date.now
        let stop = Stop(stopUID: "S", name: "泉源3號橋", coordinate: Coordinate(latitude: 25, longitude: 121),
                        directionDescription: "往致遠新村方向", dataTime: now)
        let states: [NavigationActivityAttributes.ContentState] = [
            NavigationActivityMapper.boardingSide(route: "小9(台灣好行-北投竹子湖)", stop: stop,
                                                  resolution: .known(needsToCross: true, source: .manual), now: now),
            NavigationActivityMapper.waiting(route: "小9(台灣好行-北投竹子湖)", stopName: "泉源3號橋", direction: "往致遠新村",
                                             arrivalAt: now.addingTimeInterval(599), isScheduled: false, alightName: "北投", now: now),
            NavigationActivityMapper.riding(route: "淡水信義線", alightName: "台北車站", approaching: false,
                                            remainingStops: 12, alightAt: nil, now: now),
            NavigationActivityMapper.riding(route: "淡水信義線", alightName: "台北車站", approaching: false,
                                            remainingStops: nil, alightAt: nil, now: now),
            NavigationActivityMapper.waiting(route: "淡水信義線", stopName: "台北101/世貿", direction: "往淡水",
                                             arrivalAt: nil, isScheduled: true, alightName: "北投", now: now),
            NavigationActivityMapper.riding(route: "307", alightName: "台北車站", approaching: true,
                                            remainingStops: nil, alightAt: nil, now: now),
            NavigationActivityMapper.arrived("公司", now: now),
        ]
        for state in states {
            let view = WatchNavigationView(state: state, isSimulated: true, isStale: false).fixedSize()
            let width = try #require(ImageRenderer(content: view).uiImage).size.width
            #expect(width <= WatchNavigationView.widthBudget, "\(state.stage)「\(state.shortTitle ?? state.title)」寬 \(width)pt")
        }
    }

    private func countNearWhitePixels(in view: some View) throws -> Int {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)

        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        return stride(from: 0, to: pixels.count, by: 4).filter { i in
            pixels[i] > 200 && pixels[i + 1] > 200 && pixels[i + 2] > 200
        }.count
    }
}
