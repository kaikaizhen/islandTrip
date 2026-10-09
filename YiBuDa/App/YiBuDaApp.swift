import SwiftUI

@main
struct YiBuDaApp: App {
    private let dependencies: AppDependencies
    @State private var homeViewModel: HomeViewModel

    init() {
        let dependencies = AppDependencies.live()
        dependencies.notifications.activate()
        self.dependencies = dependencies
        _homeViewModel = State(initialValue: dependencies.makeHomeViewModel())
    }

    var body: some Scene {
        WindowGroup {
            HomeView(viewModel: homeViewModel)
        }
    }
}
