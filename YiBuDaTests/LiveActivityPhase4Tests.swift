import Foundation
import Testing
@testable import YiBuDa

/// Phase 4：導航狀態 → Live Activity 內容、提醒通知規則、同步協調。
struct NavigationAlertPolicyTests {
    typealias State = NavigationActivityAttributes.ContentState
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func walking(_ title: String, meters: Int?, maneuver: Maneuver = .turnRight) -> State {
        State(maneuver: maneuver, title: title, detail: "", distanceMeters: meters, nextStep: nil, updatedAt: now)
    }

    func waiting(arrival: Date?, scheduled: Bool = false) -> State {
        NavigationActivityMapper.waiting(route: "307", stopName: "市政府", direction: "往板橋", arrivalAt: arrival,
                                         isScheduled: scheduled, alightName: "台北車站", now: now)
    }

    func ids(_ commands: [NavigationAlertPolicy.Command]) -> [String] {
        commands.map { command in
            switch command {
            case .schedule(let notification, _): "+\(notification.identifier)"
            case .cancel(let ids): "-\(ids.joined(separator: ","))"
            }
        }
    }

    @Test func turnAlertOnceWhenNear() {
        let far = walking("前方右轉", meters: 80)
        let near = walking("前方右轉", meters: 20)
        #expect(ids(NavigationAlertPolicy.commands(from: far, to: near, now: now)) == ["+nav-turn"])
        // 同一步還在附近：不再提醒
        #expect(NavigationAlertPolicy.commands(from: near, to: walking("前方右轉", meters: 10), now: now).isEmpty)
        // 直走不提醒
        #expect(NavigationAlertPolicy.commands(from: far, to: walking("直走", meters: 10, maneuver: .straight), now: now).isEmpty)
    }

    @Test func busSoonScheduledTwoMinutesBeforeAndCancelledAfterBoarding() throws {
        let commands = NavigationAlertPolicy.commands(from: walking("到站", meters: 5), to: waiting(arrival: now.addingTimeInterval(600)), now: now)
        guard case .schedule(let notification, let delay) = try #require(commands.first) else {
            Issue.record("應排程通知")
            return
        }
        #expect(notification.identifier == NavigationAlertPolicy.busSoonID)
        #expect(delay == 480)
        // 到站時間沒變：不重排
        #expect(NavigationAlertPolicy.commands(from: waiting(arrival: now.addingTimeInterval(600)),
                                               to: waiting(arrival: now.addingTimeInterval(600)), now: now).isEmpty)
        let riding = NavigationActivityMapper.riding(route: "307", alightName: "台北車站", approaching: false,
                                                     remainingStops: nil, alightAt: nil, now: now)
        #expect(ids(NavigationAlertPolicy.commands(from: waiting(arrival: now.addingTimeInterval(600)), to: riding, now: now)) == ["-nav-bus-soon"])
    }

    @Test func scheduledArrivalSaysScheduled() throws {
        let commands = NavigationAlertPolicy.commands(from: nil, to: waiting(arrival: now.addingTimeInterval(600), scheduled: true), now: now)
        guard case .schedule(let notification, _) = try #require(commands.first) else { return }
        #expect(notification.body.contains("表定"))
    }

    @Test func alightPreScheduledThenImmediateOnApproach() {
        let riding = NavigationActivityMapper.riding(route: "板南線", alightName: "台北車站", approaching: false,
                                                     remainingStops: nil, alightAt: now.addingTimeInterval(900), now: now)
        let approaching = NavigationActivityMapper.riding(route: "板南線", alightName: "台北車站", approaching: true,
                                                          remainingStops: nil, alightAt: now.addingTimeInterval(900), now: now)
        #expect(NavigationAlertPolicy.commands(from: nil, to: riding, now: now)
            == [.schedule(LocalNotification(identifier: "nav-alight", title: "準備下車",
                                            body: "依預計時間快到了：在 台北車站 下車。請聽車上廣播確認站名。"), after: 780)])
        // 同一個 ID：立即通知取代預排的
        #expect(ids(NavigationAlertPolicy.commands(from: riding, to: approaching, now: now)) == ["+nav-alight"])
        // 下車後取消
        let walk = walking("直走", meters: 100, maneuver: .straight)
        #expect(ids(NavigationAlertPolicy.commands(from: approaching, to: walk, now: now)) == ["-nav-alight"])
    }

    @Test func arrivedCancelsEverything() {
        let arrived = NavigationActivityMapper.arrived("公司", now: now)
        #expect(ids(NavigationAlertPolicy.commands(from: walking("直走", meters: 5, maneuver: .straight), to: arrived, now: now))
            == ["-nav-turn,nav-bus-soon,nav-alight"])
    }
}

@MainActor
struct NavigationActivityMapperTests {
    let now = PlanFixture.now
    let origin = Place(id: "o", name: "家", coordinate: PlanFixture.start.coordinate)
    let destination = Place(id: "d", name: "公司", coordinate: PlanFixture.end.coordinate)

    final class NoopPlanner: TransitPlanning, @unchecked Sendable {
        func plans(from origin: Place, to destination: Place) async throws -> [TransitPlan] { [] }
        func refreshed(_ realtime: LegRealtime) async throws -> LegRealtime { realtime }
    }

