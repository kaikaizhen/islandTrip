import Foundation

enum ETASource: Hashable, Sendable {
    case realTime
    case scheduled
    case unknown
}

/// 某一班可搭公車的原始資料（由 TransportProvider 提供，不含推薦判斷）。
struct BoardingOption: Identifiable, Hashable, Sendable {
    var id: String
    var routeId: String
    var routeName: String
    var patternId: String
    /// 例：「往台北車站」
    var direction: String
    var boardingStopUID: String
    var alightingStopUID: String
    /// 公車預估到上車站的時間；查無資料時為 nil，不可偽造。
    var estimatedArrivalAtStop: Date?
    var etaSource: ETASource
    var updatedAt: Date
    var rideSeconds: Int?
}

/// 某站牌的一筆到站預估，用來更新已規劃旅程的 ETA。
struct StopArrival: Hashable, Sendable {
    var patternId: String
    var estimatedArrival: Date?
    var etaSource: ETASource
    var updatedAt: Date
}

extension BoardingOption {
    func updating(with arrival: StopArrival) -> BoardingOption {
        var copy = self
        copy.estimatedArrivalAtStop = arrival.estimatedArrival
        copy.etaSource = arrival.etaSource
        copy.updatedAt = arrival.updatedAt
        return copy
    }
}
