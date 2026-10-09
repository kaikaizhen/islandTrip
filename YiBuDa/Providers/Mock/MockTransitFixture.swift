import Foundation

/// 模擬資料：一個上車站（市政府站，往台北車站方向）與馬路對面同名的反方向站牌。
/// 所有內容都是模擬，不代表真實班次、路線或站點位置。
enum MockTransitFixture {
    static let currentPlace = Place(id: "mock.current", name: "目前位置（模擬）",
                                    coordinate: Coordinate(latitude: 25.0408, longitude: 121.5654))
    static let taipeiMainStation = Place(id: "mock.tpe", name: "台北車站",
                                         coordinate: Coordinate(latitude: 25.0478, longitude: 121.5170))

    static let favorites: [Place] = [
        Place(id: "mock.home", name: "家", coordinate: Coordinate(latitude: 25.0330, longitude: 121.5430), kind: .home),
        Place(id: "mock.work", name: "公司", coordinate: Coordinate(latitude: 25.0478, longitude: 121.5170), kind: .work),
        Place(id: "mock.school", name: "學校", coordinate: Coordinate(latitude: 25.0173, longitude: 121.5397), kind: .school),
    ]

    static let searchablePlaces: [Place] = [
        taipeiMainStation,
        Place(id: "mock.taipei101", name: "台北 101", coordinate: Coordinate(latitude: 25.0340, longitude: 121.5645)),
        Place(id: "mock.ntuh", name: "台大醫院", coordinate: Coordinate(latitude: 25.0405, longitude: 121.5190)),
    ]

    // MARK: 站牌

    enum StopID {
        static let cityHallToTPE = "MOCK-CityHall-E"
        static let cityHallToBanqiao = "MOCK-CityHall-W"
        static let tpeMain = "MOCK-TPE-Main"
        static let tpeMainToBanqiao = "MOCK-TPE-Main-W"
    }

    static func stops(dataTime: Date) -> [String: Stop] {
        let list = [
            Stop(stopUID: StopID.cityHallToTPE, name: "市政府站", coordinate: Coordinate(latitude: 25.0410, longitude: 121.5660),
                 directionDescription: "往台北車站方向", dataTime: dataTime),
            Stop(stopUID: StopID.cityHallToBanqiao, name: "市政府站", coordinate: Coordinate(latitude: 25.0412, longitude: 121.5660),
                 directionDescription: "往板橋方向", dataTime: dataTime),
            Stop(stopUID: StopID.tpeMain, name: "台北車站", coordinate: Coordinate(latitude: 25.0477, longitude: 121.5173),
                 directionDescription: "往台北車站方向", dataTime: dataTime),
            Stop(stopUID: StopID.tpeMainToBanqiao, name: "台北車站", coordinate: Coordinate(latitude: 25.0479, longitude: 121.5173),
                 directionDescription: "往板橋方向", dataTime: dataTime),
        ]
        return Dictionary(uniqueKeysWithValues: list.map { ($0.stopUID, $0) })
    }

    // MARK: 停靠模式

    static func pattern(route: String, toTPE: Bool) -> RoutePattern {
        toTPE
            ? RoutePattern(patternId: "\(route)-E", routeId: route, routeName: route, directionName: "往台北車站",
                           stopUIDs: ["MOCK-Songshan", StopID.cityHallToTPE, "MOCK-Zhongxiao", StopID.tpeMain])
            : RoutePattern(patternId: "\(route)-W", routeId: route, routeName: route, directionName: "往板橋",
                           stopUIDs: ["MOCK-Songshan-W", StopID.tpeMainToBanqiao, StopID.cityHallToBanqiao, "MOCK-Banqiao"])
    }

    // MARK: 步行

    static let walkToStop = WalkLeg(destinationName: "市政府站", seconds: 180, instructions: [
        NavigationInstruction(id: "w1", kind: .straight, displayText: "往前直走 120 公尺", distanceMeters: 120,
                              safetyNote: nil, source: .mock),
        NavigationInstruction(id: "w2", kind: .turnRight, displayText: "到路口右轉", distanceMeters: 30,
                              safetyNote: "注意轉彎車輛", source: .mock),
        NavigationInstruction(id: "w3", kind: .crossStreet, displayText: "走到前方行人穿越道，過到對面", distanceMeters: 40,
                              safetyNote: "請走行人穿越道，不要直接穿越車道", source: .mock),
    ])

