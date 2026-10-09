import Foundation

/// 一個導航指令。箭頭種類沿用 `Maneuver`。
struct NavigationInstruction: Identifiable, Hashable, Sendable {
    enum Source: Hashable, Sendable {
        case mock
        case mapKit
    }

    var id: String
    var kind: Maneuver
    /// 例：「直走 120 公尺，到路口右轉」
    var displayText: String
    var distanceMeters: Int?
    var targetCoordinate: Coordinate?
    /// 安全提示，例：「請走行人穿越道，不要直接穿越車道」
    var safetyNote: String?
    var source: Source
}

struct WalkLeg: Hashable, Sendable {
    var destinationName: String
    var seconds: Int
    var instructions: [NavigationInstruction]
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
