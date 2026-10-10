import Foundation
import Testing
@testable import YiBuDa

/// 後端 /v1/plan 回應範例（格式同真實回應；內容為合成資料）。
enum PlanSamples {
    static let plan = """
    {"generatedAt":"2026-10-10T00:00:00.000Z","routes":[
      {"id":"maas-0","durationSeconds":1500,"startAt":"2026-10-10T00:00:00.000Z","endAt":"2026-10-10T00:25:00.000Z","transfers":1,"legs":[
        {"kind":"walk","from":{"name":null,"lat":25.04,"lon":121.56},"to":{"name":"市政府","lat":25.041,"lon":121.565},"seconds":200,"meters":280,"inStation":false},
        {"kind":"transit","mode":"bus","line":"忠孝幹線","headsign":"公館","color":null,
         "from":{"name":"市政府","lat":25.041,"lon":121.565},"to":{"name":"忠孝復興","lat":25.0416,"lon":121.5437},
         "departAt":"2026-10-10T00:05:00.000Z","arriveAt":"2026-10-10T00:12:00.000Z","stops":[],
         "realtime":{"city":"Taipei","stopUID":"TPE1","arrival":{"routeUID":"TPE1","subRouteUID":null,"stopUID":"TPE1","plateNumber":null,
           "arrivalAt":null,"status":"notDeparted","isLastBus":false,"dataTime":"2026-10-10T07:59:00+08:00"}}},
        {"kind":"walk","from":{"name":"忠孝復興","lat":25.0416,"lon":121.5437},"to":{"name":"忠孝復興站","lat":25.0415,"lon":121.5438},"seconds":120,"meters":0,"inStation":true},
        {"kind":"wait","at":{"name":"忠孝復興站","lat":25.0415,"lon":121.5438},"seconds":90},
        {"kind":"transit","mode":"metro","line":"板南線","headsign":"往頂埔","color":"0070bd",
         "from":{"name":"忠孝復興","lat":25.0415,"lon":121.5438},"to":{"name":"台北車站","lat":25.0461,"lon":121.5174},
         "departAt":"2026-10-10T00:15:00.000Z","arriveAt":"2026-10-10T00:21:00.000Z",
         "stops":[{"name":"忠孝新生","lat":25.0423,"lon":121.5328}],"realtime":null},
        {"kind":"teleport","from":{"name":null,"lat":0,"lon":0},"to":{"name":null,"lat":0,"lon":0}},
        {"kind":"walk","from":{"name":"台北車站","lat":25.0461,"lon":121.5174},"to":{"name":null,"lat":25.047,"lon":121.517},"seconds":240,"meters":300,"inStation":false}
      ]},
      {"id":"maas-1","durationSeconds":1800,"startAt":null,"endAt":null,"transfers":0,"legs":[
        {"kind":"transit","mode":"hovercraft","line":"","headsign":null,"color":null,
         "from":{"name":"A","lat":25,"lon":121},"to":{"name":"B","lat":25.1,"lon":121.1},
         "departAt":null,"arriveAt":null,"stops":[],"realtime":null}
      ]}
    ]}
    """
}

