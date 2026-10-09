import Foundation

/// 公車站牌。同名但方向相反的站牌是不同的 `stopUID`，不可合併。
struct Stop: Identifiable, Hashable, Sendable {
    var stopUID: String
    var name: String
    var coordinate: Coordinate
    /// 例：「往台北車站方向」
    var directionDescription: String
    /// 原始資料時間。
    var dataTime: Date

    var id: String { stopUID }
}

/// 某條路線某個方向依序停靠的站牌（停靠模式）。
struct RoutePattern: Hashable, Sendable {
    var patternId: String
    var routeId: String
    var routeName: String
    /// 例：「往台北車站」
    var directionName: String
    var stopUIDs: [String]

    /// 此停靠模式是否先停 `boarding` 再停 `alighting`。
    func serves(from boarding: String, to alighting: String) -> Bool {
        stopCount(from: boarding, to: alighting).map { $0 > 0 } ?? false
    }

    /// 從上車站到下車站要經過幾站；任一站不在此模式中則為 nil。
    func stopCount(from boarding: String, to alighting: String) -> Int? {
        guard let start = stopUIDs.firstIndex(of: boarding),
              let end = stopUIDs.firstIndex(of: alighting) else { return nil }
        return end - start
    }
}

/// 使用者與正確站牌在馬路哪一側。資料不足時必須是 `.unknown`，不可硬猜。
enum BoardingSide: Hashable, Sendable {
    case confirmed(needsToCross: Bool, guidance: String)
    case unknown
}

struct StopDetails: Hashable, Sendable {
    var stop: Stop
    /// 馬路對面、同名但反方向的站牌（若有）。
    var oppositeStop: Stop?
    var side: BoardingSide
}
