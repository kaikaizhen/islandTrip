import Foundation

/// 轉乘來不及的提醒（計畫 Phase 5：轉乘緩衝、來不及可重新規劃）。
struct TransferWarning: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// 還在候車，但這班車預估已經開走。
        case currentDeparted
        /// 照目前的時間，到轉乘站時下一班已經開走。
        case likelyMissConnection
        /// 趕得上但很緊（不到 1 分鐘餘裕）。
        case tightConnection
    }

    var kind: Kind
    /// 受影響的那一段，例：「臺鐵 區間」。
    var line: String
    /// 那一段的預估或表定開車時間。
    var departAt: Date?
    /// 依即時資料還是表定時間判斷。
    var basedOnRealtime: Bool

    /// 需要重新規劃（緊但趕得上時只提醒）。
    var suggestsReplan: Bool { kind != .tightConnection }
}

enum TransferCheck {
    /// 錯過一班也很快有下一班的運具，不提醒轉乘風險。
    static func isFrequent(_ mode: TransitMode) -> Bool { mode == .metro || mode == .lightRail }

    /// - Parameters:
    ///   - transitIndex: 目前（候車或搭乘中）是第幾段搭乘。
    ///   - currentLeg: 目前這段，含候車時更新過的即時資料。
    ///   - isRiding: 已上車。
    ///   - paceFactor: 步行速度倍數（慢慢走 1.3）。
    static func evaluate(plan: TransitPlan, transitIndex: Int, currentLeg: TransitLeg, isRiding: Bool,
                         now: Date, paceFactor: Double = 1.0) -> TransferWarning? {
        let currentDeparture = departure(of: currentLeg)
        if !isRiding, let departAt = currentDeparture.at, departAt < now.addingTimeInterval(-60) {
            return TransferWarning(kind: .currentDeparted, line: PlanFormat.lineTitle(currentLeg), departAt: departAt,
                                   basedOnRealtime: currentDeparture.isRealtime)
        }

        let transitPositions = plan.legs.indices.filter { if case .transit = plan.legs[$0] { true } else { false } }
        guard transitIndex + 1 < transitPositions.count,
              case .transit(let next) = plan.legs[transitPositions[transitIndex + 1]],
              !isFrequent(next.mode) else { return nil }

        // 到轉乘站的時間：已上車用預計抵達；候車中用「預估開車＋搭乘時間」。
        let arrival: Date?
        if isRiding {
            arrival = currentLeg.expectedArrival
        } else if let departAt = currentDeparture.at, let plannedDepart = currentLeg.departAt, let plannedArrive = currentLeg.arriveAt {
            arrival = departAt.addingTimeInterval(plannedArrive.timeIntervalSince(plannedDepart))
        } else {
            arrival = currentLeg.expectedArrival
        }
        let nextDeparture = departure(of: next)
        guard let arrival, let nextAt = nextDeparture.at else { return nil }

        // 兩段之間的步行（含站內）依步行速度放大。
        let between = plan.legs[(transitPositions[transitIndex] + 1)..<transitPositions[transitIndex + 1]]
        let walkSeconds = between.reduce(0.0) { total, leg in
            if case .walk(let walk) = leg { total + Double(walk.seconds) * paceFactor } else { total }
        }
        let slack = nextAt.timeIntervalSince(arrival.addingTimeInterval(walkSeconds))
        let basedOnRealtime = currentDeparture.isRealtime || nextDeparture.isRealtime || currentLeg.railRealtime?.delayMinutes != nil
        if slack < 0 {
            return TransferWarning(kind: .likelyMissConnection, line: PlanFormat.lineTitle(next), departAt: nextAt, basedOnRealtime: basedOnRealtime)
        }
        if slack < 60 {
            return TransferWarning(kind: .tightConnection, line: PlanFormat.lineTitle(next), departAt: nextAt, basedOnRealtime: basedOnRealtime)
        }
        return nil
    }

    /// 開車（或公車到站）時間：即時優先，其次表定。
    static func departure(of leg: TransitLeg) -> (at: Date?, isRealtime: Bool) {
        if let rail = leg.railRealtime { return (rail.expectedAt, true) }
        if let bus = leg.realtime?.arrivalAt { return (bus, true) }
        return (leg.departAt, false)
    }
}
