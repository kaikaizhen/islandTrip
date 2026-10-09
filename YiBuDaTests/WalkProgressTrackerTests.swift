import Foundation
import Testing
@testable import YiBuDa

/// 合成 GPS 軌跡：沿路徑每隔幾公尺一個點，可加側向偏移模擬漂移。
func sample(_ c: Coordinate, accuracy: Double = 8) -> LocationSample {
    LocationSample(coordinate: c, horizontalAccuracy: accuracy, timestamp: .now)
}

/// 北行 120 公尺 → 右轉東行 80 公尺 → 左轉北行 60 公尺（三步）。
let corner1 = offset(testOrigin, north: 120)
let corner2 = offset(testOrigin, north: 120, east: 80)
let finish = offset(testOrigin, north: 180, east: 80)
let threeStepInstructions = WalkInstructionBuilder.instructions(
    for: route([testOrigin, corner1, corner2, finish]), destinationName: "測試終點")

func walk(along path: [Coordinate], every meters: Double = 10, sideways: Double = 0) -> [LocationSample] {
    let length = Geo.length(of: path)
    let points = stride(from: 0, through: length, by: meters).compactMap { Geo.point(along: path, meters: $0) }
    // 一定包含終點：走到目的地的人會停在那裡（浮點誤差可能讓 stride 少取最後一點）。
    return (points + [path.last].compactMap { $0 }).map { sample(offset($0, east: sideways)) }
}

struct WalkProgressTrackerTests {
    @Test func routeHasThreeTurnsForTheTest() {
        #expect(threeStepInstructions.map(\.kind) == [.turnRight, .turnLeft, .arrive])
    }

    @Test func walkingTheRouteAdvancesEachStepOnceInOrder() {
        var tracker = WalkProgressTracker(instructions: threeStepInstructions)
        var events: [WalkProgressTracker.Event] = []
        for point in walk(along: [testOrigin, corner1, corner2, finish]) {
            if let event = tracker.process(point) { events.append(event) }
        }
        #expect(events == [.advanced, .advanced, .completed])
    }

    @Test func singleDriftNearCornerDoesNotAdvance() {
        var tracker = WalkProgressTracker(instructions: threeStepInstructions)
        _ = tracker.process(sample(offset(testOrigin, north: 40)))
        #expect(tracker.process(sample(offset(corner1, north: -5))) == nil, "只有一筆接近轉彎點")
        #expect(tracker.process(sample(offset(testOrigin, north: 60))) == nil)
        #expect(tracker.step == 0)
    }

    @Test func sidewaysJitterIsNotOffRouteAndNeverSkips() {
        var tracker = WalkProgressTracker(instructions: threeStepInstructions)
        let firstLeg = [testOrigin, offset(corner1, north: -30)]
        for (index, point) in walk(along: firstLeg, every: 5).enumerated() {
            let jittered = sample(offset(point.coordinate, east: index.isMultiple(of: 2) ? 20 : -20), accuracy: 15)
            #expect(tracker.process(jittered) == nil)
        }
        #expect(tracker.step == 0)
        #expect(!tracker.isOffRoute)
    }

    @Test func jumpFarAheadAdvancesAtMostOneStep() {
        var tracker = WalkProgressTracker(instructions: threeStepInstructions)
        // 漂移到終點附近：離目前路段很遠，不應連跳兩步。
        _ = tracker.process(sample(finish))
        _ = tracker.process(sample(finish))
        #expect(tracker.step == 0)
    }

    @Test func inaccurateFixesWarnButNeverAdvance() {
        var tracker = WalkProgressTracker(instructions: threeStepInstructions)
        for _ in 0..<4 {
            #expect(tracker.process(sample(corner1, accuracy: 80)) == nil)
        }
        #expect(tracker.isLowAccuracy)
        #expect(tracker.step == 0)
        _ = tracker.process(sample(offset(testOrigin, north: 50)))
        #expect(!tracker.isLowAccuracy)
    }

    @Test func offRouteNeedsConsecutiveSamplesAndRecovers() {
        var tracker = WalkProgressTracker(instructions: threeStepInstructions)
        let away = sample(offset(testOrigin, north: 50, east: -70))
        #expect(tracker.process(away) == nil)
        #expect(tracker.process(away) == nil)
        #expect(tracker.process(away) == .wentOffRoute)
        #expect(tracker.isOffRoute)
        #expect(tracker.process(sample(offset(testOrigin, north: 55))) == .backOnRoute)
    }

    @Test func remainingDistanceIgnoresSmallIncreases() {
        var tracker = WalkProgressTracker(instructions: threeStepInstructions)
        _ = tracker.process(sample(offset(testOrigin, north: 60)))
        #expect(tracker.remainingMeters == 60)
        _ = tracker.process(sample(offset(testOrigin, north: 52)))
        #expect(tracker.remainingMeters == 60, "退後 8 公尺是漂移，不更新")
        _ = tracker.process(sample(offset(testOrigin, north: 70)))
        #expect(tracker.remainingMeters == 50)
    }

    @Test func relocateMovesForwardOnly() {
        var tracker = WalkProgressTracker(instructions: threeStepInstructions, step: 1)
        tracker.relocate(to: sample(offset(testOrigin, north: 30)))
        #expect(tracker.step == 1, "不會跳回已走過的步驟")
        tracker.relocate(to: sample(offset(corner2, north: 30)))
        #expect(tracker.step == 2)
    }

