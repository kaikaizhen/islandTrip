import ActivityKit
import Foundation

/// 以 ActivityKit 實作的 Live Activity 控制器（僅本機更新，不使用推播）。
@MainActor
final class ActivityKitLiveActivityController: LiveActivityControlling {
    /// 超過此時間未更新，系統會將內容標為過期，畫面據此提示「資訊可能過期」。
    private let staleInterval: TimeInterval
    /// 只保存 ID：Activity 不是 Sendable，每次操作時在非隔離環境重新取得實例。
    private var activityID: String?

    init(staleInterval: TimeInterval = 120) {
        self.staleInterval = staleInterval
    }

    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    var isRunning: Bool { activityID != nil }

    func start(
        attributes: NavigationActivityAttributes,
        state: NavigationActivityAttributes.ContentState
    ) throws {
        activityID = try Activity.request(
            attributes: attributes,
            content: content(for: state),
            pushType: nil
        ).id
    }

    func update(_ state: NavigationActivityAttributes.ContentState) async {
        guard let activityID else { return }
        await Self.update(id: activityID, content: content(for: state))
    }

    func end(finalState: NavigationActivityAttributes.ContentState?) async {
        guard let activityID else { return }
        self.activityID = nil
        await Self.end(id: activityID, content: finalState.map(content(for:)))
    }

    private nonisolated static func activity(id: String) -> Activity<NavigationActivityAttributes>? {
        Activity<NavigationActivityAttributes>.activities.first { $0.id == id }
    }

    private nonisolated static func update(
        id: String,
        content: ActivityContent<NavigationActivityAttributes.ContentState>
    ) async {
        await activity(id: id)?.update(content)
    }

    private nonisolated static func end(
        id: String,
        content: ActivityContent<NavigationActivityAttributes.ContentState>?
    ) async {
        await activity(id: id)?.end(content, dismissalPolicy: .immediate)
    }

    private func content(
        for state: NavigationActivityAttributes.ContentState
    ) -> ActivityContent<NavigationActivityAttributes.ContentState> {
        ActivityContent(state: state, staleDate: state.updatedAt.addingTimeInterval(staleInterval))
    }
}
