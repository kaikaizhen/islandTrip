import Foundation

/// 離線模擬資料。不連網；時間以注入的 `now` 計算，方便測試。
struct MockTransportProvider: TransportProvider, PlaceSearching, CurrentPlaceProviding {
    var now: @Sendable () -> Date = { Date() }

    func searchStops(_ query: String) async throws -> [Stop] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        return MockTransitFixture.stops(dataTime: now()).values
            .filter { $0.name.contains(trimmed) }
            .sorted { $0.stopUID < $1.stopUID }
    }

    func findJourneys(from origin: Place, to destination: Place) async throws -> [Journey] {
        MockTransitFixture.journeys(origin: origin, destination: destination, now: now())
    }

    func getArrivals(stopUID: String) async throws -> [StopArrival] {
        MockTransitFixture.arrivals(stopUID: stopUID, now: now())
    }

    func getStopDetails(stopUID: String) async throws -> StopDetails {
        guard let details = MockTransitFixture.stopDetails(stopUID: stopUID, now: now()) else {
            throw TransportProviderError.stopNotFound
        }
        return details
    }

    func searchPlaces(_ query: String, near: Coordinate?) async throws -> [Place] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        return MockTransitFixture.searchablePlaces.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    func currentPlace() async throws -> Place {
        MockTransitFixture.currentPlace
    }
}
