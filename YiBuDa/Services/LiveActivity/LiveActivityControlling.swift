import Foundation

/// 控制導航 Live Activity 的抽象介面；ViewModel 只依賴此協定，方便以假物件測試。
@MainActor
protocol LiveActivityControlling: AnyObject {
    /// 使用者是否允許此 App 顯示即時動態。
    var areActivitiesEnabled: Bool { get }
    var isRunning: Bool { get }

    func start(
        attributes: NavigationActivityAttributes,
        state: NavigationActivityAttributes.ContentState
    ) throws
    func update(_ state: NavigationActivityAttributes.ContentState) async
    func end(finalState: NavigationActivityAttributes.ContentState?) async
}
