import Foundation

/// 一個導航指令。箭頭種類沿用 `Maneuver`。
struct NavigationInstruction: Identifiable, Hashable, Sendable {
    enum Source: Hashable, Sendable {
        case mock
        case mapKit
        /// 無法取得路線時的直線估計。
        case estimated
    }

    var id: String
    var kind: Maneuver
    /// 例：「往前走 120 公尺，到路口右轉」
    var displayText: String
    /// 補充說明，例如 Apple 地圖的原文「右轉進入忠孝東路五段」。
    var detailText: String? = nil
    var distanceMeters: Int?
    /// 這一步結束的位置（下一個動作的地點）。
    var targetCoordinate: Coordinate?
    /// 安全提示，例：「請走行人穿越道，不要直接穿越車道」
    var safetyNote: String?
    var source: Source
    /// 這一步要走的路徑；用來以 GPS 判斷進度。模擬資料可為空。
    var path: [Coordinate] = []
}

struct WalkLeg: Hashable, Sendable {
    var destinationName: String
    var seconds: Int
    var instructions: [NavigationInstruction]
    /// 無法取得真實步行路線，時間與路徑是直線估計。
    var isEstimated = false
}

struct BusLeg: Hashable, Sendable {
    var option: BoardingOption
    var boardingStop: Stop
    var alightingStop: Stop
    var pattern: RoutePattern
}

enum JourneyLeg: Hashable, Sendable {
    case walk(WalkLeg)
    case bus(BusLeg)
}

/// 從起點到目的地的一個完整方案。第一版為「步行 → 公車 → 步行」。
struct Journey: Identifiable, Hashable, Sendable {
    var id: String
    var origin: Place
    var destination: Place
    var legs: [JourneyLeg]
    var computedAt: Date

    var busLeg: BusLeg? {
        legs.lazy.compactMap { if case .bus(let leg) = $0 { leg } else { nil } }.first
    }

    /// 上車前的步行段。
    var walkToStop: WalkLeg? {
        guard case .walk(let leg) = legs.first, legs.count > 1 else { return nil }
        return leg
    }

    /// 下車後的步行段。
    var walkToDestination: WalkLeg? {
        guard case .walk(let leg) = legs.last, legs.count > 1 else { return nil }
        return leg
    }

    func replacingBusOption(_ option: BoardingOption) -> Journey {
        var copy = self
        copy.legs = legs.map { leg in
            guard case .bus(var bus) = leg else { return leg }
            bus.option = option
            return .bus(bus)
        }
        return copy
    }
}
