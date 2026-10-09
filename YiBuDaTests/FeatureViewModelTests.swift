import Foundation
import Testing
@testable import YiBuDa

/// 測試用的交通資料：包裝 Mock，可指定失敗。
struct StubTransportProvider: TransportProvider {
    var base = MockTransportProvider(now: { Date(timeIntervalSince1970: 1_800_000_000) })
    var failsJourneys = false
    var failsArrivals = false
    var arrivalsOverride: [StopArrival]?

    func searchStops(_ query: String) async throws -> [Stop] { try await base.searchStops(query) }
    func findJourneys(from origin: Place, to destination: Place) async throws -> [Journey] {
        if failsJourneys { throw URLError(.notConnectedToInternet) }
        return try await base.findJourneys(from: origin, to: destination)
    }
    func getArrivals(stopUID: String) async throws -> [StopArrival] {
        if failsArrivals { throw URLError(.notConnectedToInternet) }
        if let arrivalsOverride { return arrivalsOverride }
        return try await base.getArrivals(stopUID: stopUID)
    }
    func getStopDetails(stopUID: String) async throws -> StopDetails { try await base.getStopDetails(stopUID: stopUID) }
}

@MainActor
struct HomeViewModelTests {
    let mock = MockTransportProvider()

    func makeSUT() -> HomeViewModel {
        HomeViewModel(places: mock, favorites: mock, currentPlace: mock)
    }

    @Test func needsDestinationBeforeSearchingBuses() async {
        let sut = makeSUT()
        await sut.load()
        #expect(sut.origin != nil)
        #expect(sut.favorites.map(\.favoriteTitle) == ["回家", "公司", "學校"])
        #expect(!sut.canSearchBuses)
    }

    @Test func searchingAndSelectingSetsDestination() async throws {
        let sut = makeSUT()
        await sut.load()
        sut.query = "台北"
        await sut.search()
        let station = try #require(sut.suggestions.first { $0.name == "台北車站" })
        sut.select(station)
        #expect(sut.destination == station)
        #expect(sut.query == "台北車站")
        #expect(sut.suggestions.isEmpty)
        #expect(sut.canSearchBuses)
    }

    @Test func editingQueryClearsSelectedDestination() async {
        let sut = makeSUT()
        await sut.load()
        sut.select(MockTransitFixture.favorites[0])
        sut.query = "台大"
        #expect(sut.destination == nil)
        #expect(!sut.canSearchBuses)
    }
}

@MainActor
struct BoardingOptionsViewModelTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func makeSUT(transport: StubTransportProvider = StubTransportProvider()) -> BoardingOptionsViewModel {
        let now = now
        return BoardingOptionsViewModel(origin: MockTransitFixture.currentPlace, destination: MockTransitFixture.taipeiMainStation,
                                        transport: transport, now: { now })
    }

    @Test func loadRecommendsAndPreselects265() async {
        let sut = makeSUT()
        await sut.load()
        #expect(sut.state == .loaded)
        #expect(sut.recommended?.option?.routeName == "265")
        #expect(sut.selected?.option?.routeName == "265")
        #expect(sut.startTitle == "開始導航（搭 265）")
        #expect(sut.others.count == 3)
    }

    @Test func recommendationStaysWhenDisplayOrderChanges() async {
        let sut = makeSUT()
        await sut.load()
        sut.order = .soonestBus
        #expect(sut.recommended?.option?.routeName == "265")
        #expect(sut.others.first?.option?.routeName == "307")
    }

    @Test func alternativesAreValidJourneysAtSameStop() async throws {
        let sut = makeSUT()
        await sut.load()
        let selected = try #require(sut.selected)
        let alternatives = sut.alternatives(for: selected)
        #expect(alternatives.count == 4)
        #expect(alternatives.allSatisfy { $0.busLeg?.option.boardingStopUID == MockTransitFixture.StopID.cityHallToTPE })
    }

    @Test func failureShowsMessageWithoutFakeData() async {
        let sut = makeSUT(transport: StubTransportProvider(failsJourneys: true))
        await sut.load()
        guard case .failed = sut.state else {
            Issue.record("應該顯示錯誤")
            return
        }
        #expect(sut.ranked.isEmpty)
        #expect(sut.selected == nil)
    }
}

