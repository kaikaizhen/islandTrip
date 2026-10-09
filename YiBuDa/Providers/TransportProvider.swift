import Foundation

/// 交通資料來源。開發與測試用 `MockTransportProvider`；Phase 3 加入透過保密代理連 TDX 的實作。
protocol TransportProvider: Sendable {
    func searchStops(_ query: String) async throws -> [Stop]
    /// 回傳候選方案（未過濾方向、未排序；判斷交給 `TransitRankingService`）。
    func findJourneys(from origin: Place, to destination: Place) async throws -> [Journey]
    func getArrivals(stopUID: String) async throws -> [StopArrival]
    func getStopDetails(stopUID: String) async throws -> StopDetails
}

/// 目的地搜尋。與交通資料分開，之後可改用 MapKit 地點搜尋。
protocol PlaceSearching: Sendable {
    func searchPlaces(_ query: String) async throws -> [Place]
}

/// 常用地點（家、公司、學校）。
protocol FavoritePlacesProviding: Sendable {
    func favoritePlaces() async -> [Place]
}

/// 目前位置。Phase 2 改由 Core Location 提供。
protocol CurrentPlaceProviding: Sendable {
    func currentPlace() async throws -> Place
}

enum TransportProviderError: Error, Equatable {
    case stopNotFound
}
