import Foundation
import Testing
@testable import YiBuDa

/// Phase 5：軌道即時、轉乘來不及與重新規劃、使用者偏好。
struct RailRealtimeTests {
    let now = PlanFixture.now

    func rail(minutes: Double, delay: Int?, trainNo: String? = nil) -> RailLegRealtime {
        RailLegRealtime(system: trainNo == nil ? .trtc : .tra, stationID: "S", expectedAt: now.addingTimeInterval(minutes * 60),
                        delayMinutes: delay, trainNo: trainNo, destination: "頂埔")
    }

    @Test func railLegIsRealtimeWithDelayText() {
        var leg = PlanFixture.metro
        leg.railRealtime = rail(minutes: 3, delay: nil)
        #expect(PlanFormat.isRealtime(leg))
        #expect(PlanFormat.boardingTime(leg, now: now) == "即時：約 3 分鐘開")
        leg.railRealtime = rail(minutes: 8, delay: 5, trainNo: "1234")
        #expect(PlanFormat.boardingTime(leg, now: now) == "即時：約 8 分鐘開（誤點 5 分）")
        leg.railRealtime = rail(minutes: 8, delay: 0, trainNo: "1234")
        #expect(PlanFormat.boardingTimeWithoutTag(leg, now: now) == "約 8 分鐘開（準點）")
    }

    @Test func delayShiftsExpectedArrival() {
        var leg = PlanFixture.metro
        #expect(leg.expectedArrival == leg.arriveAt)
        leg.railRealtime = rail(minutes: 8, delay: 5, trainNo: "1234")
        #expect(leg.expectedArrival == leg.arriveAt?.addingTimeInterval(300))
    }

    @Test func decodesRailRealtimeAndToleratesUnknownSystem() throws {
        let json = """
        {"kind":"transit","mode":"tra","line":"區間","headsign":"基隆","from":{"name":"臺北","lat":25.04,"lon":121.51},
         "to":{"name":"南港","lat":25.05,"lon":121.6},"departAt":"2026-10-10T00:10:00.000Z","arriveAt":"2026-10-10T00:20:00.000Z",
         "stops":[],"realtime":null,
         "railRealtime":{"system":"TRA","stationID":"1000","expectedAt":"2026-10-10T00:15:00.000Z","delayMinutes":5,"trainNo":"1234","destination":"基隆"}}
        """
        let leg = try #require(RemoteTransitPlanner.leg(try JSONDecoder().decode(PlanLegDTO.self, from: Data(json.utf8))))
        guard case .transit(let transit) = leg else { Issue.record("應為搭乘段"); return }
        #expect(transit.railRealtime?.system == .tra)
        #expect(transit.railRealtime?.delayMinutes == 5)
        let unknown = json.replacingOccurrences(of: "\"system\":\"TRA\"", with: "\"system\":\"MAGLEV\"")
        let fallback = try #require(RemoteTransitPlanner.leg(try JSONDecoder().decode(PlanLegDTO.self, from: Data(unknown.utf8))))
        guard case .transit(let plain) = fallback else { return }
        #expect(plain.railRealtime == nil) // 改回表定，不讓整份方案失敗
    }

    @Test func refreshMatchesSameTrainOrSameTerminus() {
        func departure(_ trainNo: String?, _ destination: String, minutes: Double, delay: Int? = nil, level: RailDataLevel = .realtime) -> RailDeparture {
            RailDeparture(id: UUID().uuidString, line: nil, trainNo: trainNo, destination: destination, direction: nil,
                          scheduledAt: nil, expectedAt: now.addingTimeInterval(minutes * 60), delayMinutes: delay,
                          headway: nil, status: .normal, dataLevel: level)
        }
        let tra = rail(minutes: 8, delay: 5, trainNo: "1234")
        let board = [departure("1236", "基隆", minutes: 2), departure("1234", "基隆", minutes: 12, delay: 9)]
        #expect(RemoteTransitPlanner.matching(tra, in: board, now: now)?.delayMinutes == 9)
        #expect(RemoteTransitPlanner.matching(tra, in: [departure("1236", "基隆", minutes: 2)], now: now) == nil)
        let metro = rail(minutes: 3, delay: nil)
        let metroBoard = [departure(nil, "亞東醫院", minutes: 1), departure(nil, "頂埔", minutes: 6), departure(nil, "頂埔", minutes: 2, level: .timetable)]
        #expect(RemoteTransitPlanner.matching(metro, in: metroBoard, now: now)?.expectedAt == now.addingTimeInterval(360))
    }
}

