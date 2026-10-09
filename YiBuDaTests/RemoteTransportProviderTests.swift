import Foundation
import Testing
@testable import YiBuDa

/// 攔截 URLSession 請求，回傳預先準備的後端回應。
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        let (status, data) = Self.handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// 後端回應範例（格式同 Backend/README.md；內容為合成資料）。
enum BackendSamples {
    static let journeys = """
    {"generatedAt":"2026-10-09T00:00:00.000Z","candidates":[
      {"id":"TPE265|TPE265A|0@TPE1001>TPE1004","city":"Taipei",
       "route":{"uid":"TPE265","id":"265","name":"265","subRouteUID":"TPE265A","headsign":"往台北車站"},
       "boardingStop":{"uid":"TPE1001","name":"市政府","lat":25.04128,"lon":121.566,"bearing":"W","city":"Taipei"},
       "alightingStop":{"uid":"TPE1004","name":"台北車站","lat":25.0477,"lon":121.5173,"bearing":"W","city":"Taipei"},
       "oppositeStop":{"uid":"TPE1002","name":"市政府","lat":25.04092,"lon":121.5662,"bearing":"E","city":"Taipei"},
       "stopCount":2,
       "arrival":{"routeUID":"TPE265","subRouteUID":"TPE265A","stopUID":"TPE1001","plateNumber":"KKA-0001",
                  "arrivalAt":"2026-10-09T00:08:00.000Z","status":"normal","isLastBus":false,"dataTime":"2026-10-09T07:59:30+08:00"},
       "rideSeconds":720,"rideSource":"vehicle"},
      {"id":"TPE307|TPE307|0@TPE1001>TPE1004","city":"Taipei",
       "route":{"uid":"TPE307","id":"307","name":"307","subRouteUID":null,"headsign":"往板橋"},
       "boardingStop":{"uid":"TPE1001","name":"市政府","lat":25.04128,"lon":121.566,"bearing":"W","city":"Taipei"},
       "alightingStop":{"uid":"TPE1004","name":"台北車站","lat":25.0477,"lon":121.5173,"bearing":"W","city":"Taipei"},
       "oppositeStop":null,"stopCount":3,
       "arrival":{"routeUID":"TPE307","subRouteUID":null,"stopUID":"TPE1001","plateNumber":null,
                  "arrivalAt":null,"status":"lastBusPassed","isLastBus":false,"dataTime":null},
       "rideSeconds":270,"rideSource":"stopCount"}
    ]}
    """

    static let alerts = """
    {"alerts":[
      {"id":"A1","city":"Taipei","title":"265 改道","description":"市政府站暫不停靠","status":2,"effect":1,"routeIDs":["265"],"stopIDs":[],"url":null},
      {"id":"A2","city":"Taipei","title":"999 停駛","description":"","status":0,"effect":4,"routeIDs":["999"],"stopIDs":[],"url":null}
    ],"mqttConnected":true}
    """

    static let arrivals = """
    {"generatedAt":"2026-10-09T00:01:00.000Z","arrivals":[
      {"routeUID":"TPE265","subRouteUID":"TPE265A","stopUID":"TPE1001","plateNumber":"KKA-0001",
       "arrivalAt":"2026-10-09T00:05:00.000Z","status":"normal","isLastBus":false,"dataTime":"2026-10-09T08:00:30+08:00"}
    ]}
    """
}

@Suite(.serialized)
struct RemoteTransportProviderTests {
    let configuration = BackendConfiguration(baseURL: URL(string: "https://nas.example.com")!, appKey: String(repeating: "k", count: 24))

    func makeProvider(_ handler: @escaping (URLRequest) -> (Int, Data)) -> RemoteTransportProvider {
        StubURLProtocol.handler = handler
        let session = URLSession(configuration: {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [StubURLProtocol.self]
            return config
        }())
        return RemoteTransportProvider(client: BackendClient(configuration: configuration, session: session))
    }

    func respond(_ json: String) -> (URLRequest) -> (Int, Data) {
        { _ in (200, Data(json.utf8)) }
    }

    @Test func mapsCandidatesWithRealTimeAndEstimatedRide() async throws {
        let provider = makeProvider(respond(BackendSamples.journeys))
        let journeys = try await provider.findJourneys(from: MockTransitFixture.currentPlace, to: MockTransitFixture.taipeiMainStation)
        #expect(journeys.count == 2)

        let bus265 = try #require(journeys.first?.busLeg)
        #expect(bus265.option.routeName == "265")
        #expect(bus265.boardingStop.directionDescription == "往台北車站方向")
        #expect(bus265.option.estimatedArrivalAtStop == ISODate.parse("2026-10-09T00:08:00.000Z"))
        #expect(bus265.option.etaSource == .realTime)
        #expect(!bus265.option.rideIsEstimated)
        #expect(bus265.option.routeCode == "265")
        #expect(bus265.option.city == "Taipei")

        let bus307 = try #require(journeys.last?.busLeg)
        #expect(bus307.option.estimatedArrivalAtStop == nil, "沒有預估時間就不能偽造")
        #expect(bus307.option.statusNote == "末班車已過")
        #expect(bus307.option.rideIsEstimated)

        let request = try #require(StubURLProtocol.lastRequest)
        #expect(request.value(forHTTPHeaderField: "x-app-key") == configuration.appKey)
        #expect(request.url?.path() == "/v1/journeys")
        #expect(request.url?.query()?.contains("destinationLat=") == true)
    }

