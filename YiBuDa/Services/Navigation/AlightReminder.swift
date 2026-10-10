import Foundation

/// 搭乘中判斷「快到站了」：有可信 GPS 時看離下車站多近，否則看表定抵達時間（決策 D9）。
/// 不論哪一種都只是提醒，下車仍由使用者按「我已下車」。
struct AlightReminder: Sendable {
    enum Source: Equatable, Sendable {
        case gps
        case schedule
    }

    struct Status: Equatable, Sendable {
        var isApproaching: Bool
        /// 這個結論的依據；還沒有任何依據時為 nil。
        var source: Source?
        /// 依 GPS 推算的剩餘站數（定位夠準、找得到最近的站時才有）。
        var remainingStops: Int?
    }

    /// 定位誤差超過這個值就不用 GPS（地下捷運常收不到）。
    var maximumAccuracy = 100.0
    /// 離某站這麼近才算「在這一站附近」。
    var nearStopRadius = 250.0
    /// 離下車站這麼近就提醒。公車站距短，軌道站距長。
    var approachRadiusBus = 350.0
    var approachRadiusRail = 700.0
    /// 表定抵達前多久提醒。
    var scheduleLeadTime: TimeInterval = 120

    func status(for leg: TransitLeg, sample: LocationSample?, now: Date) -> Status {
        if let sample, sample.horizontalAccuracy >= 0, sample.horizontalAccuracy <= maximumAccuracy {
            let stations = [leg.from] + leg.stops + [leg.to]
            let distanceToAlight = Geo.distance(sample.coordinate, leg.to.coordinate)
            let radius = leg.mode == .bus ? approachRadiusBus : approachRadiusRail
            let nearest = stations.indices.min { lhs, rhs in
                Geo.distance(sample.coordinate, stations[lhs].coordinate) < Geo.distance(sample.coordinate, stations[rhs].coordinate)
            }
            var remaining: Int?
            // 沒有中途站資料時算不出站數；還在上車站附近也不算（剛上車不能就提醒下車）。
            if !leg.stops.isEmpty, let nearest, nearest > 0,
               Geo.distance(sample.coordinate, stations[nearest].coordinate) <= nearStopRadius {
                remaining = stations.count - 1 - nearest
            }
            // 已在下車站前一站附近，或離下車站夠近。
            let approaching = distanceToAlight <= radius || (remaining.map { $0 <= 1 } ?? false)
            return Status(isApproaching: approaching, source: .gps, remainingStops: remaining)
        }
        if let arriveAt = leg.arriveAt {
            return Status(isApproaching: now >= arriveAt.addingTimeInterval(-scheduleLeadTime), source: .schedule, remainingStops: nil)
        }
        return Status(isApproaching: false, source: nil, remainingStops: nil)
    }
}