/// 本檔專用的請求攔截：不與 `StubURLProtocol` 共用靜態狀態，兩個測試套件可平行執行。
final class PlanStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var response: (Int, Data) = (500, Data())
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        let (status, data) = Self.response
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct RemoteTransitPlannerTests {
    let configuration = BackendConfiguration(baseURL: URL(string: "https://nas.example.com")!, appKey: String(repeating: "k", count: 24))
    let origin = Place(id: "o", name: "起點", coordinate: Coordinate(latitude: 25.04, longitude: 121.56))
    let destination = Place(id: "d", name: "台北車站", coordinate: Coordinate(latitude: 25.047, longitude: 121.517))

    func makePlanner(status: Int = 200, body: String = PlanSamples.plan) -> RemoteTransitPlanner {
        PlanStubURLProtocol.response = (status, Data(body.utf8))
        let session = URLSession(configuration: {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [PlanStubURLProtocol.self]
            return config
        }())
        return RemoteTransitPlanner(client: BackendClient(configuration: configuration, session: session))
    }

    @Test func decodesLegsAndSkipsUnknownKinds() async throws {
        let plans = try await makePlanner().plans(from: origin, to: destination)
        #expect(plans.count == 2)
        let plan = try #require(plans.first)
        #expect(plan.legs.count == 6) // teleport 被略過
        #expect(plan.transfers == 1)
        #expect(plan.walkMeters == 580) // 站內步行不算
        #expect(plan.transitLegs.map(\.line) == ["忠孝幹線", "板南線"])
        #expect(plan.transitLegs[1].stops.count == 1)

        let request = try #require(PlanStubURLProtocol.lastRequest)
        #expect(request.url?.path == "/v1/plan")
        #expect(request.value(forHTTPHeaderField: "x-app-key") != nil)
        #expect(request.timeoutInterval >= 60)
    }

    @Test func busWithoutEstimateKeepsReasonAndNoFakeTime() async throws {
        let bus = try #require(try await makePlanner().plans(from: origin, to: destination).first?.transitLegs.first)
        let realtime = try #require(bus.realtime)
        #expect(realtime.arrivalAt == nil)
        #expect(realtime.statusNote == "尚未發車")
        #expect(realtime.stopUID == "TPE1")
    }

    @Test func unknownModeBecomesOther() async throws {
        let plans = try await makePlanner().plans(from: origin, to: destination)
        #expect(plans[1].transitLegs.first?.mode == .other)
        #expect(plans[1].startAt == nil)
    }

    @Test func serverErrorThrows() async {
        await #expect(throws: BackendError.server(502)) {
            try await makePlanner(status: 502, body: "{}").plans(from: origin, to: destination)
        }
    }
}

struct PlanFormatTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let place = PlanPlace(name: "市政府", coordinate: Coordinate(latitude: 25, longitude: 121))

    func leg(realtime: LegRealtime?, departIn minutes: Double? = 10) -> TransitLeg {
        TransitLeg(mode: .bus, line: "265", headsign: "台北車站", from: place, to: place,
                   departAt: minutes.map { now.addingTimeInterval($0 * 60) }, arriveAt: nil, stops: [], realtime: realtime)
    }

    @Test func scheduledTimeIsLabelledScheduled() {
        let text = PlanFormat.boardingTime(leg(realtime: nil), now: now)
        #expect(text.hasPrefix("表定"))
        #expect(PlanFormat.dataTag(leg(realtime: nil)) == "表定")
        #expect(!PlanFormat.boardingTimeWithoutTag(leg(realtime: nil), now: now).contains("表定"))
    }

    @Test func realtimeShowsCountdown() {
        let realtime = LegRealtime(stopUID: "S", arrivalAt: now.addingTimeInterval(180), statusNote: nil, updatedAt: now)
        #expect(PlanFormat.boardingTime(leg(realtime: realtime), now: now) == "即時：約 3 分鐘到")
        #expect(PlanFormat.dataTag(leg(realtime: realtime)) == "即時")
    }

    @Test func realtimeWithoutEstimateShowsReasonAndSchedule() {
        let realtime = LegRealtime(stopUID: "S", arrivalAt: nil, statusNote: "尚未發車", updatedAt: now)
        let text = PlanFormat.boardingTime(leg(realtime: realtime), now: now)
        #expect(text.hasPrefix("即時：尚未發車（表定"))
    }

    @Test func headsignAddsTowardsOnce() {
        #expect(PlanFormat.headsign(leg(realtime: nil)) == "往台北車站")
        var other = leg(realtime: nil)
        other.headsign = "往頂埔"
        #expect(PlanFormat.headsign(other) == "往頂埔")
        other.headsign = " "
        #expect(PlanFormat.headsign(other) == nil)
    }

    @Test func durationOverAnHour() {
        #expect(PlanFormat.duration(25 * 60) == "約 25 分鐘")
        #expect(PlanFormat.duration(95 * 60) == "約 1 小時 35 分鐘")
    }

    @Test func stepsNameTheDestinationAndTagTransit() {
        let start = PlanPlace(name: nil, coordinate: Coordinate(latitude: 25, longitude: 121))
        let plan = TransitPlan(id: "p", durationSeconds: 600, startAt: nil, endAt: nil, transfers: 0, legs: [
            .walk(WalkPlanLeg(from: start, to: place, seconds: 120, meters: 150, inStation: false)),
            .transit(leg(realtime: nil)),
            .walk(WalkPlanLeg(from: place, to: start, seconds: 60, meters: 50, inStation: false)),
        ], generatedAt: now)
        let steps = PlanSteps.make(plan, originName: "家", destinationName: "醫院", now: now)
        #expect(steps.map(\.title) == ["走到 市政府", "搭 公車 265（往台北車站）", "走到 醫院"])
        #expect(steps.map(\.dataTag) == [nil, .scheduled, nil])
    }
}