struct TransferCheckTests {
    let now = PlanFixture.now
    let place = PlanFixture.place

    /// 公車 → 走 5 分鐘 → 臺鐵（表定 now+20 分開）。
    func plan(busArrive: Double = 10, traDepart: Double = 20, nextMode: TransitMode = .tra) -> TransitPlan {
        let a = place("A", 25.0, 121.5), b = place("B", 25.01, 121.5), c = place("C", 25.02, 121.5)
        return TransitPlan(id: "t", durationSeconds: 3600, startAt: now, endAt: nil, transfers: 1, legs: [
            .transit(TransitLeg(mode: .bus, line: "307", headsign: nil, from: a, to: b, departAt: now.addingTimeInterval(120),
                                arriveAt: now.addingTimeInterval(busArrive * 60), stops: [], realtime: nil)),
            .walk(WalkPlanLeg(from: b, to: b, seconds: 300, meters: 300, inStation: false)),
            .wait(WaitPlanLeg(at: b, seconds: 60)),
            .transit(TransitLeg(mode: nextMode, line: "區間", headsign: "基隆", from: b, to: c, departAt: now.addingTimeInterval(traDepart * 60),
                                arriveAt: now.addingTimeInterval((traDepart + 15) * 60), stops: [], realtime: nil)),
        ], generatedAt: now)
    }

    func evaluate(_ plan: TransitPlan, current: TransitLeg? = nil, riding: Bool = true, pace: Double = 1.0, at time: Date? = nil) -> TransferWarning? {
        TransferCheck.evaluate(plan: plan, transitIndex: 0, currentLeg: current ?? plan.transitLegs[0], isRiding: riding,
                               now: time ?? now, paceFactor: pace)
    }

    @Test func enoughTimeNoWarning() {
        #expect(evaluate(plan()) == nil) // 10 分到 + 走 5 分 < 20 分
    }

    @Test func delayedBusMissesTrain() throws {
        let warning = try #require(evaluate(plan(busArrive: 16)))
        #expect(warning.kind == .likelyMissConnection)
        #expect(warning.line == "臺鐵 區間")
        #expect(warning.suggestsReplan)
        #expect(!warning.basedOnRealtime)
    }

    @Test func slowPaceMakesItTight() throws {
        // 13 分到 + 走 5 分 = 18 分，餘 2 分 → 不警告；慢慢走 5 分 × 1.3 = 6.5 分 → 19.5 分，只剩 30 秒 → 很緊
        #expect(evaluate(plan(busArrive: 13)) == nil)
        let warning = try #require(evaluate(plan(busArrive: 13), pace: 1.3))
        #expect(warning.kind == .tightConnection)
        #expect(!warning.suggestsReplan)
    }

    @Test func frequentMetroNotWarned() {
        #expect(evaluate(plan(busArrive: 30, nextMode: .metro)) == nil)
    }

    @Test func currentTrainAlreadyLeftWhileWaiting() throws {
        var leg = plan().transitLegs[0]
        leg.realtime = LegRealtime(stopUID: "S", arrivalAt: now.addingTimeInterval(-180), statusNote: nil, updatedAt: now)
        let warning = try #require(evaluate(plan(), current: leg, riding: false))
        #expect(warning.kind == .currentDeparted)
        #expect(warning.basedOnRealtime)
    }

