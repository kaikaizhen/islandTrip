import Foundation
import Testing
@testable import YiBuDa

/// 以公尺偏移建立座標，方便畫出測試用路線。
func offset(_ c: Coordinate, north: Double = 0, east: Double = 0) -> Coordinate {
    let metersPerDegreeLat = .pi * Geo.earthRadius / 180
    return Coordinate(latitude: c.latitude + north / metersPerDegreeLat,
                      longitude: c.longitude + east / (metersPerDegreeLat * cos(c.latitude * .pi / 180)))
}

let testOrigin = Coordinate(latitude: 25.0408, longitude: 121.5654)

/// 依序走過各點產生 MapKit 風格的步驟（每個轉折點開始新的一步）。
func route(_ corners: [Coordinate], names: [String] = []) -> WalkingRoute {
    let steps = zip(corners, corners.dropFirst()).enumerated().map { index, pair in
        WalkingRoute.Step(mapKitInstruction: names[safe: index] ?? "", distanceMeters: Int(Geo.distance(pair.0, pair.1)),
                          coordinates: [pair.0, pair.1])
    }
    // MapKit 第一步通常是距離 0 的起點，應被忽略。
    let start = WalkingRoute.Step(mapKitInstruction: "", distanceMeters: 0, coordinates: [corners[0], corners[0]])
    return WalkingRoute(coordinates: corners, expectedSeconds: 200, distanceMeters: Int(Geo.length(of: corners)),
                        steps: [start] + steps)
}

struct GeoTests {
    @Test func distanceAndBearing() {
        let north = offset(testOrigin, north: 100)
        let east = offset(testOrigin, east: 100)
        #expect(abs(Geo.distance(testOrigin, north) - 100) < 0.5)
        #expect(abs(Geo.bearing(from: testOrigin, to: north) - 0) < 0.5)
        #expect(abs(Geo.bearing(from: testOrigin, to: east) - 90) < 0.5)
    }

    @Test func turnAngleSignMeansDirection() {
        #expect(Geo.turnAngle(from: 0, to: 90) == 90)
        #expect(Geo.turnAngle(from: 0, to: 270) == -90)
        #expect(Geo.turnAngle(from: 350, to: 10) == 20)
    }

    @Test func projectionGivesOffsetAndProgress() throws {
        let path = [testOrigin, offset(testOrigin, north: 100)]
        let result = try #require(Geo.projection(of: offset(testOrigin, north: 40, east: 6), onto: path))
        #expect(abs(result.distance - 6) < 0.5)
        #expect(abs(result.along - 40) < 0.5)
    }
}

struct WalkInstructionBuilderTests {
    @Test func rightTurnThenArrive() {
        let corners = [testOrigin, offset(testOrigin, north: 120), offset(testOrigin, north: 120, east: 80)]
        let result = WalkInstructionBuilder.instructions(for: route(corners, names: ["沿忠孝東路走", "右轉進入松仁路"]),
                                                         destinationName: "市政府站")
        #expect(result.count == 2)
        #expect(result[0].kind == .turnRight)
        #expect(result[0].displayText == "往前走 120 公尺，到路口右轉")
        #expect(result[0].detailText == "右轉進入松仁路")
        #expect(result[1].kind == .arrive)
        #expect(result[1].displayText == "往前走 80 公尺，就到市政府站")
        #expect(result.allSatisfy { $0.source == .mapKit && $0.path.count >= 2 })
    }

    @Test func streetNameChangeIsMergedIntoOneStraight() {
        let corners = [testOrigin, offset(testOrigin, north: 50), offset(testOrigin, north: 120),
                       offset(testOrigin, north: 120, east: -60)]
        let result = WalkInstructionBuilder.instructions(for: route(corners), destinationName: "目的地")
        #expect(result.count == 2)
        #expect(result[0].kind == .turnLeft)
        #expect(result[0].distanceMeters == 120)
    }

    @Test func classifiesSlightTurnsAndUTurn() {
        let start = [testOrigin, offset(testOrigin, north: 100)]
        let corner = start[1]
        #expect(WalkInstructionBuilder.maneuver(after: start, before: [corner, offset(corner, north: 50, east: 40)]) == .slightRight)
        #expect(WalkInstructionBuilder.maneuver(after: start, before: [corner, offset(corner, north: 50, east: -40)]) == .slightLeft)
        #expect(WalkInstructionBuilder.maneuver(after: start, before: [corner, offset(corner, north: 5, east: 60)]) == .turnRight)
        #expect(WalkInstructionBuilder.maneuver(after: start, before: [corner, offset(corner, north: -60, east: 3)]) == .uTurn)
        #expect(WalkInstructionBuilder.maneuver(after: start, before: [corner, offset(corner, north: 60, east: 5)]) == .straight)
    }

    @Test func spokenDistanceRoundsToTensAndKilometres() {
        #expect(WalkInstructionBuilder.spoken(123) == "120 公尺")
        #expect(WalkInstructionBuilder.spoken(3) == "10 公尺")
        #expect(WalkInstructionBuilder.spoken(1250) == "1.2 公里")
    }
}

struct WalkingJourneyPlannerTests {
    let journeys = MockTransitFixture.journeys(origin: MockTransitFixture.currentPlace,
                                               destination: MockTransitFixture.taipeiMainStation, now: .now)

    @Test func replacesWalkLegsWithMapRoutes() async throws {
        let planned = await WalkingJourneyPlanner(routes: FakeWalkingRouteProvider()).plan(journeys)
        let walk = try #require(planned.first?.walkToStop)
        #expect(walk.seconds == 150)
        #expect(!walk.isEstimated)
        #expect(walk.instructions.allSatisfy { $0.source == .mapKit })
        #expect(planned.map { $0.busLeg?.option.id } == journeys.map { $0.busLeg?.option.id })
    }

    @Test func routingFailureGivesLabelledEstimate() async throws {
        let planned = await WalkingJourneyPlanner(routes: FakeWalkingRouteProvider(fails: true)).plan(journeys)
        let walk = try #require(planned.first?.walkToStop)
        #expect(walk.isEstimated)
        #expect(walk.instructions.count == 1)
        #expect(walk.instructions[0].source == .estimated)
        #expect(walk.instructions[0].detailText?.contains("估計") == true)
        #expect(walk.instructions[0].safetyNote?.contains("斑馬線") == true)
    }
}
