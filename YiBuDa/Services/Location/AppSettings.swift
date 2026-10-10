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

/// 轉乘方案的排序偏好（計畫 Phase 5）。
enum PlanPreference: String, CaseIterable, Sendable {
    case fastest
    case fewerTransfers
    case lessWalking

    var title: String {
        switch self {
        case .fastest: "最快到達"
        case .fewerTransfers: "少轉乘"
        case .lessWalking: "少走路"
        }
    }
}

/// 步行速度：影響「走過去要多久」與「趕不趕得上」。
enum WalkingPace: String, CaseIterable, Sendable {
    case normal
    case slow

    var title: String {
        switch self {
        case .normal: "一般"
        case .slow: "慢慢走（時間多抓 3 成）"
        }
    }

    /// 步行時間乘上這個倍數。
    var factor: Double {
        switch self {
        case .normal: 1.0
        case .slow: 1.3
        }
    }
}

/// 使用者設定，存在本機。
@MainActor
@Observable
final class AppSettings {
    private static let locationSourceKey = "locationSource"
    private static let planPreferenceKey = "planPreference"
    private static let walkingPaceKey = "walkingPace"
    private static let bufferMinutesKey = "bufferMinutes"
    /// 趕車緩衝可選的分鐘數。
    static let bufferChoices = [2, 4, 6]
    private let defaults: UserDefaults

    var locationSource: LocationSource {
        didSet { defaults.set(locationSource.rawValue, forKey: Self.locationSourceKey) }
    }
    var planPreference: PlanPreference {
        didSet { defaults.set(planPreference.rawValue, forKey: Self.planPreferenceKey) }
    }
    var walkingPace: WalkingPace {
        didSet { defaults.set(walkingPace.rawValue, forKey: Self.walkingPaceKey) }
    }
    /// 走到站牌後預留幾分鐘才算「趕得上」（計畫 4.1 預設 2 分鐘）。
    var bufferMinutes: Int {
        didSet { defaults.set(bufferMinutes, forKey: Self.bufferMinutesKey) }
    }

    /// - Parameter defaultSource: 使用者還沒選過時的預設值；真實班次時預設 GPS，模擬班次時預設模擬位置。
    init(defaults: UserDefaults = .standard, defaultSource: LocationSource = .simulated) {
        self.defaults = defaults
        locationSource = defaults.string(forKey: Self.locationSourceKey).flatMap(LocationSource.init) ?? defaultSource
        planPreference = defaults.string(forKey: Self.planPreferenceKey).flatMap(PlanPreference.init) ?? .fastest
        walkingPace = defaults.string(forKey: Self.walkingPaceKey).flatMap(WalkingPace.init) ?? .normal
        let buffer = defaults.integer(forKey: Self.bufferMinutesKey)
        bufferMinutes = Self.bufferChoices.contains(buffer) ? buffer : 2
    }
}
