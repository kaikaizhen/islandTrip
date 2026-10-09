import Foundation
import Observation

/// Phase 0 首頁：驗證 Live Activity 與本機通知能力。
@MainActor
@Observable
final class HomeViewModel {
    enum SimulationStatus: Equatable {
        case idle
        case running(stepIndex: Int)
    }

    struct Notice: Equatable {
        enum Kind: Equatable { case info, warning }
        var kind: Kind
        var text: String
    }

    static let testNotificationDelay: TimeInterval = 5

    private(set) var status: SimulationStatus = .idle
    private(set) var currentStep: NavigationActivityAttributes.ContentState?
    private(set) var notice: Notice?

    let script: SimulatedNavigationScript
    private let liveActivity: any LiveActivityControlling
    private let notifications: any NotificationScheduling
    private let now: () -> Date

    init(
        script: SimulatedNavigationScript = .phase0,
        liveActivity: any LiveActivityControlling,
        notifications: any NotificationScheduling,
        now: @escaping () -> Date = Date.init
    ) {
        self.script = script
        self.liveActivity = liveActivity
        self.notifications = notifications
        self.now = now
    }

    var isRunning: Bool { status != .idle }

    private var isLastStep: Bool {
        if case .running(let index) = status { return index >= script.count - 1 }
        return false
    }

    var primaryActionTitle: String {
        switch status {
        case .idle: "開始模擬導航"
        case .running: isLastStep ? "結束模擬" : "模擬下一步"
        }
    }

    /// 底部唯一主要按鈕的行為，依目前狀態決定。
    func performPrimaryAction() async {
        switch status {
        case .idle: await start()
        case .running: isLastStep ? await stop() : await advance()
        }
    }

    func start() async {
        guard !isRunning, let first = script.state(at: 0, updatedAt: now()) else { return }
        status = .running(stepIndex: 0)
        currentStep = first
        notice = nil

        guard liveActivity.areActivitiesEnabled else {
            notice = Notice(kind: .warning, text: "即時動態已關閉，請到「設定 > 一步搭」開啟。App 內仍可繼續模擬。")
            return
        }
        do {
            try liveActivity.start(
                attributes: NavigationActivityAttributes(destinationName: script.destinationName, isSimulated: true),
                state: first
            )
        } catch {
            notice = Notice(kind: .warning, text: "無法啟動即時動態，App 內仍可繼續模擬。")
        }
    }

    func advance() async {
        guard case .running(let index) = status,
              let next = script.state(at: index + 1, updatedAt: now()) else { return }
        status = .running(stepIndex: index + 1)
        currentStep = next
        await liveActivity.update(next)
    }

    func stop() async {
        guard isRunning else { return }
        await liveActivity.end(finalState: nil)
        status = .idle
        currentStep = nil
        notice = Notice(kind: .info, text: "模擬導航已結束。")
    }

    func sendTestNotification() async {
        do {
            switch await notifications.permission() {
            case .denied:
                notice = deniedNotice
                return
            case .notDetermined:
                guard try await notifications.requestPermission() else {
                    notice = deniedNotice
                    return
                }
            case .authorized:
                break
            }
            try await notifications.schedule(
                LocalNotification(identifier: "phase0.test", title: "一步搭（模擬）", body: "120 公尺後右轉"),
                after: Self.testNotificationDelay
            )
            notice = Notice(
                kind: .info,
                text: "\(Int(Self.testNotificationDelay)) 秒後會送出測試通知。可以先鎖定 iPhone，觀察 Apple Watch 是否收到。"
            )
        } catch {
            notice = Notice(kind: .warning, text: "測試通知送出失敗，請稍後再試。")
        }
    }

    private var deniedNotice: Notice {
        Notice(kind: .warning, text: "通知權限已關閉，請到「設定 > 一步搭 > 通知」開啟。")
    }
}
