import Foundation
import Observation

/// 導航期間同步 Live Activity 與提醒通知（計畫 Phase 4）。
/// 以 Observation 追蹤導航狀態，不依賴畫面重繪，所以 App 在背景（導航中背景定位）時也會更新。
@MainActor
final class NavigationActivityCoordinator {
    typealias State = NavigationActivityAttributes.ContentState

    private let controller: any LiveActivityControlling
    private let notifications: (any NotificationScheduling)?
    private let actions: NavigationActionCenter
    private let heartbeat: Duration
    private let now: () -> Date

    private var provider: (@MainActor (Date) -> State?)?
    private var attributes: NavigationActivityAttributes?
    private(set) var lastState: State?
    private var heartbeatTask: Task<Void, Never>?
    private var isActive = false

    /// - Parameter heartbeat: 多久重算一次（候車分鐘數會隨時間變），內容沒變也重送更新時間。
    ///   超過 Live Activity 的 staleDate 還沒更新（例如 App 被系統終止）時，畫面會顯示「資訊可能過期」。
    init(controller: any LiveActivityControlling, notifications: (any NotificationScheduling)?,
         actions: NavigationActionCenter = .shared, heartbeat: Duration = .seconds(30), now: @escaping () -> Date = Date.init) {
        self.controller = controller
        self.notifications = notifications
        self.actions = actions
        self.heartbeat = heartbeat
        self.now = now
    }

    /// 開始同步。`state` 會被追蹤：裡面讀到的導航屬性一改變就重新計算。
    /// - Parameter requestsNotificationPermission: 還沒決定過時詢問通知權限（只在真實搭車導航時，模擬與步行測試不問）。
    func start(destinationName: String, isSimulated: Bool, requestsNotificationPermission: Bool = false,
               state: @escaping @MainActor (Date) -> State?,
               onAction: @escaping @MainActor (NavigationActivityAttributes.Action) -> Void) {
        guard !isActive else { return }
        isActive = true
        if requestsNotificationPermission, let notifications {
            Task {
                if await notifications.permission() == .notDetermined { _ = try? await notifications.requestPermission() }
            }
        }
        provider = state
        attributes = NavigationActivityAttributes(destinationName: destinationName, isSimulated: isSimulated)
        actions.setHandler { action in onAction(action) }
        observe()
        heartbeatTask = Task { [weak self, heartbeat] in
            while !Task.isCancelled {
                try? await Task.sleep(for: heartbeat)
                await self?.refresh()
            }
        }
    }

    /// 行程結束或取消：結束 Live Activity、取消導航提醒、停止接收鎖定畫面按鈕。
    func stop() async {
        guard isActive else { return }
        isActive = false
        heartbeatTask?.cancel()
        heartbeatTask = nil
        provider = nil
        actions.setHandler(nil)
        await controller.end(finalState: lastState.map { var final = $0; final.updatedAt = now(); return final })
        await notifications?.cancel(identifiers: NavigationAlertPolicy.allIDs)
        lastState = nil
    }

    private func observe() {
        guard isActive, let provider else { return }
        let time = now()
        let state = withObservationTracking {
            provider(time)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        guard let state else { return }
        Task { await apply(state) }
    }

    /// 只有內容改變才更新；更新時間不算內容。
    func apply(_ state: State) async {
        guard isActive, let attributes else { return }
        let previous = lastState
        if let previous, previous.sameContent(as: state) { return }
        lastState = state
        if !controller.isRunning {
            if controller.areActivitiesEnabled { try? controller.start(attributes: attributes, state: state) }
        } else {
            await controller.update(state)
        }
        await sendAlerts(from: previous, to: state)
    }

    private func refresh() async {
        guard isActive, let provider, var state = provider(now()) else { return }
        if let lastState, !lastState.sameContent(as: state) {
            await apply(state)
            return
        }
        guard controller.isRunning else { return }
        state.updatedAt = now()
        lastState = state
        await controller.update(state)
    }

    private func sendAlerts(from previous: State?, to state: State) async {
        guard let notifications else { return }
        let commands = NavigationAlertPolicy.commands(from: previous, to: state, now: now())
        guard !commands.isEmpty, await notifications.permission() == .authorized else { return }
        for command in commands {
            switch command {
            case .schedule(let notification, let delay):
                try? await notifications.schedule(notification, after: delay)
            case .cancel(let identifiers):
                await notifications.cancel(identifiers: identifiers)
            }
        }
    }
}
