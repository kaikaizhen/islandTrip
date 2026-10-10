import Foundation
import Testing
@testable import YiBuDa

/// 測試用方案：步行 → 公車（有上車站牌）→ 站內步行×2 → 等車 → 捷運 → 很短的步行 → 步行到目的地。
enum PlanFixture {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static func place(_ name: String?, _ lat: Double, _ lon: Double) -> PlanPlace {
        PlanPlace(name: name, coordinate: Coordinate(latitude: lat, longitude: lon))
    }

    static let start = place(nil, 25.0400, 121.5600)
    static let busStop = place("市政府", 25.0410, 121.5650)
    static let busAlight = place("忠孝復興", 25.0416, 121.5437)
    static let platform = place("忠孝復興站", 25.0415, 121.5438)
    static let metroAlight = place("台北車站", 25.0461, 121.5174)
    static let exit = place("台北車站 出口M3", 25.0463, 121.5176)
    static let end = place(nil, 25.0475, 121.5170)

    static var boardingStop: Stop {
        Stop(stopUID: "TPE1", name: "市政府", coordinate: busStop.coordinate, directionDescription: "往公館方向", dataTime: now)
    }

    static var oppositeStop: Stop {
        Stop(stopUID: "TPE2", name: "市政府", coordinate: Coordinate(latitude: 25.0413, longitude: 121.5651),
             directionDescription: "反方向", dataTime: now)
    }

    static func bus(withStop: Bool = true) -> TransitLeg {
        TransitLeg(mode: .bus, line: "忠孝幹線", headsign: "公館", from: busStop, to: busAlight,
                   departAt: now.addingTimeInterval(300), arriveAt: now.addingTimeInterval(900),
                   stops: [place("國父紀念館", 25.0414, 121.5577)],
                   realtime: LegRealtime(stopUID: "TPE1", arrivalAt: now.addingTimeInterval(240), statusNote: nil, updatedAt: now,
                                         city: "Taipei", routeUID: "TPE-ZX", subRouteUID: nil,
                                         boardingStop: withStop ? boardingStop : nil, oppositeStop: withStop ? oppositeStop : nil))
    }

    static let metro = TransitLeg(mode: .metro, line: "板南線", headsign: "往頂埔", from: platform, to: metroAlight,
                                  departAt: now.addingTimeInterval(1200), arriveAt: now.addingTimeInterval(1500),
                                  stops: [place("忠孝新生", 25.0423, 121.5328), place("善導寺", 25.0448, 121.5233)], realtime: nil)

    static func plan(busHasStop: Bool = true) -> TransitPlan {
        TransitPlan(id: "p", durationSeconds: 1800, startAt: now, endAt: now.addingTimeInterval(1800), transfers: 1, legs: [
            .walk(WalkPlanLeg(from: start, to: busStop, seconds: 300, meters: 400, inStation: false)),
            .transit(bus(withStop: busHasStop)),
            .walk(WalkPlanLeg(from: busAlight, to: platform, seconds: 60, meters: 0, inStation: true)),
            .walk(WalkPlanLeg(from: platform, to: platform, seconds: 30, meters: 0, inStation: true)),
            .wait(WaitPlanLeg(at: platform, seconds: 120)),
            .transit(metro),
            .walk(WalkPlanLeg(from: metroAlight, to: exit, seconds: 10, meters: 5, inStation: false)),
            .walk(WalkPlanLeg(from: exit, to: end, seconds: 240, meters: 300, inStation: false)),
        ], generatedAt: now)
    }

    static func flow(busHasStop: Bool = true) -> PlanNavigationFlow {
        PlanNavigationFlow(plan: plan(busHasStop: busHasStop), destinationName: "公司") { walk, name in
            WalkingJourneyPlanner.estimatedLeg(from: walk.from.coordinate, to: walk.to.coordinate, name: name)
        }
    }
}

struct PlanNavigationFlowTests {
    @Test func buildsStagesInOrder() {
        let flow = PlanFixture.flow()
        let kinds = flow.stages.map { stage -> String in
            switch stage {
            case .walk(let leg): "walk:\(leg.destinationName)"
            case .stationWalk: "station"
            case .boardingSide(let i): "side:\(i)"
            case .waiting(let i): "wait:\(i)"
            case .riding(let i): "ride:\(i)"
            case .arrived: "arrived"
            }
        }
        // 站內步行合併成一段；等車併入候車；5 公尺的步行不另外導航；最後一段走到目的地名稱。
        #expect(kinds == ["walk:市政府", "side:0", "wait:0", "ride:0", "station", "wait:1", "ride:1", "walk:公司", "arrived"])
    }

