import Foundation
import UserNotifications

/// 以 UserNotifications 實作的本機通知；同時負責讓 App 在前景時也顯示橫幅。
final class UserNotificationScheduler: NSObject, NotificationScheduling, UNUserNotificationCenterDelegate {
    private var center: UNUserNotificationCenter { .current() }

    /// 需在 App 啟動時呼叫一次，才能在前景收到橫幅。
    func activate() {
        center.delegate = self
    }

    func permission() async -> NotificationPermission {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized, .provisional, .ephemeral: .authorized
        @unknown default: .denied
        }
    }

    func requestPermission() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func schedule(_ notification: LocalNotification, after delay: TimeInterval) async throws {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        // 時效性（timeSensitive）需額外 entitlement，Phase 0 先用一般等級。
        content.interruptionLevel = .active

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(delay, 1), repeats: false)
        let request = UNNotificationRequest(identifier: notification.identifier, content: content, trigger: trigger)
        try await center.add(request)
    }

    func cancelAll() async {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
