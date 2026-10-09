import CoreLocation
import Foundation

/// 手機朝向（指南針）。
struct HeadingSample: Hashable, Sendable {
    /// 手機頂端朝向的方位（度，正北 0、順時針）。
    var degrees: Double
    /// 誤差（度）；負值代表無效。
    var accuracy: Double
}

/// 手機朝向來源。正式為 Core Location 指南針；測試用假物件。
@MainActor
protocol HeadingProviding {
    /// 持續更新；停止迭代即關閉指南針。
    func headingUpdates() -> AsyncStream<HeadingSample>
}

/// 以 CLLocationManager 取得指南針朝向。只在步行步驟期間開啟以省電。
@MainActor
final class CoreLocationHeadingProvider: HeadingProviding {
    func headingUpdates() -> AsyncStream<HeadingSample> {
        AsyncStream { continuation in
            let streamer = HeadingStreamer(continuation: continuation)
            streamer.start()
            continuation.onTermination = { _ in
                Task { @MainActor in streamer.stop() }
            }
        }
    }
}

/// 把 CLLocationManager 的指南針回呼轉成 AsyncStream。
private final class HeadingStreamer: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private let continuation: AsyncStream<HeadingSample>.Continuation

    init(continuation: AsyncStream<HeadingSample>.Continuation) {
        self.continuation = continuation
        super.init()
        manager.delegate = self
        manager.headingFilter = 2
        manager.headingOrientation = .portrait
    }

    func start() {
        guard CLLocationManager.headingAvailable() else {
            continuation.finish()
            return
        }
        manager.startUpdatingHeading()
    }

    func stop() {
        manager.stopUpdatingHeading()
        manager.delegate = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading heading: CLHeading) {
        // 有定位權限時用真北，否則退回磁北。
        let degrees = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
        continuation.yield(HeadingSample(degrees: degrees, accuracy: heading.headingAccuracy))
    }

    /// 誤差大時讓系統顯示指南針校正畫面。
    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        true
    }
}