    @Test func waitingUsesRealtimeDeparturePlusRideTime() throws {
        // 公車即時晚 9 分到站：預計 10+9 分到轉乘站，加步行 5 分 > 20 分
        var leg = plan().transitLegs[0]
        leg.realtime = LegRealtime(stopUID: "S", arrivalAt: now.addingTimeInterval(11 * 60), statusNote: nil, updatedAt: now)
        let warning = try #require(evaluate(plan(), current: leg, riding: false))
        #expect(warning.kind == .likelyMissConnection)
        #expect(warning.basedOnRealtime)
    }
}

struct PlanPreferenceTests {
    let now = PlanFixture.now

    func plan(_ id: String, end: Double, transfers: Int, walk: Int) -> TransitPlan {
        let p = PlanFixture.place(nil, 25, 121)
        return TransitPlan(id: id, durationSeconds: 0, startAt: now, endAt: now.addingTimeInterval(end * 60), transfers: transfers, legs: [
            .walk(WalkPlanLeg(from: p, to: p, seconds: walk, meters: walk, inStation: false)),
            .transit(TransitLeg(mode: .bus, line: "1", headsign: nil, from: p, to: p, departAt: nil, arriveAt: nil, stops: [], realtime: nil)),
        ], generatedAt: now)
    }

    @Test func sortsByPreference() {
        let plans = [plan("fast", end: 30, transfers: 2, walk: 900), plan("direct", end: 40, transfers: 0, walk: 600),
                     plan("short-walk", end: 45, transfers: 1, walk: 100)]
        #expect(TransitPlansViewModel.sorted(plans, by: .fastest).map(\.id) == ["fast", "direct", "short-walk"])
        #expect(TransitPlansViewModel.sorted(plans, by: .fewerTransfers).map(\.id) == ["direct", "short-walk", "fast"])
        #expect(TransitPlansViewModel.sorted(plans, by: .lessWalking).map(\.id) == ["short-walk", "direct", "fast"])
    }

    @MainActor
    @Test func settingsPersist() throws {
        let suite = "settings-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.planPreference == .fastest)
        #expect(settings.walkingPace == .normal)
        #expect(settings.bufferMinutes == 2)
        settings.planPreference = .lessWalking
        settings.walkingPace = .slow
        settings.bufferMinutes = 6
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.planPreference == .lessWalking)
        #expect(reloaded.walkingPace.factor == 1.3)
        #expect(reloaded.bufferMinutes == 6)
    }

    @Test func slowPaceStretchesEstimatedWalk() {
        let a = Coordinate(latitude: 25.0, longitude: 121.5), b = Coordinate(latitude: 25.001, longitude: 121.5)
        let normal = WalkingJourneyPlanner.estimatedLeg(from: a, to: b, name: "x")
        let slow = WalkingJourneyPlanner.estimatedLeg(from: a, to: b, name: "x", speed: 1.0 / 1.3)
        #expect(Double(slow.seconds) / Double(normal.seconds) > 1.25)
    }
}

@MainActor
struct ReplanTests {
    final class StubPlanner: TransitPlanning, @unchecked Sendable {
        var result: [TransitPlan]
        var lastOrigin: Place?
        init(_ result: [TransitPlan]) { self.result = result }
        func plans(from origin: Place, to destination: Place) async throws -> [TransitPlan] {
            lastOrigin = origin
            return result
        }
        func refreshed(_ realtime: LegRealtime) async throws -> LegRealtime { realtime }
    }

    let origin = Place(id: "o", name: "家", coordinate: PlanFixture.start.coordinate)
    let destination = Place(id: "d", name: "公司", coordinate: PlanFixture.end.coordinate)

