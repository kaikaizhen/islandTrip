import Foundation

/// 離線模擬的轉乘方案（不是真實班次）。一個捷運直達、一個公車轉捷運，
/// 公車段一段有即時到站、一段只有表定，方便檢查畫面標示。
struct MockTransitPlanner: TransitPlanning {
    var now: @Sendable () -> Date = { Date() }

    func plans(from origin: Place, to destination: Place) async throws -> [TransitPlan] {
        let now = now()
        let at = { (minutes: Double) in now.addingTimeInterval(minutes * 60) }
        let start = PlanPlace(name: nil, coordinate: origin.coordinate)
        let end = PlanPlace(name: nil, coordinate: destination.coordinate)
        let cityHall = PlanPlace(name: "市政府", coordinate: Coordinate(latitude: 25.0412, longitude: 121.5652))
        let taipeiMain = PlanPlace(name: "台北車站", coordinate: Coordinate(latitude: 25.0461, longitude: 121.5174))
        let busStop = PlanPlace(name: "捷運市政府站", coordinate: Coordinate(latitude: 25.0408, longitude: 121.5660))
        let busAlight = PlanPlace(name: "捷運忠孝復興站", coordinate: Coordinate(latitude: 25.0416, longitude: 121.5437))
        let zhongxiao = PlanPlace(name: "忠孝復興", coordinate: Coordinate(latitude: 25.0415, longitude: 121.5438))
        let midStops = [PlanPlace(name: "國父紀念館", coordinate: Coordinate(latitude: 25.0414, longitude: 121.5577)),
                        PlanPlace(name: "忠孝敦化", coordinate: Coordinate(latitude: 25.0414, longitude: 121.5508))]

        let metroOnly = TransitPlan(
            id: "mock-plan-metro", durationSeconds: 25 * 60, startAt: at(0), endAt: at(25), transfers: 0,
            legs: [
                .walk(WalkPlanLeg(from: start, to: cityHall, seconds: 360, meters: 420, inStation: false)),
                .transit(TransitLeg(mode: .metro, line: "板南線", headsign: "往頂埔", from: cityHall, to: taipeiMain,
                                    departAt: at(8), arriveAt: at(18), stops: midStops, realtime: nil)),
                .walk(WalkPlanLeg(from: taipeiMain, to: end, seconds: 300, meters: 350, inStation: false)),
            ],
            generatedAt: now
        )
        let busThenMetro = TransitPlan(
            id: "mock-plan-bus-metro", durationSeconds: 31 * 60, startAt: at(0), endAt: at(31), transfers: 1,
            legs: [
                .walk(WalkPlanLeg(from: start, to: busStop, seconds: 240, meters: 300, inStation: false)),
                .transit(TransitLeg(mode: .bus, line: "忠孝幹線", headsign: "往公館", from: busStop, to: busAlight,
                                    departAt: at(5), arriveAt: at(14), stops: [],
                                    realtime: LegRealtime(stopUID: "MOCK-BUS-1", arrivalAt: at(6), statusNote: nil, updatedAt: now))),
                .walk(WalkPlanLeg(from: busAlight, to: zhongxiao, seconds: 180, meters: 150, inStation: true)),
                .wait(WaitPlanLeg(at: zhongxiao, seconds: 120)),
                .transit(TransitLeg(mode: .metro, line: "板南線", headsign: "往頂埔", from: zhongxiao, to: taipeiMain,
                                    departAt: at(19), arriveAt: at(26), stops: [], realtime: nil)),
                .walk(WalkPlanLeg(from: taipeiMain, to: end, seconds: 300, meters: 350, inStation: false)),
            ],
            generatedAt: now
        )
        let busScheduledOnly = TransitPlan(
            id: "mock-plan-bus-scheduled", durationSeconds: 34 * 60, startAt: at(0), endAt: at(34), transfers: 0,
            legs: [
                .walk(WalkPlanLeg(from: start, to: busStop, seconds: 240, meters: 300, inStation: false)),
                .transit(TransitLeg(mode: .bus, line: "藍5", headsign: "往台北車站", from: busStop, to: taipeiMain,
                                    departAt: at(9), arriveAt: at(29), stops: [], realtime: nil)),
                .walk(WalkPlanLeg(from: taipeiMain, to: end, seconds: 300, meters: 350, inStation: false)),
            ],
            generatedAt: now
        )
        return [metroOnly, busThenMetro, busScheduledOnly]
    }
}
