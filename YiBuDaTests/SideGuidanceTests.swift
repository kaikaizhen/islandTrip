import Foundation
import Testing
@testable import YiBuDa

struct TurnSideAdviceTests {
    @Test func asksWhenSideUnknownAndOnlyForTurns() {
        #expect(TurnSideAdvice.advice(for: .turnRight, userSide: nil) == .askSide(turn: .right))
        #expect(TurnSideAdvice.advice(for: .straight, userSide: nil) == .none)
        #expect(TurnSideAdvice.advice(for: .arrive, userSide: .left) == .none)
    }

    // D3 的情境：要右轉進巷子，但人在左側 → 先在路口過馬路。
    @Test func oppositeSideMustCrossAtIntersectionFirst() {
        #expect(TurnSideAdvice.advice(for: .turnRight, userSide: .left) == .crossFirst(turn: .right))
        #expect(TurnSideAdvice.advice(for: .slightLeft, userSide: .right) == .crossFirst(turn: .left))
        #expect(TurnSideAdvice.advice(for: .turnLeft, userSide: .left) == .sameSide(turn: .left))
    }

    @Test func sideAfterTurningFollowsTurnDirection() {
        #expect(TurnSideAdvice.sideAfterTurning(.turnRight, previous: .left) == .right)
        #expect(TurnSideAdvice.sideAfterTurning(.turnLeft, previous: nil) == .left)
        #expect(TurnSideAdvice.sideAfterTurning(.straight, previous: .left) == .left)
        #expect(TurnSideAdvice.sideAfterTurning(.uTurn, previous: .left) == nil)
    }
}

struct BoardingSideEstimatorTests {
    let stops = MockTransitFixture.stops(dataTime: .now)
    var correct: Stop { stops[MockTransitFixture.StopID.cityHallToTPE]! }
    var opposite: Stop { stops[MockTransitFixture.StopID.cityHallToBanqiao]! }

    func estimate(near stop: Stop, towardsOther: Double = 0, accuracy: Double = 5) -> BoardingSideEstimator.Estimate {
        let other = stop.stopUID == correct.stopUID ? opposite : correct
        let point = Geo.point(along: [stop.coordinate, other.coordinate], meters: towardsOther) ?? stop.coordinate
        return BoardingSideEstimator.estimate(user: sample(point, accuracy: accuracy), correctStop: correct, oppositeStop: opposite)
    }

    @Test func standingAtEachStopIsRecognised() {
        #expect(estimate(near: correct) == .sameSideAsCorrectStop)
        #expect(estimate(near: opposite) == .oppositeSide)
    }

    // 計畫 4.2：定位誤差大於兩側站牌的間距時，不判斷。
    @Test func inaccurateFixIsUncertain() {
        let separation = Geo.distance(correct.coordinate, opposite.coordinate)
        guard case .uncertain = estimate(near: correct, accuracy: separation) else {
            Issue.record("誤差太大時不能下結論")
            return
        }
    }

    @Test func middleOfRoadIsUncertain() {
        let separation = Geo.distance(correct.coordinate, opposite.coordinate)
        guard case .uncertain = estimate(near: correct, towardsOther: separation / 2, accuracy: 3) else {
            Issue.record("在馬路中線附近不能下結論")
            return
        }
    }

    @Test func farFromStopsIsUncertain() {
        let far = sample(offset(correct.coordinate, north: 400))
        guard case .uncertain = BoardingSideEstimator.estimate(user: far, correctStop: correct, oppositeStop: opposite) else {
            Issue.record("離站牌太遠不判斷")
            return
        }
    }

    @Test func stabilizerNeedsThreeMatchingEstimates() {
        var stabilizer = SideEstimateStabilizer()
        #expect(stabilizer.add(.oppositeSide) == nil)
        #expect(stabilizer.add(.oppositeSide) == nil)
        #expect(stabilizer.add(.sameSideAsCorrectStop) == nil, "中間出現不同結論就重來")
        #expect(stabilizer.add(.sameSideAsCorrectStop) == nil)
        #expect(stabilizer.add(.sameSideAsCorrectStop) == .sameSideAsCorrectStop)
        #expect(stabilizer.add(.uncertain("x")) == nil)
    }
}

@MainActor
struct SideSessionTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func busJourney() throws -> (Journey, [Journey]) {
        let journeys = MockTransitFixture.journeys(origin: MockTransitFixture.currentPlace,
                                                   destination: MockTransitFixture.taipeiMainStation, now: now)
        let valid = TransitRankingService().rank(journeys, now: now).map(\.journey)
        return (try #require(valid.first { $0.busLeg?.option.routeName == "265" }), valid)
    }

    @Test func turningInfersSideForNextTurn() async throws {
        let sut = NavigationSessionViewModel(
            journey: Journey(id: "w", origin: Place(id: "o", name: "起點", coordinate: testOrigin),
                             destination: Place(id: "d", name: "終點", coordinate: finish),
                             legs: [.walk(WalkLeg(destinationName: "終點", seconds: 200, instructions: threeStepInstructions))],
                             computedAt: now),
            alternatives: [], transport: StubTransportProvider())
        await sut.start()
        #expect(sut.turnAdvice == .askSide(turn: .right))

        sut.setWalkingSide(.left)
        #expect(sut.turnAdvice == .crossFirst(turn: .right))

        sut.nextStep()  // 完成右轉 → 在右邊；下一步要左轉
        #expect(sut.walkingSide == .right)
        #expect(sut.turnAdvice == .crossFirst(turn: .left))

        sut.previousStep()
        #expect(sut.walkingSide == nil, "往回走就不確定")
    }

    @Test func manualAnswerOverridesStopData() async throws {
        let (journey, alternatives) = try busJourney()
        let sut = NavigationSessionViewModel(journey: journey, alternatives: alternatives, transport: StubTransportProvider())
        await sut.start()
        sut.nextStep(); sut.nextStep(); sut.nextStep()
        #expect(sut.boardingResolution == .known(needsToCross: true, source: .stopData))

        sut.answerBoardingSide(.nearbyIsCorrect)
        #expect(sut.boardingResolution == .known(needsToCross: false, source: .manual))
        sut.answerBoardingSide(.cannotSeeSign)
        #expect(sut.boardingResolution == .cannotTell)
        sut.answerBoardingSide(nil)
        #expect(sut.boardingResolution == .known(needsToCross: true, source: .stopData))
    }

    @Test func stableGPSNearCorrectStopSaysNoCrossingNeeded() async throws {
        let (journey, alternatives) = try busJourney()
        let correct = try #require(journey.busLeg?.boardingStop)
        let atStop = (0..<4).map { _ in sample(correct.coordinate, accuracy: 4) }
        let location = FakeLocationProvider(updates: atStop)
        let sut = NavigationSessionViewModel(journey: journey, alternatives: alternatives, transport: StubTransportProvider(),
                                             locationUpdates: { location.liveUpdates() })
        // 模擬步行段沒有路徑，所以手動走到上車側確認畫面；GPS 仍用來判斷左右側。
        await sut.start()
        await waitUntil { sut.gpsBoardingEstimate != nil }
        sut.nextStep(); sut.nextStep(); sut.nextStep()
        #expect(sut.phase == .checkingBoardingSide)
        guard case .known(needsToCross: false, source: .gps) = sut.boardingResolution else {
            Issue.record("站在正確站牌旁，GPS 應判斷不用過馬路：\(sut.boardingResolution)")
            return
        }
    }
}
