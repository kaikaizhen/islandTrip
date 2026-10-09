import Foundation

/// 使用者走在馬路的哪一邊（相對於行進方向）。
enum WalkSide: Hashable, Sendable {
    case left
    case right

    var title: String { self == .left ? "左邊" : "右邊" }
    /// 用在「左轉／右轉」。
    var short: String { self == .left ? "左" : "右" }
}

/// 轉彎前的上車側／過馬路建議（D3）。純邏輯。
enum TurnSideAdvice: Equatable, Sendable {
    /// 不是轉彎，不需要提示。
    case none
    /// 還不知道使用者在哪一邊，要問。
    case askSide(turn: WalkSide)
    /// 已在轉彎的那一邊，到路口直接轉。
    case sameSide(turn: WalkSide)
    /// 在對側，要先在路口過馬路。
    case crossFirst(turn: WalkSide)

    static func advice(for maneuver: Maneuver, userSide: WalkSide?) -> TurnSideAdvice {
        guard let turn = maneuver.turnSide else { return .none }
        guard let userSide else { return .askSide(turn: turn) }
        return userSide == turn ? .sameSide(turn: turn) : .crossFirst(turn: turn)
    }

    /// 照指示轉彎後，使用者會在新道路的哪一邊：右轉後在右邊，左轉後在左邊。
    static func sideAfterTurning(_ maneuver: Maneuver, previous: WalkSide?) -> WalkSide? {
        switch maneuver {
        case .turnLeft, .turnRight, .slightLeft, .slightRight: maneuver.turnSide
        case .uTurn, .crossStreet: nil
        default: previous
        }
    }
}

extension Maneuver {
    /// 轉向的那一側；直走、到達等為 nil。
    var turnSide: WalkSide? {
        switch self {
        case .turnLeft, .slightLeft: .left
        case .turnRight, .slightRight: .right
        default: nil
        }
    }
}

/// 以「正確站牌」與「對面反方向站牌」為參考，判斷使用者在哪一側（計畫 4.2）。
/// 定位誤差大於兩站間距一半、或離站牌太遠時不判斷，不硬猜。
enum BoardingSideEstimator {
    enum Estimate: Equatable, Sendable {
        case sameSideAsCorrectStop
        case oppositeSide
        case uncertain(String)
    }

    /// 兩站至少要相距多少才有意義。
    static let minimumStopSeparation = 8.0
    /// 離站牌超過這個距離就不判斷（還在路上）。
    static let maximumDistanceFromStops = 120.0

    static func estimate(user: LocationSample, correctStop: Stop, oppositeStop: Stop) -> Estimate {
        let separation = Geo.distance(correctStop.coordinate, oppositeStop.coordinate)
        guard separation >= minimumStopSeparation else { return .uncertain("兩側站牌太近，無法用定位分辨") }
        guard user.horizontalAccuracy >= 0, user.horizontalAccuracy <= separation / 2 else {
            return .uncertain("定位不夠準，請依站牌名稱與行駛方向確認")
        }
        let nearest = min(Geo.distance(user.coordinate, correctStop.coordinate), Geo.distance(user.coordinate, oppositeStop.coordinate))
        guard nearest <= maximumDistanceFromStops else { return .uncertain("離站牌還遠") }

        // 沿「正確站牌 → 對面站牌」方向的位置：0 在正確站牌，間距處在對面站牌，一半是馬路中線附近。
        let along = alongAxis(user.coordinate, from: correctStop.coordinate, to: oppositeStop.coordinate)
        let offsetFromCenter = along - separation / 2
        // 要明確在某一側（距中線超過定位誤差）才下結論。
        guard abs(offsetFromCenter) > max(user.horizontalAccuracy, 3) else {
            return .uncertain("太靠近馬路中間，無法判斷")
        }
        return offsetFromCenter < 0 ? .sameSideAsCorrectStop : .oppositeSide
    }

    /// 點投影到「a → b」方向上的距離（可小於 0 或大於兩點間距）。
    private static func alongAxis(_ point: Coordinate, from a: Coordinate, to b: Coordinate) -> Double {
        let angle = Geo.turnAngle(from: Geo.bearing(from: a, to: b), to: Geo.bearing(from: a, to: point)) * .pi / 180
        return Geo.distance(a, point) * cos(angle)
    }
}

/// 連續數筆判斷一致才採用，避免單一 GPS 點改變結論。
struct SideEstimateStabilizer: Sendable {
    var required = 3
    private var recent: [BoardingSideEstimator.Estimate] = []

    /// 加入一筆，回傳目前穩定的結論（沒有就是 nil）。
    mutating func add(_ estimate: BoardingSideEstimator.Estimate) -> BoardingSideEstimator.Estimate? {
        recent.append(estimate)
        if recent.count > required { recent.removeFirst(recent.count - required) }
        guard recent.count == required, let first = recent.first, recent.allSatisfy({ $0 == first }) else { return nil }
        if case .uncertain = first { return nil }
        return first
    }
}
