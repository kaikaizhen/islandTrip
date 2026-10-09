import Foundation
import Testing
@testable import YiBuDa

struct FakeWalkingRouteProvider: WalkingRouteProviding {
    var fails = false

    func walkingRoute(from origin: Coordinate, to destination: Coordinate) async throws -> WalkingRoute {
        if fails { throw WalkingRouteError.noRoute }
        let middle = Coordinate(latitude: (origin.latitude + destination.latitude) / 2, longitude: origin.longitude)
        return WalkingRoute(coordinates: [origin, middle, destination], expectedSeconds: 150, distanceMeters: 190)
    }
}

@MainActor
struct RoutePreviewViewModelTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func makeSUT(routes: FakeWalkingRouteProvider = FakeWalkingRouteProvider()) throws -> RoutePreviewViewModel {
        let journeys = MockTransitFixture.journeys(origin: MockTransitFixture.currentPlace,
                                                   destination: MockTransitFixture.taipeiMainStation, now: now)
        let ranked = try #require(TransitRankingService().rank(journeys, now: now).first { $0.option?.routeName == "265" })
        return RoutePreviewViewModel(ranked: ranked, transport: StubTransportProvider(), routes: routes)
    }

    @Test func showsCorrectStopAndMarksOppositeStopAsWrong() async throws {
        let sut = try makeSUT()
        await sut.load()

        let boarding = try #require(sut.markers.first { $0.kind == .boardingStop })
        let wrong = try #require(sut.markers.first { $0.kind == .wrongDirectionStop })
        #expect(boarding.subtitle?.contains("往台北車站方向") == true)
        #expect(wrong.title == "不是這個")
        #expect(wrong.subtitle?.contains("往板橋方向") == true)
        #expect(Set(sut.markers.map(\.kind)) == [.origin, .boardingStop, .wrongDirectionStop, .alightingStop, .destination])
    }

    @Test func walkingSegmentsUseMapRouteAndBusIsApproximate() async throws {
        let sut = try makeSUT()
        await sut.load()

        let segments = Dictionary(uniqueKeysWithValues: sut.segments.map { ($0.kind, $0) })
        #expect(segments[.walkToStop]?.isApproximate == false)
        #expect(segments[.walkToStop]?.coordinates.count == 3)
        #expect(segments[.bus]?.isApproximate == true, "沒有公車路線形狀資料時必須標示為示意")
        #expect(sut.walkSummary(sut.walkToStop) == "走約 3 分鐘・190 公尺（Apple 地圖）")
    }

    @Test func routeFailureFallsBackToLabelledStraightLine() async throws {
        let sut = try makeSUT(routes: FakeWalkingRouteProvider(fails: true))
        await sut.load()

        #expect(sut.walkToStop == .unavailable)
        let walk = try #require(sut.segments.first { $0.kind == .walkToStop })
        #expect(walk.isApproximate)
        #expect(walk.coordinates.count == 2)
        #expect(sut.walkSummary(sut.walkToStop).contains("無法取得步行路線"))
    }
}
