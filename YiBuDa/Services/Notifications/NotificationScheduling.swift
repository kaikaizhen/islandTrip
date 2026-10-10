import Foundation

enum NotificationPermission: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
}

struct LocalNotification: Equatable, Sendable {
    var identifier: String
    var title: String
    var body: String
}

/// 本機通知的抽象介面。是否轉送到 Apple Watch 由 iOS 決定，App 無法控制。
protocol NotificationScheduling: Sendable {
    func permission() async -> NotificationPermission
    /// 回傳使用者是否允許通知。
    func requestPermission() async throws -> Bool
    func schedule(_ notification: LocalNotification, after delay: TimeInterval) async throws
    /// 取消尚未送出與已送出的指定通知（例：已上車就不再提醒「車快到了」）。
    func cancel(identifiers: [String]) async
    func cancelAll() async
}
