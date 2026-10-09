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

    /// 目前只有 Mock 模式；Phase 3 加入真實資料來源時在這裡切換。
    static func live() -> AppDependencies {
        let mock = MockTransportProvider()
        return AppDependencies(
            liveActivity: ActivityKitLiveActivityController(),
            notifications: UserNotificationScheduler(),
            transport: mock,
            places: mock,
            favorites: mock,
            currentPlace: mock,
            ranking: TransitRankingService(),
            walkingRoutes: MapKitWalkingRouteProvider()
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