@MainActor
struct NavigationSessionViewModelTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func makeSUT(transport: StubTransportProvider = StubTransportProvider(), route: String = "265") throws -> NavigationSessionViewModel {
        let journeys = MockTransitFixture.journeys(origin: MockTransitFixture.currentPlace,
                                                   destination: MockTransitFixture.taipeiMainStation, now: now)
        let valid = TransitRankingService().rank(journeys, now: now).map(\.journey)
        let journey = try #require(valid.first { $0.busLeg?.option.routeName == route })
        let now = now
        return NavigationSessionViewModel(journey: journey, alternatives: valid, transport: transport, now: { now })
    }

    @Test func completesWholeFlowWithManualConfirmations() async throws {
        let sut = try makeSUT()
        await sut.start()
        #expect(sut.phase == .walkingToStop(step: 0))
        #expect(sut.stopDetails != nil)
        #expect(sut.walkingPrimaryTitle == "下一步")

        sut.nextStep(); sut.nextStep()
        #expect(sut.walkingPrimaryTitle == "我到站牌了")
        sut.nextStep()
        #expect(sut.phase == .checkingBoardingSide)

        await sut.confirmBoardingSide()
        #expect(sut.phase == .waitingAtStop)
        #expect(sut.waitingOptions.count == 4)

        sut.board()
        #expect(sut.phase == .onVehicle(approachingAlight: false))
        #expect(sut.remainingStops == 2)

        sut.simulateNextStop()
        #expect(sut.phase == .onVehicle(approachingAlight: true))

        sut.alighted()
        #expect(sut.phase == .walkingToDestination(step: 0))
        sut.nextStep()
        #expect(sut.walkingPrimaryTitle == "我到了")
        sut.nextStep()
        #expect(sut.phase == .arrived)

        sut.cancel()
        #expect(sut.isFinished)
    }

    @Test func boardingDifferentBusSwitchesJourney() async throws {
        let sut = try makeSUT()
        await sut.start()
        sut.nextStep(); sut.nextStep(); sut.nextStep()
        await sut.confirmBoardingSide()
        let bus212 = try #require(sut.waitingOptions.first { $0.option?.routeName == "212" })
        sut.selectWaitingOption(bus212)
        sut.board()
        #expect(sut.bus?.option.routeName == "212")
    }

    @Test func lastWalkingStepPointsToBoardingStop() async throws {
        let sut = try makeSUT()
        await sut.start()
        sut.nextStep(); sut.nextStep()
        #expect(sut.nextStepText?.contains("市政府站") == true)
        #expect(sut.nextStepText?.contains("265") == true)
    }

    @Test func arrivalRefreshFailureKeepsOldDataAndWarns() async throws {
        let sut = try makeSUT(transport: StubTransportProvider(failsArrivals: true))
        await sut.start()
        sut.nextStep(); sut.nextStep(); sut.nextStep()
        await sut.confirmBoardingSide()
        #expect(sut.notice != nil)
        #expect(sut.waitingOptions.count == 4)
    }

    @Test func refreshedArrivalUpdatesEta() async throws {
        let newETA = now.addingTimeInterval(90)
        let arrivals = [StopArrival(patternId: "265-E", estimatedArrival: newETA, etaSource: .realTime, updatedAt: now)]
        let sut = try makeSUT(transport: StubTransportProvider(arrivalsOverride: arrivals))
        await sut.start()
        sut.nextStep(); sut.nextStep(); sut.nextStep()
        await sut.confirmBoardingSide()
        let bus265 = try #require(sut.waitingOptions.first { $0.option?.routeName == "265" })
        #expect(bus265.option?.estimatedArrivalAtStop == newETA)
    }
}

struct TransitFormatTests {
    let now = Date(timeIntervalSince1970: 0)

    @Test func countdownNeverInventsMinutes() {
        #expect(TransitFormat.busCountdown(nil, now: now) == "查無即時預估")
        #expect(TransitFormat.busCountdown(now.addingTimeInterval(30), now: now) == "約 1 分鐘到")
        #expect(TransitFormat.busCountdown(now.addingTimeInterval(-10), now: now) == "即將進站")
        #expect(TransitFormat.busCountdown(now.addingTimeInterval(360), now: now) == "約 6 分鐘到")
    }

    @Test func walkMinutesRoundsUpAndIsAtLeastOne() {
        #expect(TransitFormat.walkMinutes(180) == "走過去約 3 分鐘")
        #expect(TransitFormat.walkMinutes(10) == "走過去約 1 分鐘")
    }
}

struct MockTransportProviderTests {
    let provider = MockTransportProvider(now: { Date(timeIntervalSince1970: 1_800_000_000) })

    @Test func searchStopsReturnsBothDirectionsAsDistinctStops() async throws {
        let stops = try await provider.searchStops("市政府")
        #expect(stops.count == 2)
        #expect(Set(stops.map(\.stopUID)).count == 2)
        #expect(Set(stops.map(\.directionDescription)) == ["往台北車站方向", "往板橋方向"])
    }

    @Test func unknownStopThrows() async {
        await #expect(throws: TransportProviderError.stopNotFound) {
            try await provider.getStopDetails(stopUID: "nope")
        }
    }

    @Test func oppositeStopSideIsUnknownNotGuessed() async throws {
        let details = try await provider.getStopDetails(stopUID: MockTransitFixture.StopID.cityHallToBanqiao)
        #expect(details.side == .unknown)
    }
}
