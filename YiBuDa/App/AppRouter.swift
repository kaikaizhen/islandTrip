import Foundation
import Observation

enum AppRoute: Hashable {
    case options(origin: Place, destination: Place)
    case settings
    case walkTest
    case nearbyStations(origin: Place)
    case stationBoard(RailStation)
}

/// 要開始的一趟導航（全螢幕呈現）。
struct NavigationRequest: Identifiable {
    let id = UUID()
    let journey: Journey
    let alternatives: [Journey]
    /// 是否用 GPS 自動推進步行步驟。
    let tracksLocation: Bool
}

/// 要開始的一趟轉乘導航（全螢幕呈現）。
struct PlanNavigationRequest: Identifiable {
    let id = UUID()
    let plan: TransitPlan
    let origin: Place
    let destination: Place
    let tracksLocation: Bool
}

/// 畫面流程：首頁 → 推薦班次（push）→ 導航（全螢幕，避免誤觸返回而中斷）。
@MainActor
@Observable
final class AppRouter {
    var path: [AppRoute] = []
    var navigation: NavigationRequest?
    var planNavigation: PlanNavigationRequest?

    func showOptions(origin: Place, destination: Place) {
        path.append(.options(origin: origin, destination: destination))
    }

    func showSettings() {
        path.append(.settings)
    }

    func startNavigation(journey: Journey, alternatives: [Journey], tracksLocation: Bool) {
        navigation = NavigationRequest(journey: journey, alternatives: alternatives, tracksLocation: tracksLocation)
    }

    func showWalkTest() {
        path.append(.walkTest)
    }

    func showNearbyStations(origin: Place) {
        path.append(.nearbyStations(origin: origin))
    }

    func showStationBoard(_ station: RailStation) {
        path.append(.stationBoard(station))
    }

    func startPlanNavigation(plan: TransitPlan, origin: Place, destination: Place, tracksLocation: Bool) {
        planNavigation = PlanNavigationRequest(plan: plan, origin: origin, destination: destination, tracksLocation: tracksLocation)
    }

    /// 導航結束後回到首頁。
    func finishNavigation() {
        navigation = nil
        planNavigation = nil
        path.removeAll()
    }
}