    @Test func mappedJourneysPassAppDirectionValidation() async throws {
        let provider = makeProvider(respond(BackendSamples.journeys))
        let journeys = try await provider.findJourneys(from: MockTransitFixture.currentPlace, to: MockTransitFixture.taipeiMainStation)
        let ranked = TransitRankingService().rank(journeys, now: ISODate.parse("2026-10-09T00:00:00.000Z")!)
        #expect(ranked.count == 2)
        #expect(ranked.first?.option?.routeName == "265")
    }

    @Test func stopDetailsGiveOppositeStopButLeaveSideUnknown() async throws {
        let provider = makeProvider(respond(BackendSamples.journeys))
        _ = try await provider.findJourneys(from: MockTransitFixture.currentPlace, to: MockTransitFixture.taipeiMainStation)
        let details = try await provider.getStopDetails(stopUID: "TPE1001")
        #expect(details.oppositeStop?.stopUID == "TPE1002")
        #expect(details.oppositeStop?.directionDescription == "反方向（東行）")
        #expect(details.side == .unknown, "真實資料不知道使用者在哪一側，交給 GPS 或詢問")
    }

    @Test func arrivalsUseKnownCityAndMatchPattern() async throws {
        let provider = makeProvider { request in
            (200, Data((request.url?.path() == "/v1/arrivals" ? BackendSamples.arrivals : BackendSamples.journeys).utf8))
        }
        let journeys = try await provider.findJourneys(from: MockTransitFixture.currentPlace, to: MockTransitFixture.taipeiMainStation)
        let arrivals = try await provider.getArrivals(stopUID: "TPE1001")
        #expect(StubURLProtocol.lastRequest?.url?.query()?.contains("city=Taipei") == true)
        #expect(arrivals.first?.patternId == journeys.first?.busLeg?.option.patternId)
        #expect(arrivals.first?.estimatedArrival == ISODate.parse("2026-10-09T00:05:00.000Z"))
    }