    @Test func busWithoutTDXStopSkipsBoardingSide() {
        let flow = PlanFixture.flow(busHasStop: false)
        #expect(!flow.stages.contains(.boardingSide(transitIndex: 0)))
        #expect(flow.stages[1] == .waiting(transitIndex: 0))
    }

    @Test func cannotGoBackAfterBoarding() {
        var flow = PlanFixture.flow()
        flow.next() // 走完（直線估計只有一步）
        #expect(flow.stage == .boardingSide(transitIndex: 0))
        #expect(flow.canGoBack)
        flow.next()
        flow.next()
        #expect(flow.stage == .riding(transitIndex: 0))
        #expect(!flow.canGoBack)
        flow.next()
        #expect(flow.stage == .stationWalk(from: "忠孝復興", to: "忠孝復興站", seconds: 90))
        // 下車後也不能退回搭乘
        #expect(!flow.canGoBack)
        let wentBack = flow.previous()
        #expect(!wentBack)
    }

    @Test func walkStepsAdvanceBeforeStage() {
        var flow = PlanFixture.flow()
        let instructions = [1, 2, 3].map { NavigationInstruction(id: "\($0)", kind: .straight, displayText: "\($0)", source: .mapKit) }
        flow.replaceWalk(at: 0, with: WalkLeg(destinationName: "市政府", seconds: 300, instructions: instructions))
        flow.next()
        #expect(flow.walkStep == 1)
        let wentBack = flow.previous()
        #expect(wentBack)
        #expect(flow.walkStep == 0)
        flow.advanceWalk(to: 2)
        flow.advanceWalk(to: 1) // 只往前
        #expect(flow.walkStep == 2)
        flow.next()
        #expect(flow.stage == .boardingSide(transitIndex: 0))
        // 退回步行時回到最後一步
        flow.previous()
        #expect(flow.walkStep == 2)
    }

    @Test func progressAndUpcomingTransit() {
        var flow = PlanFixture.flow()
        #expect(flow.transitProgress == nil)
        #expect(flow.upcomingTransit?.line == "忠孝幹線")
        flow.next()
        #expect(flow.transitProgress == "第 1 段車，共 2 段")
        for _ in 0..<4 { flow.next() }
        #expect(flow.stage == .waiting(transitIndex: 1))
        #expect(flow.transitProgress == "第 2 段車，共 2 段")
        #expect(flow.upcomingTransit?.line == "板南線")
    }

    @Test func arrivedIsTerminal() {
        var flow = PlanFixture.flow()
        while flow.stage != .arrived { flow.next() }
        let moved = flow.next()
        #expect(!moved)
    }
}

struct AlightReminderTests {
    let reminder = AlightReminder()
    let now = PlanFixture.now

    func sample(_ coordinate: Coordinate, accuracy: Double = 10) -> LocationSample {
        LocationSample(coordinate: coordinate, horizontalAccuracy: accuracy, timestamp: now)
    }

    @Test func gpsAtBoardingStopIsNotApproachingAndHasNoCount() {
        let status = reminder.status(for: PlanFixture.metro, sample: sample(PlanFixture.platform.coordinate), now: now)
        #expect(status == .init(isApproaching: false, source: .gps, remainingStops: nil))
    }

    @Test func gpsMidwayCountsRemainingStops() {
        // 忠孝新生：後面還有善導寺、台北車站
        let status = reminder.status(for: PlanFixture.metro, sample: sample(Coordinate(latitude: 25.0423, longitude: 121.5328)), now: now)
        #expect(status == .init(isApproaching: false, source: .gps, remainingStops: 2))
    }

    @Test func legWithoutIntermediateStopsDoesNotAlertAtBoarding() {
        var leg = PlanFixture.bus()
        leg.stops = []
        let atBoarding = reminder.status(for: leg, sample: sample(leg.from.coordinate), now: now)
        #expect(!atBoarding.isApproaching)
        #expect(atBoarding.remainingStops == nil)
        let nearAlight = reminder.status(for: leg, sample: sample(leg.to.coordinate), now: now)
        #expect(nearAlight.isApproaching)
    }

