import Foundation
import Testing
@testable import YiBuDa

struct TransitRankingServiceTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let ranking = TransitRankingService()

    var journeys: [Journey] {
        MockTransitFixture.journeys(origin: MockTransitFixture.currentPlace,
                                    destination: MockTransitFixture.taipeiMainStation, now: now)
    }

    func ranked(_ order: JourneySortOrder = .earliestArrival, atStop: Bool = false) -> [RankedJourney] {
        ranking.rank(journeys, now: now, order: order, userAtBoardingStop: atStop)
    }

    // 計畫測試案例：同一站 3 條可達路線，有先到站但趕不上、有較晚到站但較早抵達目的地。
    @Test func recommendsCatchableJourneyArrivingEarliest() throws {
        let recommended = try #require(ranking.recommendation(in: ranked()))
        #expect(recommended.option?.routeName == "265")
        #expect(recommended.catchStatus == .canCatch)
    }

    @Test func busArrivingBeforeWalkAndBufferIsTooLate() throws {
        let bus307 = try #require(ranked().first { $0.option?.routeName == "307" })
        // 2 分鐘後到站，但步行 3 分鐘 + 緩衝 2 分鐘
        #expect(bus307.catchStatus == .tooLate)
    }

    @Test func orderPutsCatchableFirstThenUnknownThenTooLate() {
        #expect(ranked().map { $0.option?.routeName } == ["265", "212", "671", "307"])
    }

    @Test func soonestBusOrderSortsByEtaWithUnknownLast() {
        #expect(ranked(.soonestBus).map { $0.option?.routeName } == ["307", "212", "265", "671"])
    }

    // 計畫測試案例：相同站名的兩個相反方向站牌，不得把反向公車列為可搭。
    @Test func oppositeDirectionStopIsExcluded() {
        let all = ranked()
        #expect(all.count == 4)
        #expect(!all.contains { $0.option?.boardingStopUID == MockTransitFixture.StopID.cityHallToBanqiao })
    }

    @Test func unknownEtaIsNotFabricated() throws {
        let bus671 = try #require(ranked().first { $0.option?.routeName == "671" })
        #expect(bus671.catchStatus == .unknown)
        #expect(bus671.arrivalAtDestination == nil)
        #expect(bus671.option?.estimatedArrivalAtStop == nil)
    }

    @Test func oldDataIsMarkedStale() throws {
        let all = ranked()
        #expect(try #require(all.first { $0.option?.routeName == "212" }).isStale)
        #expect(try #require(all.first { $0.option?.routeName == "265" }).isStale == false)
    }

    @Test func arrivalAddsRideAndWalkToDestination() throws {
        let bus265 = try #require(ranked().first { $0.option?.routeName == "265" })
        // 8 分鐘後到站 + 搭 12 分鐘 + 走 4 分鐘
        #expect(bus265.arrivalAtDestination == now.addingTimeInterval(24 * 60))
    }

    @Test func atStopIgnoresWalkAndBuffer() throws {
        let bus307 = try #require(ranked(atStop: true).first { $0.option?.routeName == "307" })
        #expect(bus307.catchStatus == .canCatch)
    }

    @Test func noRecommendationWhenNothingCatchable() {
        let late = journeys.map { journey in
            journey.replacingBusOption(journey.busLeg!.option.updating(with: StopArrival(
                patternId: journey.busLeg!.option.patternId, estimatedArrival: now.addingTimeInterval(60),
                etaSource: .realTime, updatedAt: now)))
        }
        #expect(ranking.recommendation(in: ranking.rank(late, now: now)) == nil)
    }
}

struct BoardingDirectionValidatorTests {
    let pattern = RoutePattern(patternId: "P", routeId: "R", routeName: "R", directionName: "往 B",
                               stopUIDs: ["A", "B", "C"])

    @Test func patternServesOnlyForwardDirection() {
        #expect(pattern.serves(from: "A", to: "C"))
        #expect(!pattern.serves(from: "C", to: "A"))
        #expect(!pattern.serves(from: "A", to: "A"))
        #expect(!pattern.serves(from: "A", to: "X"))
        #expect(pattern.stopCount(from: "A", to: "C") == 2)
    }

    @Test func legWithMismatchedStopUIDIsInvalid() throws {
        let journey = try #require(MockTransitFixture.journeys(
            origin: MockTransitFixture.currentPlace, destination: MockTransitFixture.taipeiMainStation, now: .now).first)
        var leg = try #require(journey.busLeg)
        #expect(BoardingDirectionValidator.isValid(leg))
        leg.boardingStop.stopUID = MockTransitFixture.StopID.cityHallToBanqiao
        #expect(!BoardingDirectionValidator.isValid(leg))
    }
}
