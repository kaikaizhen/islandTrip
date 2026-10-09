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

    /// 班次仍是模擬資料（站牌在台北市政府），所以預設用模擬位置；Phase 3 接上真實資料後改為 GPS。
    var locationSource: LocationSource {
        didSet { defaults.set(locationSource.rawValue, forKey: Self.locationSourceKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        locationSource = defaults.string(forKey: Self.locationSourceKey).flatMap(LocationSource.init) ?? .simulated
    }
}
