import Foundation
import Observation

enum AppRoute: Hashable {
    case options(origin: Place, destination: Place)
    case settings
}

/// 要開始的一趟導航（全螢幕呈現）。
struct NavigationRequest: Identifiable {
    let id = UUID()
    let journey: Journey
    let alternatives: [Journey]
}

/// 畫面流程：首頁 → 推薦班次（push）→ 導航（全螢幕，避免誤觸返回而中斷）。
@MainActor
@Observable
final class AppRouter {
    var path: [AppRoute] = []
    var navigation: NavigationRequest?

    func showOptions(origin: Place, destination: Place) {
        path.append(.options(origin: origin, destination: destination))
    }

    func showSettings() {
        path.append(.settings)
    }

    func startNavigation(journey: Journey, alternatives: [Journey]) {
        navigation = NavigationRequest(journey: journey, alternatives: alternatives)
    }

    /// 導航結束後回到首頁。
    func finishNavigation() {
        navigation = nil
        path.removeAll()
    }
}