    @Test func gpsAtStopBeforeAlightIsApproaching() {
        // 善導寺是台北車站前一站
        let status = reminder.status(for: PlanFixture.metro, sample: sample(Coordinate(latitude: 25.0448, longitude: 121.5233)), now: now)
        #expect(status.isApproaching)
        #expect(status.source == .gps)
        #expect(status.remainingStops == 1)
    }

    @Test func poorGPSFallsBackToSchedule() {
        let leg = PlanFixture.metro
        let early = reminder.status(for: leg, sample: sample(PlanFixture.platform.coordinate, accuracy: 500), now: now)
        #expect(early == .init(isApproaching: false, source: .schedule, remainingStops: nil))
        let late = reminder.status(for: leg, sample: nil, now: leg.arriveAt!.addingTimeInterval(-60))
        #expect(late == .init(isApproaching: true, source: .schedule, remainingStops: nil))
    }

    @Test func noGPSNoScheduleHasNoSource() {
        var leg = PlanFixture.metro
        leg.arriveAt = nil
        #expect(reminder.status(for: leg, sample: nil, now: now) == .init(isApproaching: false, source: nil, remainingStops: nil))
    }
}

struct BoardingSideResolverTests {
    @Test func answerBeatsGPS() {
        let result = BoardingSideResolver.resolve(answer: .nearbyIsOpposite, gpsEstimate: .sameSideAsCorrectStop, gpsAccuracy: 5,
                                                  stopSide: nil, lastEstimate: nil)
        #expect(result == .known(needsToCross: true, source: .manual))
    }

    @Test func gpsBeatsStopData() {
        let result = BoardingSideResolver.resolve(answer: nil, gpsEstimate: .sameSideAsCorrectStop, gpsAccuracy: 7.6,
                                                  stopSide: .confirmed(needsToCross: true, guidance: ""), lastEstimate: nil)
        #expect(result == .known(needsToCross: false, source: .gps(accuracy: 8)))
    }

    @Test func asksWithReasonWhenUncertain() {
        let result = BoardingSideResolver.resolve(answer: nil, gpsEstimate: nil, gpsAccuracy: nil, stopSide: nil,
                                                  lastEstimate: .uncertain("定位不夠準"))
        #expect(result == .ask(reason: "定位不夠準"))
    }
}

@MainActor
struct PlanNavigationViewModelTests {
    final class RecordingPlanner: TransitPlanning, @unchecked Sendable {
        var refreshCount = 0
        func plans(from origin: Place, to destination: Place) async throws -> [TransitPlan] { [] }
        func refreshed(_ realtime: LegRealtime) async throws -> LegRealtime {
            refreshCount += 1
            var copy = realtime
            copy.arrivalAt = PlanFixture.now.addingTimeInterval(60)
            return copy
        }
    }

    let origin = Place(id: "o", name: "家", coordinate: PlanFixture.start.coordinate)
    let destination = Place(id: "d", name: "公司", coordinate: PlanFixture.end.coordinate)

    func makeViewModel(planner: RecordingPlanner = RecordingPlanner(), now: Date = PlanFixture.now) -> PlanNavigationViewModel {
        PlanNavigationViewModel(plan: PlanFixture.plan(), origin: origin, destination: destination, planner: planner, now: { now })
    }

    @Test func walksThroughWholePlanManually() async {
        let viewModel = makeViewModel()
        await viewModel.start()
        #expect(viewModel.stage == .walk(viewModel.flow.currentWalk!))
        #expect(viewModel.nextStepText == "到 市政府 搭 公車 忠孝幹線")
        #expect(viewModel.walkingPrimaryTitle == "我到了，下一步")
        viewModel.next()
        #expect(viewModel.boardingTarget?.stop.stopUID == "TPE1")
        #expect(viewModel.boardingTarget?.direction == "往公館")
        #expect(viewModel.boardingDetails?.oppositeStop?.stopUID == "TPE2")
        #expect(viewModel.boardingResolution == .ask(reason: nil))
        viewModel.answerBoardingSide(.nearbyIsCorrect)
        #expect(viewModel.boardingResolution == .known(needsToCross: false, source: .manual))
        viewModel.next()
        #expect(viewModel.stage == .waiting(transitIndex: 0))
        while viewModel.stage != .arrived { viewModel.next() }
        viewModel.cancel()
        #expect(viewModel.isFinished)
    }

