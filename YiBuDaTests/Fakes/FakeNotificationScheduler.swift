import Foundation
@testable import YiBuDa

actor FakeNotificationScheduler: NotificationScheduling {
    struct ScheduleError: Error {}

    private var currentPermission: NotificationPermission
    private let grantOnRequest: Bool
    private let failToSchedule: Bool
    private(set) var requestCount = 0
    private(set) var scheduled: [(LocalNotification, TimeInterval)] = []

    init(permission: NotificationPermission, grantOnRequest: Bool = true, failToSchedule: Bool = false) {
        currentPermission = permission
        self.grantOnRequest = grantOnRequest
        self.failToSchedule = failToSchedule
    }

    func permission() async -> NotificationPermission { currentPermission }

    func requestPermission() async throws -> Bool {
        requestCount += 1
        currentPermission = grantOnRequest ? .authorized : .denied
        return grantOnRequest
    }

    func schedule(_ notification: LocalNotification, after delay: TimeInterval) async throws {
        if failToSchedule { throw ScheduleError() }
        scheduled.append((notification, delay))
    }

    func cancelAll() async { scheduled.removeAll() }
}
