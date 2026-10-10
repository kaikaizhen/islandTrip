import SwiftUI

/// 根畫面：組合各功能畫面與導覽流程。ViewModel 一律由 AppDependencies 建立。
struct RootView: View {
    let dependencies: AppDependencies
    @State private var router = AppRouter()
    @State private var homeViewModel: HomeViewModel

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _homeViewModel = State(initialValue: dependencies.makeHomeViewModel())
    }

    var body: some View {
        NavigationStack(path: $router.path) {
            HomeView(
                viewModel: homeViewModel,
                onSearchBuses: router.showOptions,
                onOpenSettings: router.showSettings,
                onOpenStations: router.showNearbyStations
            )
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .options(let origin, let destination):
                    BoardingOptionsScreen(
                        viewModel: dependencies.makeBoardingOptionsViewModel(origin: origin, destination: destination),
                        plans: dependencies.makeTransitPlansViewModel(origin: origin, destination: destination),
                        onStartPlan: { plan in
                            router.startPlanNavigation(plan: plan, origin: origin, destination: destination,
                                                       tracksLocation: dependencies.settings.locationSource == .gps)
                        },
                        onStart: { journey, alternatives in
                            router.startNavigation(journey: journey, alternatives: alternatives,
                                                   tracksLocation: dependencies.settings.locationSource == .gps)
                        },
                        makePreview: dependencies.makeRoutePreviewViewModel
                    )
                case .settings:
                    SettingsView(settings: dependencies.settings,
                                 makeCapabilityTestViewModel: dependencies.makeCapabilityTestViewModel,
                                 onOpenWalkTest: router.showWalkTest)
                case .nearbyStations(let origin):
                    NearbyStationsScreen(viewModel: dependencies.makeNearbyStationsViewModel(origin: origin),
                                         onSelect: router.showStationBoard)
                case .stationBoard(let station):
                    StationBoardScreen(viewModel: dependencies.makeStationBoardViewModel(station))
                case .walkTest:
                    WalkTestScreen(viewModel: dependencies.makeWalkTestViewModel()) { journey in
                        router.startNavigation(journey: journey, alternatives: [], tracksLocation: true)
                    }
                }
            }
        }
        .environment(\.isMockTransit, dependencies.isMockTransit)
        .fullScreenCover(item: $router.navigation) { request in
            NavigationSessionScreen(
                viewModel: dependencies.makeNavigationSessionViewModel(request),
                onFinish: router.finishNavigation
            )
            .environment(\.isMockTransit, dependencies.isMockTransit)
        }
        .fullScreenCover(item: $router.planNavigation) { request in
            PlanNavigationScreen(
                viewModel: dependencies.makePlanNavigationViewModel(request),
                onFinish: router.finishNavigation
            )
            .environment(\.isMockTransit, dependencies.isMockTransit)
        }
    }
}

/// 以 @State 持有 ViewModel，避免父畫面重繪時重建而遺失狀態。
private struct BoardingOptionsScreen: View {
    @State var viewModel: BoardingOptionsViewModel
    @State var plans: TransitPlansViewModel
    let onStartPlan: (TransitPlan) -> Void
    let onStart: (Journey, [Journey]) -> Void
    let makePreview: (RankedJourney) -> RoutePreviewViewModel

    var body: some View {
        BoardingOptionsView(viewModel: viewModel, plans: plans, onStartPlan: onStartPlan, onStart: onStart, makePreview: makePreview)
    }
}

private struct NearbyStationsScreen: View {
    @State var viewModel: NearbyStationsViewModel
    let onSelect: (RailStation) -> Void

    var body: some View {
        NearbyStationsView(viewModel: viewModel, onSelect: onSelect)
    }
}

private struct StationBoardScreen: View {
    @State var viewModel: StationBoardViewModel

    var body: some View {
        StationBoardView(viewModel: viewModel)
    }
}

private struct WalkTestScreen: View {
    @State var viewModel: WalkTestViewModel
    let onStart: (Journey) -> Void

    var body: some View {
        WalkTestView(viewModel: viewModel, onStart: onStart)
    }
}

private struct PlanNavigationScreen: View {
    @State var viewModel: PlanNavigationViewModel
    let onFinish: () -> Void

    var body: some View {
        PlanNavigationView(viewModel: viewModel, onFinish: onFinish)
    }
}

private struct NavigationSessionScreen: View {
    @State var viewModel: NavigationSessionViewModel
    let onFinish: () -> Void

    var body: some View {
        NavigationSessionView(viewModel: viewModel, onFinish: onFinish)
    }
}
