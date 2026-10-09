import CoreLocation
import Foundation

/// 以 Core Location 取得位置。只在需要時開啟：首頁取一次、導航期間持續，結束即停止。
struct CoreLocationProvider: LocationProviding {
    /// 首頁出發地可接受的最大誤差。
    var acceptableAccuracy: CLLocationAccuracy = 100
    var timeout: Duration = .seconds(15)

    func currentLocation() async throws -> LocationSample {
        let acceptableAccuracy = acceptableAccuracy
        let timeout = timeout
        return try await withThrowingTaskGroup(of: LocationSample.self) { group in
            group.addTask {
                // CLServiceSession 在需要時詢問「使用 App 期間」權限，並在取得位置前保持有效。
                let session = CLServiceSession(authorization: .whenInUse)
                defer { session.invalidate() }
                for try await update in CLLocationUpdate.liveUpdates() {
                    if update.authorizationDenied || update.authorizationDeniedGlobally { throw LocationError.denied }
                    if let location = update.location,
                       location.horizontalAccuracy >= 0, location.horizontalAccuracy <= acceptableAccuracy {
                        return Self.sample(location)
                    }
                }
                throw LocationError.unavailable
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw LocationError.timeout
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw LocationError.unavailable }
            return first
        }
    }

    func liveUpdates() -> AsyncThrowingStream<LocationSample, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let session = CLServiceSession(authorization: .whenInUse)
                // 導航中鎖定螢幕或切到背景時繼續定位；行程結束（取消串流）即釋放。
                let background = CLBackgroundActivitySession()
                defer {
                    session.invalidate()
                    background.invalidate()
                }
                do {
                    for try await update in CLLocationUpdate.liveUpdates(.otherNavigation) {
                        if update.authorizationDenied || update.authorizationDeniedGlobally { throw LocationError.denied }
                        if let location = update.location, location.horizontalAccuracy >= 0 {
                            continuation.yield(Self.sample(location))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func sample(_ location: CLLocation) -> LocationSample {
        LocationSample(
            coordinate: Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
            horizontalAccuracy: location.horizontalAccuracy,
            timestamp: location.timestamp
        )
    }
}
