import Foundation
import Observation

enum LocationSource: String, CaseIterable, Sendable {
    /// 真實 GPS。
    case gps
    /// 固定在台北市政府附近，配合模擬班次使用。
    case simulated

    var title: String {
        switch self {
        case .gps: "GPS（真實位置）"
        case .simulated: "模擬（台北市政府附近）"
        }
    }
}

/// 使用者設定，存在本機。
@MainActor
@Observable
final class AppSettings {
    private static let locationSourceKey = "locationSource"
    private let defaults: UserDefaults

    var locationSource: LocationSource {
        didSet { defaults.set(locationSource.rawValue, forKey: Self.locationSourceKey) }
    }

    /// - Parameter defaultSource: 使用者還沒選過時的預設值；真實班次時預設 GPS，模擬班次時預設模擬位置。
    init(defaults: UserDefaults = .standard, defaultSource: LocationSource = .simulated) {
        self.defaults = defaults
        locationSource = defaults.string(forKey: Self.locationSourceKey).flatMap(LocationSource.init) ?? defaultSource
    }
}
