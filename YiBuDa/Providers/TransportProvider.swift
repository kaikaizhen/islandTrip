import Foundation

/// 交通資料來源。開發與測試用 `MockTransportProvider`；Phase 3 加入透過保密代理連 TDX 的實作。
protocol TransportProvider: Sendable {
    func searchStops(_ query: String) async throws -> [Stop]
    /// 回傳候選方案（未過濾方向、未排序；判斷交給 `TransitRankingService`）。
    func findJourneys(from origin: Place, to destination: Place) async throws -> [Journey]
    func getArrivals(stopUID: String) async throws -> [StopArrival]
    func getStopDetails(stopUID: String) async throws -> StopDetails
}

/// 目的地搜尋。與交通資料分開；正式使用 Apple MapKit 地點搜尋。
protocol PlaceSearching: Sendable {
    /// - Parameter near: 優先搜尋此位置附近；nil 時由實作決定範圍。
    func searchPlaces(_ query: String, near: Coordinate?) async throws -> [Place]
}

/// 常用地點（家、公司、學校）。
protocol FavoritePlacesProviding: Sendable {
    func favoritePlaces() async -> [Place]
}

/// 目前位置。Phase 2 改由 Core Location 提供。
protocol CurrentPlaceProviding: Sendable {
    func currentPlace() async throws -> Place
}

/// 公車通阻／異常消息（改道、停駛、站牌不停靠…）。
struct ServiceAlert: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var description: String
    /// TDX Effect：1 改道／站牌不停靠、3 班次減少、4 班次取消、6 站點異動、7 重大延遲…
    var effect: Int?
    var routeCodes: [String]
    var url: URL?
}

/// 異常消息來源（真實資料時由 NAS 後端提供；模擬資料沒有）。
protocol ServiceAlertProviding: Sendable {
    func alerts(city: String) async throws -> [ServiceAlert]
}

/// 跨運具方案（可轉乘）。真實資料時由 NAS 後端呼叫 TDX MaaS。
protocol TransitPlanning: Sendable {
    func plans(from origin: Place, to destination: Place) async throws -> [TransitPlan]
}

enum TransportProviderError: Error, Equatable {
    case stopNotFound
}