    @Test func unauthorizedIsReported() async {
        let provider = makeProvider { _ in (401, Data()) }
        await #expect(throws: BackendError.unauthorized) {
            _ = try await provider.findJourneys(from: MockTransitFixture.currentPlace, to: MockTransitFixture.taipeiMainStation)
        }
    }

    func makeRailProvider(_ handler: @escaping (URLRequest) -> (Int, Data)) -> RemoteRailProvider {
        StubURLProtocol.handler = handler
        let session = URLSession(configuration: {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [StubURLProtocol.self]
            return config
        }())
        return RemoteRailProvider(client: BackendClient(configuration: configuration, session: session))
    }

    @Test func railDeparturesKeepDataLevelAndHeadway() async throws {
        let json = """
        {"system":"TMRT","stationID":"103","generatedAt":"2026-10-12T00:00:00.000Z","note":"此系統只提供班距，沒有每班時間。",
         "departures":[
          {"line":"G","trainNo":null,"destination":null,"direction":null,"scheduledAt":null,"expectedAt":null,"delayMinutes":null,
           "headway":{"minMinutes":4,"maxMinutes":6},"status":"normal","dataLevel":"frequency"},
          {"line":"自強","trainNo":"111","destination":"高雄","direction":"順行","scheduledAt":"2026-10-12T00:10:00.000Z",
           "expectedAt":"2026-10-12T00:15:00.000Z","delayMinutes":5,"headway":null,"status":"normal","dataLevel":"realtime"}
         ]}
        """
        let provider = makeRailProvider(respond(json))
        let station = RailStation(system: .tmrt, stationID: "103", name: "文心崇德", coordinate: Coordinate(latitude: 24.17, longitude: 120.68))
        let board = try await provider.board(for: station)
        #expect(StubURLProtocol.lastRequest?.url?.query()?.contains("system=TMRT") == true)
        #expect(board.note == "此系統只提供班距，沒有每班時間。")
        #expect(board.departures[0].headway == 4...6)
        #expect(board.departures[0].dataLevel == .frequency)
        #expect(board.departures[1].delayMinutes == 5)
        #expect(board.departures[1].expectedAt == ISODate.parse("2026-10-12T00:15:00.000Z"))
    }

    @Test func railAlertsUnsupportedIsNil() async throws {
        let provider = makeRailProvider(respond(#"{"supported":false,"alerts":[]}"#))
        #expect(try await provider.alerts(for: .tra) == nil)
    }

    @Test func nearbyRailStationsAreMapped() async throws {
        let provider = makeRailProvider(respond(#"{"stations":[{"system":"TRTC","systemName":"臺北捷運","uid":"TRTC-BL18","id":"BL18","name":"市政府","lat":25.0412,"lon":121.5652,"distance":35}]}"#))
        let stations = try await provider.nearbyStations(around: testOrigin, radius: 1500)
        #expect(stations.map(\.id) == ["TRTC-BL18"])
        #expect(stations.first?.distance == 35)
    }

    @Test func alertsAreMapped() async throws {
        let provider = makeProvider(respond(BackendSamples.alerts))
        let alerts = try await provider.alerts(city: "Taipei")
        #expect(alerts.map(\.id) == ["A1", "A2"])
        #expect(alerts.first?.routeCodes == ["265"])
        #expect(alerts.first?.effect == 1)
    }
}

struct BackendConfigurationTests {
    let key = String(repeating: "k", count: 24)

    @Test func requiresValidURLAndLongEnoughKey() {
        #expect(BackendConfiguration.from(info: ["YiBuDaBackendURL": "https://nas.example.com", "YiBuDaAppKey": key]) != nil)
        #expect(BackendConfiguration.from(info: ["YiBuDaBackendURL": "http://192.168.1.20:8080", "YiBuDaAppKey": key]) != nil)
        #expect(BackendConfiguration.from(info: ["YiBuDaBackendURL": "", "YiBuDaAppKey": key]) == nil, "未設定就用模擬資料")
        #expect(BackendConfiguration.from(info: ["YiBuDaBackendURL": "ftp://nas", "YiBuDaAppKey": key]) == nil)
        #expect(BackendConfiguration.from(info: ["YiBuDaBackendURL": "https://nas.example.com", "YiBuDaAppKey": "short"]) == nil)
        #expect(BackendConfiguration.from(info: nil) == nil)
    }

    @Test func parsesBothTimestampFormats() {
        #expect(ISODate.parse("2026-10-09T00:08:00.000Z") == Date(timeIntervalSince1970: 1_791_504_480))
        #expect(ISODate.parse("2026-10-09T08:08:00+08:00") == Date(timeIntervalSince1970: 1_791_504_480))
        #expect(ISODate.parse("not a date") == nil)
    }

    @MainActor
    @Test func dependenciesChooseDataSource() {
        let info: [String: Any] = ["YiBuDaBackendURL": "https://nas.example.com", "YiBuDaAppKey": key]
        #expect(!AppDependencies.live(arguments: [], info: info).isMockTransit)
        #expect(AppDependencies.live(arguments: ["-mockTransit"], info: info).isMockTransit)
        #expect(AppDependencies.live(arguments: [], info: [:]).isMockTransit)
    }
}

struct StubAlertProvider: ServiceAlertProviding {
    var alerts: [ServiceAlert]
    var fails = false
    func alerts(city: String) async throws -> [ServiceAlert] {
        if fails { throw BackendError.server(502) }
        return alerts
    }
}

@MainActor
struct OptionsAlertTests {
    @Test func onlyAlertsForListedRoutesAreShown() async throws {
        let journeys = MockTransitFixture.journeys(origin: MockTransitFixture.currentPlace,
                                                   destination: MockTransitFixture.taipeiMainStation, now: .now)
            .map { journey -> Journey in
                guard var option = journey.busLeg?.option else { return journey }
                option.city = "Taipei"
                option.routeCode = option.routeName
                return journey.replacingBusOption(option)
            }
        struct FixedTransport: TransportProvider {
            var journeys: [Journey]
            func searchStops(_ query: String) async throws -> [Stop] { [] }
            func findJourneys(from origin: Place, to destination: Place) async throws -> [Journey] { journeys }
            func getArrivals(stopUID: String) async throws -> [StopArrival] { [] }
            func getStopDetails(stopUID: String) async throws -> StopDetails { throw TransportProviderError.stopNotFound }
        }
        let relevant = ServiceAlert(id: "A1", title: "265 改道", description: "", effect: 1, routeCodes: ["265"], url: nil)
        let unrelated = ServiceAlert(id: "A2", title: "999 停駛", description: "", effect: 4, routeCodes: ["999"], url: nil)
        let sut = BoardingOptionsViewModel(origin: MockTransitFixture.currentPlace, destination: MockTransitFixture.taipeiMainStation,
                                           transport: FixedTransport(journeys: journeys),
                                           alerts: StubAlertProvider(alerts: [relevant, unrelated]))
        await sut.load()
        #expect(sut.alerts == [relevant])
        let bus265 = try #require(sut.ranked.first { $0.option?.routeName == "265" })
        #expect(sut.alerts(for: bus265) == [relevant])
        let bus212 = try #require(sut.ranked.first { $0.option?.routeName == "212" })
        #expect(sut.alerts(for: bus212).isEmpty)
    }

    @Test func alertFailureDoesNotBlockResults() async {
        let sut = BoardingOptionsViewModel(origin: MockTransitFixture.currentPlace, destination: MockTransitFixture.taipeiMainStation,
                                           transport: MockTransportProvider(), alerts: StubAlertProvider(alerts: [], fails: true))
        await sut.load()
        #expect(sut.state == .loaded)
        // 模擬資料沒有縣市，不會查詢異常消息
        #expect(!sut.alertsUnavailable)
    }
}
