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
