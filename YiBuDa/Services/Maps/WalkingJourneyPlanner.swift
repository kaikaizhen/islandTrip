import Foundation

/// 把方案中的步行段換成真實步行路線（起點 → 上車站、下車站 → 目的地）。
protocol JourneyWalkPlanning: Sendable {
    func plan(_ journeys: [Journey]) async -> [Journey]
}

struct WalkingJourneyPlanner: JourneyWalkPlanning {
    let routes: any WalkingRouteProviding
    /// 估計步行時間用的速度（公尺/秒），偏保守以照顧長輩。
    var estimatedWalkingSpeed = 1.0
    /// 直線距離換算實際步行距離的係數（要繞路、等紅綠燈）。
    var detourFactor = 1.4

    private struct Pair: Hashable {
        var from: Coordinate
        var to: Coordinate
        var name: String
    }

    func plan(_ journeys: [Journey]) async -> [Journey] {
        // 同一個上車站／下車站只算一次路線。
        var pairs = Set<Pair>()
        for journey in journeys {
            guard let bus = journey.busLeg else { continue }
            pairs.insert(Pair(from: journey.origin.coordinate, to: bus.boardingStop.coordinate, name: bus.boardingStop.name))
            pairs.insert(Pair(from: bus.alightingStop.coordinate, to: journey.destination.coordinate, name: journey.destination.name))
        }

        let legs = await withTaskGroup(of: (Pair, WalkLeg).self) { group in
            for pair in pairs {
                group.addTask { (pair, await leg(for: pair)) }
            }
            var result: [Pair: WalkLeg] = [:]
            for await (pair, leg) in group { result[pair] = leg }
            return result
        }

        return journeys.map { journey in
            guard let bus = journey.busLeg,
                  let toStop = legs[Pair(from: journey.origin.coordinate, to: bus.boardingStop.coordinate, name: bus.boardingStop.name)],
                  let toDestination = legs[Pair(from: bus.alightingStop.coordinate, to: journey.destination.coordinate,
                                                name: journey.destination.name)]
            else { return journey }
            var planned = journey
            planned.legs = [.walk(toStop), .bus(bus), .walk(toDestination)]
            return planned
        }
    }

    private func leg(for pair: Pair) async -> WalkLeg {
        do {
            let route = try await routes.walkingRoute(from: pair.from, to: pair.to)
            return WalkLeg(destinationName: pair.name, seconds: route.expectedSeconds,
                           instructions: WalkInstructionBuilder.instructions(for: route, destinationName: pair.name))
        } catch {
            return estimatedLeg(for: pair)
        }
    }

    /// 無法取得路線時的保守估計：明確標示是估計，不畫成精確路線。
    func estimatedLeg(from: Coordinate, to: Coordinate, name: String) -> WalkLeg {
        estimatedLeg(for: Pair(from: from, to: to, name: name))
    }

    private func estimatedLeg(for pair: Pair) -> WalkLeg {
        let meters = Geo.distance(pair.from, pair.to) * detourFactor
        let instruction = NavigationInstruction(
            id: "estimated-\(pair.name)", kind: .straight,
            displayText: "前往\(pair.name)（約 \(WalkInstructionBuilder.spoken(Int(meters))))",
            detailText: "無法取得步行路線，距離是估計值",
            distanceMeters: Int(meters), targetCoordinate: pair.to,
            safetyNote: "請在路口或斑馬線過馬路，並確認站牌名稱與方向",
            source: .estimated, path: [pair.from, pair.to]
        )
        return WalkLeg(destinationName: pair.name, seconds: Int((meters / estimatedWalkingSpeed).rounded()),
                       instructions: [instruction], isEstimated: true)
    }
}