    @Test func planStagesMapToD4Stages() {
        let viewModel = PlanNavigationViewModel(plan: PlanFixture.plan(), origin: origin, destination: destination,
                                                planner: NoopPlanner(), now: { [now] in now })
        var stages: [NavigationActivityAttributes.Stage] = []
        var actions: [NavigationActivityAttributes.Action?] = []
        while true {
            let state = NavigationActivityMapper.state(for: viewModel, now: now)
            stages.append(state?.stage ?? .arrived)
            actions.append(state?.action)
            if viewModel.stage == .arrived { break }
            viewModel.next()
        }
        #expect(stages == [.walking, .boardingSide, .waiting, .riding, .walking, .waiting, .riding, .walking, .arrived])
        #expect(actions == [nil, nil, .board, .alight, nil, .board, .alight, nil, nil])
    }

    @Test func waitingUsesLiveArrivalOrMarksScheduled() {
        let viewModel = PlanNavigationViewModel(plan: PlanFixture.plan(), origin: origin, destination: destination,
                                                planner: NoopPlanner(), now: { [now] in now })
        viewModel.next(); viewModel.next()
        let bus = NavigationActivityMapper.state(for: viewModel, now: now)
        #expect(bus?.arrivalAt == now.addingTimeInterval(240))
        #expect(bus?.arrivalIsScheduled == false)
        #expect(bus?.arrivalMinutes == 4)
        #expect(bus?.shortTitle == "等忠孝幹線")
        viewModel.next(); viewModel.next(); viewModel.next()
        let metro = NavigationActivityMapper.state(for: viewModel, now: now)
        #expect(metro?.arrivalAt == PlanFixture.metro.departAt)
        #expect(metro?.arrivalIsScheduled == true)
    }

    @Test func walkingDistanceRoundedToTenMeters() {
        let instruction = NavigationInstruction(id: "1", kind: .turnLeft, displayText: "前方左轉", distanceMeters: 123, source: .mapKit)
        let state = NavigationActivityMapper.walking(instruction, remaining: 47, next: nil, now: now)
        #expect(state.distanceMeters == 50)
        #expect(state.shortTitle == "左轉")
        #expect(state.detail == "還有 50 公尺")
    }

    @Test func longRouteNameShortenedForLiveActivity() {
        let state = NavigationActivityMapper.waiting(route: "小9(台灣好行-北投竹子湖)", stopName: "泉源3號橋", direction: "往致遠新村",
                                                     arrivalAt: nil, isScheduled: false, alightName: "北投", now: now)
        #expect(state.routeName == "小9")
        #expect(state.title == "等 小9")
    }

    @Test func sameContentIgnoresUpdatedAt() {
        let a = NavigationActivityMapper.arrived("公司", now: now)
        var b = a
        b.updatedAt = now.addingTimeInterval(60)
        #expect(a.sameContent(as: b))
        b.detail = "別的地方"
        #expect(!a.sameContent(as: b))
    }
}

@MainActor
struct NavigationActivityCoordinatorTests {
    let now = PlanFixture.now
    let origin = Place(id: "o", name: "家", coordinate: PlanFixture.start.coordinate)
    let destination = Place(id: "d", name: "公司", coordinate: PlanFixture.end.coordinate)

    @Test func followsStateAndEndsActivity() async throws {
        let controller = FakeLiveActivityController()
        let notifications = FakeNotificationScheduler(permission: .authorized)
        let coordinator = NavigationActivityCoordinator(controller: controller, notifications: notifications,
                                                        actions: NavigationActionCenter(), heartbeat: .seconds(3600), now: { [now] in now })
        let viewModel = PlanNavigationViewModel(plan: PlanFixture.plan(), origin: origin, destination: destination,
                                                planner: NavigationActivityMapperTests.NoopPlanner(), now: { [now] in now })
        coordinator.start(destinationName: "公司", isSimulated: true, state: { now in
            NavigationActivityMapper.state(for: viewModel, now: now)
        }, onAction: { _ in })
        try await waitUntil { controller.states.count == 1 }
        #expect(controller.startedAttributes?.isSimulated == true)
        #expect(controller.states.last?.stage == .walking)

        viewModel.next()
        try await waitUntil { controller.states.count == 2 }
        #expect(controller.states.last?.stage == .boardingSide)

        viewModel.next() // 候車：排「車快到了」
        try await waitUntil { await notifications.scheduled.contains { $0.0.identifier == NavigationAlertPolicy.busSoonID } }

        await coordinator.stop()
        #expect(controller.endCount == 1)
        #expect(await notifications.cancelled.contains(NavigationAlertPolicy.busSoonID))
    }

    @Test func lockScreenButtonReachesHandler() async {
        let center = NavigationActionCenter()
        let coordinator = NavigationActivityCoordinator(controller: FakeLiveActivityController(), notifications: nil,
                                                        actions: center, heartbeat: .seconds(3600), now: { [now] in now })
        var received: [NavigationActivityAttributes.Action] = []
        coordinator.start(destinationName: "公司", isSimulated: true, state: { _ in nil }, onAction: { received.append($0) })
        center.send(.board)
        await coordinator.stop()
        center.send(.alight) // 結束後不再處理
        #expect(received == [.board])
    }

    @Test func doesNotStartWhenActivitiesDisabled() async throws {
        let controller = FakeLiveActivityController()
        controller.areActivitiesEnabled = false
        let coordinator = NavigationActivityCoordinator(controller: controller, notifications: nil,
                                                        actions: NavigationActionCenter(), heartbeat: .seconds(3600), now: { [now] in now })
        coordinator.start(destinationName: "公司", isSimulated: false, state: { now in
            NavigationActivityMapper.arrived("公司", now: now)
        }, onAction: { _ in })
        try await Task.sleep(for: .milliseconds(50))
        #expect(controller.states.isEmpty)
        await coordinator.stop()
    }

    private func waitUntil(_ condition: @escaping () async -> Bool) async throws {
        for _ in 0..<100 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("等待逾時")
    }
}
