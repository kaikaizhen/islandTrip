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
    /// 搭乘時間是依站數估計（不是同一部車的預估）。
    var rideIsEstimated = false
    /// 沒有預估到站時間的原因，例：「尚未發車」「末班車已過」。
    var statusNote: String?
    /// TDX 縣市代碼，例：Taipei。
    var city: String?
    /// TDX RouteID（通阻消息以它標示影響的路線）。
    var routeCode: String?
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