    @Test func mockInstructionsWithoutPathAreNotTracked() {
        var tracker = WalkProgressTracker(instructions: MockTransitFixture.walkToStop.instructions)
        #expect(!tracker.isTrackable)
        #expect(tracker.process(sample(testOrigin)) == nil)
    }
}

struct FakeWalkPlanner: JourneyWalkPlanning {
    var leg: WalkLeg
    func plan(_ journeys: [Journey]) async -> [Journey] { journeys }
    func walkLeg(from: Coordinate, to: Coordinate, name: String) async -> WalkLeg { leg }
}

@MainActor
struct GPSNavigationSessionTests {
    func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func walkOnlyJourney() -> Journey {
        Journey(id: "walk", origin: Place(id: "o", name: "起點", coordinate: testOrigin),
                destination: Place(id: "d", name: "測試終點", coordinate: finish),
                legs: [.walk(WalkLeg(destinationName: "測試終點", seconds: 200, instructions: threeStepInstructions))],
                computedAt: .now)
    }

    @Test func gpsWalkAdvancesThroughStepsToArrival() async {
        let trace = walk(along: [testOrigin, corner1, corner2, finish])
        let location = FakeLocationProvider(updates: trace)
        let sut = NavigationSessionViewModel(journey: walkOnlyJourney(), alternatives: [],
                                             transport: StubTransportProvider(),
                                             locationUpdates: { location.liveUpdates() })
        await sut.start()
        await waitUntil { sut.phase == .arrived }
        #expect(sut.phase == .arrived)
    }

    @Test func withoutGPSStaysManual() async {
        let sut = NavigationSessionViewModel(journey: walkOnlyJourney(), alternatives: [], transport: StubTransportProvider())
        await sut.start()
        #expect(!sut.isTrackingGPS)
        #expect(sut.liveRemainingMeters == nil)
        sut.nextStep(); sut.nextStep()
        #expect(sut.walkingPrimaryTitle == "我到了")
        sut.nextStep()
        #expect(sut.phase == .arrived)
    }

    @Test func offRouteThenRerouteStartsNewLegFromFirstStep() async {
        let away = sample(offset(testOrigin, north: 50, east: -70))
        let location = FakeLocationProvider(updates: [sample(offset(testOrigin, north: 20)), away, away, away])
        let newLeg = WalkLeg(destinationName: "測試終點", seconds: 120,
                             instructions: WalkInstructionBuilder.instructions(for: route([away.coordinate, finish]),
                                                                              destinationName: "測試終點"))
        let sut = NavigationSessionViewModel(journey: walkOnlyJourney(), alternatives: [],
                                             transport: StubTransportProvider(),
                                             locationUpdates: { location.liveUpdates() },
                                             walkPlanner: FakeWalkPlanner(leg: newLeg))
        await sut.start()
        await waitUntil { sut.isOffRoute }
        #expect(sut.isOffRoute)
        #expect(sut.canReroute)

        await sut.reroute()
        #expect(sut.phase == .walkingToStop(step: 0))
        #expect(sut.journey.walkToStop == newLeg)
        #expect(!sut.isOffRoute)
    }

    @Test func deniedLocationFallsBackToManualWithExplanation() async {
        struct DeniedLocation: LocationProviding {
            func currentLocation() async throws -> LocationSample { throw LocationError.denied }
            func liveUpdates() -> AsyncThrowingStream<LocationSample, Error> {
                AsyncThrowingStream { $0.finish(throwing: LocationError.denied) }
            }
        }
        let location = DeniedLocation()
        let sut = NavigationSessionViewModel(journey: walkOnlyJourney(), alternatives: [], transport: StubTransportProvider(),
                                             locationUpdates: { location.liveUpdates() })
        await sut.start()
        await waitUntil { sut.locationProblem != nil }
        #expect(sut.locationProblem?.contains("定位權限") == true)
        #expect(!sut.isTrackingGPS)
    }
}

struct WalkOnlyStateMachineTests {
    @Test func walkOnlyEndsAtArrivalWithoutTransitPhases() {
        var machine = NavigationStateMachine(walkToStopSteps: 2, walkToDestinationSteps: 0, hasTransit: false)
        machine.handle(.start)
        machine.handle(.nextStep)
        machine.handle(.nextStep)
        #expect(machine.phase == .arrived)
    }

    @Test func rerouteResetsToFirstStepOfSameLeg() {
        var machine = NavigationStateMachine(walkToStopSteps: 3, walkToDestinationSteps: 2)
        machine.handle(.start)
        machine.handle(.nextStep)
        let accepted = machine.handle(.rerouted(walkSteps: 4))
        #expect(accepted)
        #expect(machine.phase == .walkingToStop(step: 0))
        for _ in 0..<3 { machine.handle(.nextStep) }
        #expect(machine.phase == .walkingToStop(step: 3), "新路線有 4 步")
    }

    @Test func rerouteIgnoredOutsideWalking() {
        var machine = NavigationStateMachine(walkToStopSteps: 0, walkToDestinationSteps: 1)
        machine.handle(.start)
        let accepted = machine.handle(.rerouted(walkSteps: 2))
        #expect(!accepted)
        #expect(machine.phase == .checkingBoardingSide)
    }
}
