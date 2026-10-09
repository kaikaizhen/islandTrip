import Foundation

struct LocationSample: Hashable, Sendable {
    var coordinate: Coordinate
    /// 定位誤差半徑（公尺）；越小越準。
    var horizontalAccuracy: Double
    var timestamp: Date
}

enum LocationError: Error, Equatable {
    case denied
    case unavailable
    case timeout
}

/// 位置來源。正式為 Core Location；測試與模擬模式用假物件。
protocol LocationProviding: Sendable {
    /// 取得一次目前位置（首頁出發地用）。
    func currentLocation() async throws -> LocationSample
    /// 導航期間持續更新；停止迭代（取消）即停止定位，行程結束不會繼續追蹤。
    func liveUpdates() -> AsyncThrowingStream<LocationSample, Error>
}
