import Foundation

enum CatchStatus: Hashable, Sendable {
    case canCatch
    case tooLate
    /// 查無預估到站時間，無法判斷。
    case unknown
}

/// 經過評估的方案：能否趕上、預計抵達目的地時間、資料是否過期。
struct RankedJourney: Identifiable, Hashable, Sendable {
    var journey: Journey
    var catchStatus: CatchStatus
    var arrivalAtDestination: Date?
    var isStale: Bool

    var id: String { journey.id }
    var option: BoardingOption? { journey.busLeg?.option }
}

enum JourneySortOrder: Hashable, Sendable, CaseIterable {
    /// 預設：先排趕得上的，再依抵達目的地時間。
    case earliestArrival
    /// 依公車到站時間。
    case soonestBus
}

/// 比較所有候車方案。純邏輯、不連網，所有時間由呼叫端傳入。
struct TransitRankingService: Sendable {
    /// 走到站牌後預留的緩衝時間。
    var safetyBuffer: TimeInterval = 120
    /// 到站預估資料超過此時間未更新，就標示「資訊可能過期」。
    var staleThreshold: TimeInterval = 120

    /// - Parameter userAtBoardingStop: 使用者已在上車站（候車中），能否趕上不再計入步行與緩衝。
    func rank(
        _ journeys: [Journey],
        now: Date,
        order: JourneySortOrder = .earliestArrival,
        userAtBoardingStop: Bool = false
    ) -> [RankedJourney] {
        let evaluated = journeys
            .filter { $0.busLeg.map(BoardingDirectionValidator.isValid) ?? false }
            .map { evaluate($0, now: now, userAtBoardingStop: userAtBoardingStop) }

        switch order {
        case .earliestArrival:
            return evaluated.sorted { lhs, rhs in
                (lhs.catchRank, lhs.arrivalAtDestination ?? .distantFuture, lhs.option?.estimatedArrivalAtStop ?? .distantFuture)
                    < (rhs.catchRank, rhs.arrivalAtDestination ?? .distantFuture, rhs.option?.estimatedArrivalAtStop ?? .distantFuture)
            }
        case .soonestBus:
            return evaluated.sorted {
                ($0.option?.estimatedArrivalAtStop ?? .distantFuture) < ($1.option?.estimatedArrivalAtStop ?? .distantFuture)
            }
        }
    }

    /// 主推方案：排序後第一個「確定趕得上」的；都沒有就不主推。
    func recommendation(in ranked: [RankedJourney]) -> RankedJourney? {
        ranked.first { $0.catchStatus == .canCatch }
    }

    func evaluate(_ journey: Journey, now: Date, userAtBoardingStop: Bool = false) -> RankedJourney {
        let requiredLead = userAtBoardingStop ? 0 : TimeInterval(journey.walkToStop?.seconds ?? 0) + safetyBuffer
        let walkToDestination = TimeInterval(journey.walkToDestination?.seconds ?? 0)
        let option = journey.busLeg?.option

        let catchStatus: CatchStatus
        let arrival: Date?
        if let busArrival = option?.estimatedArrivalAtStop {
            catchStatus = busArrival >= now.addingTimeInterval(requiredLead) ? .canCatch : .tooLate
            arrival = option?.rideSeconds.map { busArrival.addingTimeInterval(TimeInterval($0) + walkToDestination) }
        } else {
            catchStatus = .unknown
            arrival = nil
        }

        let isStale = option.map { now.timeIntervalSince($0.updatedAt) > staleThreshold } ?? false
        return RankedJourney(journey: journey, catchStatus: catchStatus, arrivalAtDestination: arrival, isStale: isStale)
    }
}

private extension RankedJourney {
    var catchRank: Int {
        switch catchStatus {
        case .canCatch: 0
        case .unknown: 1
        case .tooLate: 2
        }
    }
}