@MainActor
struct TransitPlansViewModelTests {
    struct StubPlanner: TransitPlanning {
        var result: Result<[TransitPlan], BackendError>
        func plans(from origin: Place, to destination: Place) async throws -> [TransitPlan] { try result.get() }
        func refreshed(_ realtime: LegRealtime) async throws -> LegRealtime { realtime }
    }

    let origin = Place(id: "o", name: "起點", coordinate: Coordinate(latitude: 25.04, longitude: 121.56))
    let destination = Place(id: "d", name: "終點", coordinate: Coordinate(latitude: 25.047, longitude: 121.517))
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func filtersWalkOnlyAndSortsByArrival() async throws {
        let mock = try await MockTransitPlanner(now: { [now] in now }).plans(from: origin, to: destination)
        let place = PlanPlace(name: nil, coordinate: origin.coordinate)
        let walkOnly = TransitPlan(id: "walk", durationSeconds: 60, startAt: now, endAt: now, transfers: 0,
                                   legs: [.walk(WalkPlanLeg(from: place, to: place, seconds: 60, meters: 50, inStation: false))],
                                   generatedAt: now)
        let viewModel = TransitPlansViewModel(origin: origin, destination: destination,
                                              planner: StubPlanner(result: .success(mock.reversed() + [walkOnly])))
        await viewModel.load()
        #expect(viewModel.state == .loaded)
        #expect(viewModel.plans.map(\.id) == ["mock-plan-metro", "mock-plan-bus-metro", "mock-plan-bus-scheduled"])
    }

    @Test func failureDoesNotPretendThereAreNoPlans() async {
        let viewModel = TransitPlansViewModel(origin: origin, destination: destination,
                                              planner: StubPlanner(result: .failure(.server(504))))
        await viewModel.load()
        guard case .failed = viewModel.state else {
            Issue.record("應顯示失敗，而不是「沒有方案」")
            return
        }
        #expect(viewModel.plans.isEmpty)
    }
}

struct RouteNameFormatTests {
    @Test func splitsLongRouteName() {
        let parts = TransitFormat.routeNameParts("小9(台灣好行-北投竹子湖)")
        #expect(parts.main == "小9")
        #expect(parts.detail == "台灣好行-北投竹子湖")
        #expect(TransitFormat.shortRouteName("紅5（區間車）") == "紅5")
    }

    @Test func plainNamesStayWhole() {
        #expect(TransitFormat.routeNameParts("265").main == "265")
        #expect(TransitFormat.routeNameParts("265").detail == nil)
        #expect(TransitFormat.routeNameParts("(特)265").main == "(特)265")
    }

    @Test func countdownBoxParts() {
        let now = Date(timeIntervalSince1970: 0)
        #expect(TransitFormat.countdownParts(now.addingTimeInterval(530), now: now, unavailableText: nil) == ("9", "分鐘"))
        #expect(TransitFormat.countdownParts(now, now: now, unavailableText: nil) == ("即將進站", nil))
        #expect(TransitFormat.countdownParts(nil, now: now, unavailableText: "末班車已過") == ("末班車已過", nil))
    }
}