    @Test func replanFromWaitingSwitchesToNewPlan() async throws {
        let replacement = try #require(try await MockTransitPlanner(now: { PlanFixture.now }).plans(from: origin, to: destination).first)
        let planner = StubPlanner([replacement])
        let viewModel = PlanNavigationViewModel(plan: PlanFixture.plan(), origin: origin, destination: destination,
                                                planner: planner, now: { PlanFixture.now })
        viewModel.next(); viewModel.next()
        #expect(viewModel.stage == .waiting(transitIndex: 0))
        #expect(viewModel.canReplan)
        await viewModel.replan()
        #expect(viewModel.plan.id == replacement.id)
        #expect(viewModel.flow.index == 0)
        #expect(viewModel.replanMessage?.contains("板南線") == true)
        // 沒有 GPS 時從目前車站重新規劃
        #expect(planner.lastOrigin?.name == "市政府")
    }

    @Test func cannotReplanWhileRiding() async {
        let planner = StubPlanner([])
        let viewModel = PlanNavigationViewModel(plan: PlanFixture.plan(), origin: origin, destination: destination,
                                                planner: planner, now: { PlanFixture.now })
        viewModel.next(); viewModel.next(); viewModel.next()
        #expect(viewModel.stage == .riding(transitIndex: 0))
        #expect(!viewModel.canReplan)
        await viewModel.replan()
        #expect(planner.lastOrigin == nil)
    }

    @Test func noAlternativeExplains() async {
        let viewModel = PlanNavigationViewModel(plan: PlanFixture.plan(), origin: origin, destination: destination,
                                                planner: StubPlanner([]), now: { PlanFixture.now })
        await viewModel.replan()
        #expect(viewModel.plan.id == "p")
        #expect(viewModel.replanMessage?.contains("找不到") == true)
    }
}

struct RailDiscoveryTests {
    let now = PlanFixture.now

    func departure(_ trainNo: String?, _ destination: String, scheduled: Double?, expected: Double, level: RailDataLevel = .realtime) -> RailDeparture {
        RailDeparture(id: UUID().uuidString, line: nil, trainNo: trainNo, destination: destination, direction: nil,
                      scheduledAt: scheduled.map { now.addingTimeInterval($0 * 60) }, expectedAt: now.addingTimeInterval(expected * 60),
                      delayMinutes: trainNo == nil ? nil : Int(expected - (scheduled ?? expected)), headway: nil, status: .normal, dataLevel: level)
    }

    @Test func traFoundWhenTrainAppearsOnBoard() {
        var leg = PlanFixture.metro
        leg.mode = .tra
        leg.departAt = now.addingTimeInterval(10 * 60)
        let station = RailStation(system: .tra, stationID: "1000", name: "臺北", coordinate: leg.from.coordinate)
        let board = [departure("1234", "基隆", scheduled: 10.5, expected: 14), departure("1236", "樹林", scheduled: 25, expected: 25)]
        let found = RemoteTransitPlanner.discover(leg, in: board, station: station, now: now)
        #expect(found?.trainNo == "1234")
        #expect(found?.delayMinutes == 3)
        // 只有時刻表資料時不算
        let timetableOnly = [departure("1234", "基隆", scheduled: 10, expected: 10, level: .timetable)]
        #expect(RemoteTransitPlanner.discover(leg, in: timetableOnly, station: station, now: now) == nil)
    }

    @Test func candidateStationsIncludeEveryLineAtInterchange() {
        let leg = PlanFixture.metro // 從「忠孝復興站」上車
        let stations = [
            RailStation(system: .trtc, stationID: "BL15", name: "忠孝復興", coordinate: leg.from.coordinate, distance: 10),
            RailStation(system: .trtc, stationID: "BR10", name: "忠孝復興", coordinate: leg.from.coordinate, distance: 10),
            RailStation(system: .tra, stationID: "1000", name: "臺北", coordinate: leg.from.coordinate, distance: 30),
            RailStation(system: .trtc, stationID: "BL14", name: "忠孝新生", coordinate: leg.from.coordinate, distance: 300),
        ]
        #expect(RemoteTransitPlanner.candidateStations(stations, for: leg).map(\.stationID) == ["BL15", "BR10"])
        #expect(RailName.normalized("臺北車站") == "台北")
        #expect(RailName.normalized("往南港展覽館") == "南港展覽館")
    }
}