    static let walkToDestination = WalkLeg(destinationName: "台北車站", seconds: 240, instructions: [
        NavigationInstruction(id: "d1", kind: .straight, displayText: "下車後往前直走 200 公尺", distanceMeters: 200,
                              safetyNote: nil, source: .mock),
        NavigationInstruction(id: "d2", kind: .arrive, displayText: "目的地在右手邊", distanceMeters: nil,
                              safetyNote: nil, source: .mock),
    ])

    // MARK: 方案

    struct Candidate {
        var route: String
        var toTPE: Bool
        var minutesUntilBus: Double?
        var rideMinutes: Int
        var dataAgeSeconds: TimeInterval = 20
    }

    /// 307 先到但走不到；265 較晚到站卻較早抵達目的地；212 資料過期；671 查無預估；
    /// 另一班 307 在對面反方向站牌（不可列為可搭）。
    static let candidates: [Candidate] = [
        Candidate(route: "307", toTPE: true, minutesUntilBus: 2, rideMinutes: 15),
        Candidate(route: "212", toTPE: true, minutesUntilBus: 6, rideMinutes: 18, dataAgeSeconds: 300),
        Candidate(route: "265", toTPE: true, minutesUntilBus: 8, rideMinutes: 12),
        Candidate(route: "671", toTPE: true, minutesUntilBus: nil, rideMinutes: 14),
        Candidate(route: "307", toTPE: false, minutesUntilBus: 4, rideMinutes: 15),
    ]

    static func journeys(origin: Place, destination: Place, now: Date) -> [Journey] {
        let stops = stops(dataTime: now)
        return candidates.map { candidate in
            let pattern = pattern(route: candidate.route, toTPE: candidate.toTPE)
            let boarding = candidate.toTPE ? StopID.cityHallToTPE : StopID.cityHallToBanqiao
            let alighting = StopID.tpeMain
            let option = BoardingOption(
                id: "\(pattern.patternId)@\(boarding)",
                routeId: candidate.route, routeName: candidate.route, patternId: pattern.patternId,
                direction: pattern.directionName, boardingStopUID: boarding, alightingStopUID: alighting,
                estimatedArrivalAtStop: candidate.minutesUntilBus.map { now.addingTimeInterval($0 * 60) },
                etaSource: candidate.minutesUntilBus == nil ? .unknown : .realTime,
                updatedAt: now.addingTimeInterval(-candidate.dataAgeSeconds),
                rideSeconds: candidate.rideMinutes * 60
            )
            let bus = BusLeg(option: option, boardingStop: stops[boarding]!, alightingStop: stops[alighting]!, pattern: pattern)
            return Journey(id: option.id, origin: origin, destination: destination,
                           legs: [.walk(walkToStop), .bus(bus), .walk(walkToDestination)], computedAt: now)
        }
    }

    static func arrivals(stopUID: String, now: Date) -> [StopArrival] {
        candidates
            .filter { ($0.toTPE ? StopID.cityHallToTPE : StopID.cityHallToBanqiao) == stopUID }
            .map { candidate in
                StopArrival(
                    patternId: pattern(route: candidate.route, toTPE: candidate.toTPE).patternId,
                    estimatedArrival: candidate.minutesUntilBus.map { now.addingTimeInterval($0 * 60) },
                    etaSource: candidate.minutesUntilBus == nil ? .unknown : .realTime,
                    updatedAt: now.addingTimeInterval(-candidate.dataAgeSeconds)
                )
            }
    }

    static func stopDetails(stopUID: String, now: Date) -> StopDetails? {
        let stops = stops(dataTime: now)
        guard let stop = stops[stopUID] else { return nil }
        switch stopUID {
        case StopID.cityHallToTPE:
            return StopDetails(stop: stop, oppositeStop: stops[StopID.cityHallToBanqiao],
                               side: .confirmed(needsToCross: true, guidance: "請走到前方行人穿越道，再前往對向站牌"))
        case StopID.cityHallToBanqiao:
            return StopDetails(stop: stop, oppositeStop: stops[StopID.cityHallToTPE], side: .unknown)
        default:
            return StopDetails(stop: stop, oppositeStop: nil, side: .unknown)
        }
    }
}
