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
    /// nil 時沿用模擬步行段（UI 測試離線用）。
    let walkPlanner: (any JourneyWalkPlanning)?
    let heading: any HeadingProviding

    /// UI 測試用的啟動參數：目的地搜尋改用離線模擬資料，讓測試不依賴網路。
    static let mockPlaceSearchArgument = "-mockPlaceSearch"
    /// UI 測試用的啟動參數：步行段沿用模擬資料（步驟數固定），不向 Apple 地圖要路線。
    static let mockWalkingArgument = "-mockWalking"

    /// 交通資料目前只有 Mock；Phase 3 加入真實資料來源時在這裡切換。目的地搜尋使用 Apple MapKit。
    static func live(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppDependencies {
        let mock = MockTransportProvider()
        let places: any PlaceSearching = arguments.contains(mockPlaceSearchArgument) ? mock : MapKitPlaceSearch()
        let settings = AppSettings()
        let location = CoreLocationProvider()
        let walkingRoutes = MapKitWalkingRouteProvider()
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
            walkingRoutes: walkingRoutes,
            settings: settings,
            location: location,
            walkPlanner: arguments.contains(mockWalkingArgument) ? nil : WalkingJourneyPlanner(routes: walkingRoutes),
            heading: CoreLocationHeadingProvider()
        )
    }

    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(places: places, favorites: favorites, currentPlace: currentPlace)
    }

    func makeBoardingOptionsViewModel(origin: Place, destination: Place) -> BoardingOptionsViewModel {
        BoardingOptionsViewModel(origin: origin, destination: destination, transport: transport,
                                 walkPlanner: walkPlanner, ranking: ranking)
    }

    func makeNavigationSessionViewModel(_ request: NavigationRequest) -> NavigationSessionViewModel {
        let location = location
        let updates: (@Sendable () -> AsyncThrowingStream<LocationSample, Error>)? =
            request.tracksLocation ? { @Sendable in location.liveUpdates() } : nil
        // 指南針只在使用真實位置時有意義（模擬位置與實際所在地不同）。
        let heading = heading
        let headingUpdates: (@MainActor () -> AsyncStream<HeadingSample>)? =
            request.tracksLocation ? { @MainActor in heading.headingUpdates() } : nil
        return NavigationSessionViewModel(
            journey: request.journey, alternatives: request.alternatives, transport: transport, ranking: ranking,
            locationUpdates: updates,
            walkPlanner: walkPlanner ?? WalkingJourneyPlanner(routes: walkingRoutes),
            headingUpdates: headingUpdates
        )
    }

    func makeRoutePreviewViewModel(_ ranked: RankedJourney) -> RoutePreviewViewModel {
        RoutePreviewViewModel(ranked: ranked, transport: transport, routes: walkingRoutes,
                              showsLiveLocation: settings.locationSource == .gps)
    }

    /// 步行測試一律用真實 GPS 與 Apple 地圖。
    func makeWalkTestViewModel() -> WalkTestViewModel {
        WalkTestViewModel(location: location, places: places, planner: WalkingJourneyPlanner(routes: walkingRoutes))
    }

    func makeCapabilityTestViewModel() -> CapabilityTestViewModel {
        CapabilityTestViewModel(liveActivity: liveActivity, notifications: notifications)
    }
}
