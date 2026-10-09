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
                onOpenSettings: router.showSettings
            )
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .options(let origin, let destination):
                    BoardingOptionsScreen(
                        viewModel: dependencies.makeBoardingOptionsViewModel(origin: origin, destination: destination),
                        onStart: router.startNavigation
                    )
                case .settings:
                    SettingsView(makeCapabilityTestViewModel: dependencies.makeCapabilityTestViewModel)
                }
            }
        }
        .fullScreenCover(item: $router.navigation) { request in
            NavigationSessionScreen(
                viewModel: dependencies.makeNavigationSessionViewModel(request),
                onFinish: router.finishNavigation
            )
        }
    }
}

/// 以 @State 持有 ViewModel，避免父畫面重繪時重建而遺失狀態。
private struct BoardingOptionsScreen: View {
    @State var viewModel: BoardingOptionsViewModel
    let onStart: (Journey, [Journey]) -> Void

    var body: some View {
        BoardingOptionsView(viewModel: viewModel, onStart: onStart)
    }
}

private struct NavigationSessionScreen: View {
    @State var viewModel: NavigationSessionViewModel
    let onFinish: () -> Void

    var body: some View {
        NavigationSessionView(viewModel: viewModel, onFinish: onFinish)
    }
}