    @Test func refreshUpdatesOnlyWaitingBusLeg() async {
        let planner = RecordingPlanner()
        let viewModel = makeViewModel(planner: planner)
        await viewModel.refreshArrival() // 還在步行：不查
        #expect(planner.refreshCount == 0)
        viewModel.next()
        viewModel.next()
        await viewModel.refreshArrival()
        #expect(planner.refreshCount == 1)
        #expect(viewModel.currentTransit?.realtime?.arrivalAt == PlanFixture.now.addingTimeInterval(60))
    }

    @Test func scheduleReminderLatchesAndAlertsOnce() {
        var clock = PlanFixture.now
        let viewModel = PlanNavigationViewModel(plan: PlanFixture.plan(), origin: origin, destination: destination,
                                                planner: RecordingPlanner(), now: { clock })
        viewModel.next(); viewModel.next(); viewModel.next()
        #expect(viewModel.stage == .riding(transitIndex: 0))
        #expect(!viewModel.alightStatus.isApproaching)
        #expect(viewModel.alightStatus.source == .schedule)
        clock = PlanFixture.now.addingTimeInterval(800) // 表定 900 秒到，提前 120 秒提醒
        viewModel.tick()
        #expect(viewModel.alightStatus.isApproaching)
        #expect(viewModel.alertCount == 1)
        viewModel.tick()
        #expect(viewModel.alertCount == 1)
        viewModel.next()
        #expect(!viewModel.alightStatus.isApproaching) // 下車後重置
    }
}

@Suite(.serialized)
struct RemoteTransitPlannerRealtimeTests {
    @Test func decodesBoardingAndOppositeStops() throws {
        let json = """
        {"city":"Taipei","stopUID":"TPE1","routeUID":"TPE-ZX","subRouteUID":null,
         "arrival":{"routeUID":"TPE-ZX","subRouteUID":null,"stopUID":"TPE1","plateNumber":null,"arrivalAt":"2026-10-10T00:05:00.000Z",
                    "status":"normal","isLastBus":false,"dataTime":"2026-10-10T08:00:00+08:00"},
         "boardingStop":{"uid":"TPE1","name":"市政府","lat":25.041,"lon":121.565,"bearing":"W","city":"Taipei"},
         "oppositeStop":{"uid":"TPE2","name":"市政府","lat":25.0413,"lon":121.5651,"bearing":"E","city":"Taipei"}}
        """
        let dto = try JSONDecoder().decode(PlanLegDTO.Realtime.self, from: Data(json.utf8))
        let realtime = RemoteTransitPlanner.realtime(from: dto, headsign: "公館")
        #expect(realtime.routeUID == "TPE-ZX")
        #expect(realtime.boardingStop?.directionDescription == "往公館方向")
        #expect(realtime.oppositeStop?.stopUID == "TPE2")
        #expect(realtime.oppositeStop?.directionDescription == "反方向（東行）")
    }

    @Test func oldBackendWithoutStopsStillDecodes() throws {
        let json = """
        {"city":"Taipei","stopUID":"TPE1","arrival":null}
        """
        let dto = try JSONDecoder().decode(PlanLegDTO.Realtime.self, from: Data(json.utf8))
        let realtime = RemoteTransitPlanner.realtime(from: dto, headsign: nil)
        #expect(realtime.boardingStop == nil)
        #expect(realtime.routeUID == "")
        #expect(realtime.statusNote == "查無即時預估")
    }

    @Test func refreshPicksThisRouteOnly() {
        let base = PlanFixture.bus().realtime!
        let response = ArrivalsResponseDTO(generatedAt: "2026-10-10T00:00:00.000Z", arrivals: [
            ArrivalDTO(routeUID: "OTHER", subRouteUID: nil, stopUID: "TPE1", plateNumber: nil, arrivalAt: "2026-10-10T00:01:00.000Z",
                       status: "normal", isLastBus: false, dataTime: nil),
            ArrivalDTO(routeUID: "TPE-ZX", subRouteUID: nil, stopUID: "TPE1", plateNumber: nil, arrivalAt: nil,
                       status: "lastBusPassed", isLastBus: false, dataTime: nil),
        ])
        let updated = RemoteTransitPlanner.updating(base, with: response)
        #expect(updated.arrivalAt == nil)
        #expect(updated.statusNote == "末班車已過")
    }
}
