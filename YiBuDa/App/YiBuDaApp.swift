import SwiftUI

@main
struct YiBuDaApp: App {
    private let dependencies: AppDependencies

    init() {
        let dependencies = AppDependencies.live()
        dependencies.notifications.activate()
        self.dependencies = dependencies
    }

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
        }
    }
}
