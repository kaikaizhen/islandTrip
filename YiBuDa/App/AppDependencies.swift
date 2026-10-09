import Foundation

/// Composition root：在這裡決定各協定的具體實作，其餘程式只依賴協定。
@MainActor
struct AppDependencies {
    let liveActivity: any LiveActivityControlling
    let notifications: UserNotificationScheduler

    static func live() -> AppDependencies {
        AppDependencies(
            liveActivity: ActivityKitLiveActivityController(),
            notifications: UserNotificationScheduler()
        )
    }

    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(liveActivity: liveActivity, notifications: notifications)
    }
}
