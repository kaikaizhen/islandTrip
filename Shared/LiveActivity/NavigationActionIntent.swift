import AppIntents
import Foundation

/// 鎖定畫面「我已上車／我已下車」按鈕（決策 D4）。
/// LiveActivityIntent 在 App 的行程中執行，所以直接交給 App 內的導航處理，不需要 App Group。
struct NavigationActionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "導航操作"
    static let isDiscoverable = false

    @Parameter(title: "動作")
    var action: String

    init() {}

    init(action: NavigationActivityAttributes.Action) {
        self.action = action.rawValue
    }

    func perform() async throws -> some IntentResult {
        if let action = NavigationActivityAttributes.Action(rawValue: action) {
            await NavigationActionCenter.shared.send(action)
        }
        return .result()
    }
}

/// App 內接收鎖定畫面按鈕的地方；目前導航畫面註冊處理方式，結束時取消。
@MainActor
final class NavigationActionCenter {
    static let shared = NavigationActionCenter()
    private var handler: ((NavigationActivityAttributes.Action) -> Void)?

    func setHandler(_ handler: ((NavigationActivityAttributes.Action) -> Void)?) {
        self.handler = handler
    }

    func send(_ action: NavigationActivityAttributes.Action) {
        handler?(action)
    }
}
