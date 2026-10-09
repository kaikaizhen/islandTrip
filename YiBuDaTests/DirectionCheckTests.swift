import Foundation
import Testing
@testable import YiBuDa

struct DirectionCheckTests {
    func heading(_ degrees: Double, accuracy: Double = 10) -> HeadingSample {
        HeadingSample(degrees: degrees, accuracy: accuracy)
    }

    @Test func alignedWithinToleranceIncludingWrapAround() {
        var check = DirectionCheck()
        #expect(check.update(heading: heading(355), walkBearing: 10) == .aligned)
        #expect(check.relativeAngle == 15)
    }

    @Test func tellsWhichWayToTurn() {
        var check = DirectionCheck()
        #expect(check.update(heading: heading(0), walkBearing: 90) == .turnRight)
        #expect(check.update(heading: heading(0), walkBearing: 270) == .turnLeft)
        #expect(check.update(heading: heading(0), walkBearing: 180) == .turnAround)
    }

    // 滯後：對準後要偏超過 35 度才算偏掉，避免在邊界反覆震動。
    @Test func hysteresisPreventsFlickerAtBoundary() {
        var check = DirectionCheck()
        #expect(check.update(heading: heading(25), walkBearing: 0) == .turnLeft, "25 度還沒對準")
        #expect(check.update(heading: heading(15), walkBearing: 0) == .aligned)
        #expect(check.update(heading: heading(30), walkBearing: 0) == .aligned, "已對準時 30 度仍算對準")
        #expect(check.update(heading: heading(40), walkBearing: 0) == .turnLeft)
    }

    @Test func inaccurateCompassIsNotUsed() {
        var check = DirectionCheck()
        #expect(check.update(heading: heading(0, accuracy: 45), walkBearing: 0) == .unavailable)
        #expect(check.update(heading: heading(0, accuracy: -1), walkBearing: 0) == .unavailable)
        #expect(check.relativeAngle == nil)
        #expect(!check.isAligned)
    }

    @Test func walkBearingFollowsRouteNotStraightLine() throws {
        // L 形路徑：北行 100 公尺再東行；站在起點時應朝北，不是直線指向終點（東北）。
        let corner = offset(testOrigin, north: 100)
        let path = [testOrigin, corner, offset(corner, east: 100)]
        let atStart = try #require(DirectionCheck.walkBearing(along: path, from: testOrigin))
        #expect(abs(Geo.turnAngle(from: 0, to: atStart)) < 2)

        let pastCorner = try #require(DirectionCheck.walkBearing(along: path, from: offset(corner, east: 30)))
        #expect(abs(Geo.turnAngle(from: 90, to: pastCorner)) < 2)
    }

    @Test func walkBearingWithoutPositionUsesStepStart() throws {
        let path = [testOrigin, offset(testOrigin, east: 50)]
        let bearing = try #require(DirectionCheck.walkBearing(along: path, from: nil))
        #expect(abs(Geo.turnAngle(from: 90, to: bearing)) < 2)
        #expect(DirectionCheck.walkBearing(along: [testOrigin], from: nil) == nil)
    }
}

@MainActor
struct DirectionSessionTests {
    func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func journey() -> Journey {
        Journey(id: "w", origin: Place(id: "o", name: "起點", coordinate: testOrigin),
                destination: Place(id: "d", name: "終點", coordinate: finish),
                legs: [.walk(WalkLeg(destinationName: "終點", seconds: 200, instructions: threeStepInstructions))],
                computedAt: .now)
    }

    @Test func facingAlongRouteBecomesAligned() async {
        // 第一步往北走：先朝東（要往左轉），再朝北（對準）。
        let sut = NavigationSessionViewModel(
            journey: journey(), alternatives: [], transport: StubTransportProvider(),
            headingUpdates: {
                AsyncStream { continuation in
                    continuation.yield(HeadingSample(degrees: 90, accuracy: 10))
                    continuation.yield(HeadingSample(degrees: 5, accuracy: 10))
                    continuation.finish()
                }
            })
        await sut.start()
        await waitUntil { sut.directionGuidance == .aligned }
        #expect(sut.directionGuidance == .aligned)
    }

    @Test func noCompassMeansNoDirectionCard() async {
        let sut = NavigationSessionViewModel(journey: journey(), alternatives: [], transport: StubTransportProvider())
        await sut.start()
        #expect(sut.directionGuidance == nil)
    }

    @Test func mockStepsWithoutPathDoNotUseCompass() async throws {
        let journeys = MockTransitFixture.journeys(origin: MockTransitFixture.currentPlace,
                                                   destination: MockTransitFixture.taipeiMainStation, now: .now)
        let sut = NavigationSessionViewModel(
            journey: try #require(journeys.first), alternatives: [], transport: StubTransportProvider(),
            headingUpdates: { AsyncStream { $0.yield(HeadingSample(degrees: 0, accuracy: 5)) } })
        await sut.start()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(sut.directionGuidance == nil)
    }
}
