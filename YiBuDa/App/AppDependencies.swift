import Foundation

/// Composition root：在這裡決定各協定的具體實作，其餘程式只依賴協定。
@MainActor
struct AppDependencies {
    let liveActivity: any LiveActivityControlling
    let notifications: UserNotificationScheduler
    let transport: any TransportProvider
    let places: any PlaceSearching
    let favorites: any FavoritePlacesProviding
    let currentPlace: any CurrentPlaceProviding
    let ranking: TransitRankingService
    let walkingRoutes: any WalkingRouteProviding
    let settings: AppSettings
    let location: any LocationProviding

    /// UI 測試用的啟動參數：目的地搜尋改用離線模擬資料，讓測試不依賴網路。
    static let mockPlaceSearchArgument = "-mockPlaceSearch"

    /// 交通資料目前只有 Mock；Phase 3 加入真實資料來源時在這裡切換。目的地搜尋使用 Apple MapKit。
    static func live(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppDependencies {
        let mock = MockTransportProvider()
        let places: any PlaceSearching = arguments.contains(mockPlaceSearchArgument) ? mock : MapKitPlaceSearch()
        let settings = AppSettings()
        let location = CoreLocationProvider()
        return AppDependencies(
            liveActivity: ActivityKitLiveActivityController(),
            notifications: UserNotificationScheduler(),
            transport: mock,
            places: places,
            favorites: mock,
            currentPlace: SettingsCurrentPlaceProvider(
                settings: settings, gps: GPSCurrentPlaceProvider(location: location), simulated: mock
            ),
            ranking: TransitRankingService(),
            walkingRoutes: MapKitWalkingRouteProvider(),
            settings: settings,
            location: location
        )
    }

    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(places: places, favorites: favorites, currentPlace: currentPlace)
    }

    func makeBoardingOptionsViewModel(origin: Place, destination: Place) -> BoardingOptionsViewModel {
        BoardingOptionsViewModel(origin: origin, destination: destination, transport: transport, ranking: ranking)
    }

    func makeNavigationSessionViewModel(_ request: NavigationRequest) -> NavigationSessionViewModel {
        NavigationSessionViewModel(journey: request.journey, alternatives: request.alternatives,
                                   transport: transport, ranking: ranking)
    }

    func makeRoutePreviewViewModel(_ ranked: RankedJourney) -> RoutePreviewViewModel {
        RoutePreviewViewModel(ranked: ranked, transport: transport, routes: walkingRoutes)
    }

    func makeCapabilityTestViewModel() -> CapabilityTestViewModel {
        CapabilityTestViewModel(liveActivity: liveActivity, notifications: notifications)
    }
}
