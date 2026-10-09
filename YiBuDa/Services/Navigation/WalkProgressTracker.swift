import Foundation

/// 依 GPS 推進步行步驟。重點是「不亂跳」：
/// - 誤差太大的定位點不改變步驟
/// - 連續數筆都接近轉彎點才前進，每次最多前進一步
/// - 連續數筆都離路線太遠才判定走錯路
/// 純邏輯，所有輸入由呼叫端提供，可用合成的 GPS 軌跡測試。
struct WalkProgressTracker: Sendable {
    struct Configuration: Sendable {
        /// 誤差大於此值的定位點只用來提示「定位不準」，不推進步驟。
        var maximumUsableAccuracy = 50.0
        /// 距離轉彎點多近算到達（實際會依定位誤差放寬，但不超過上限）。
        var arrivalRadius = 15.0
        var maximumArrivalRadius = 30.0
        /// 需要連續幾筆都在到達範圍內才前進一步。
        var samplesToAdvance = 2
        /// 離路線多遠算偏離（實際會依定位誤差放寬）。
        var offRouteDistance = 35.0
        /// 需要連續幾筆都偏離才判定走錯路。
        var samplesToOffRoute = 3
        /// 連續幾筆定位不準才提示。
        var samplesToLowAccuracy = 2
        /// 剩餘距離變大超過此值才更新顯示（避免數字因漂移忽大忽小）。
        var remainingIncreaseThreshold = 20.0
    }

    enum Event: Equatable, Sendable {
        /// 自動前進到下一步。
        case advanced
        /// 走完最後一步。
        case completed
        case wentOffRoute
        case backOnRoute
    }

    private(set) var step: Int
    private(set) var remainingMeters: Int?
    private(set) var isOffRoute = false
    private(set) var isLowAccuracy = false

    private var instructions: [NavigationInstruction]
    private let configuration: Configuration
    private var arrivalStreak = 0
    private var offRouteStreak = 0
    private var lowAccuracyStreak = 0

    init(instructions: [NavigationInstruction], step: Int = 0, configuration: Configuration = Configuration()) {
        self.instructions = instructions
        self.step = step
        self.configuration = configuration
    }

    /// 有真實路徑（非模擬）時才能用 GPS 判斷進度。
    var isTrackable: Bool {
        instructions.indices.contains(step) && instructions[step].path.count >= 2
    }

    mutating func process(_ sample: LocationSample) -> Event? {
        guard isTrackable else { return nil }

        guard sample.horizontalAccuracy >= 0, sample.horizontalAccuracy <= configuration.maximumUsableAccuracy else {
            lowAccuracyStreak += 1
            if lowAccuracyStreak >= configuration.samplesToLowAccuracy { isLowAccuracy = true }
            arrivalStreak = 0
            return nil
        }
        lowAccuracyStreak = 0
        isLowAccuracy = false

        let path = instructions[step].path
        guard let projection = Geo.projection(of: sample.coordinate, onto: path) else { return nil }
        updateRemaining(Geo.length(of: path) - projection.along)

        if let event = checkOffRoute(offset: projection.distance, accuracy: sample.horizontalAccuracy) {
            return event
        }
        guard !isOffRoute else { return nil }

        let target = path.last ?? sample.coordinate
        let radius = min(configuration.maximumArrivalRadius, max(configuration.arrivalRadius, sample.horizontalAccuracy))
        if Geo.distance(sample.coordinate, target) <= radius {
            arrivalStreak += 1
        } else {
            arrivalStreak = 0
        }
        guard arrivalStreak >= configuration.samplesToAdvance else { return nil }
        return advance()
    }

    /// 手動「下一步／回上一步」後同步步驟，並清除累積的判斷。
    mutating func setStep(_ newStep: Int) {
        step = newStep
        resetStreaks()
        remainingMeters = nil
        isOffRoute = false
    }

    /// 重新規劃路線後換成新的指令，從第一步開始。
    mutating func replaceInstructions(_ newInstructions: [NavigationInstruction]) {
        instructions = newInstructions
        setStep(0)
    }

    /// 重新定位：從目前這步起，找出離目前位置最近的那一步（不往回跳）。
    mutating func relocate(to sample: LocationSample) {
        let candidates = instructions.indices.filter { $0 >= step && instructions[$0].path.count >= 2 }
        let nearest = candidates.min { lhs, rhs in
            (Geo.projection(of: sample.coordinate, onto: instructions[lhs].path)?.distance ?? .infinity)
                < (Geo.projection(of: sample.coordinate, onto: instructions[rhs].path)?.distance ?? .infinity)
        }
        if let nearest { setStep(nearest) }
    }

    private mutating func advance() -> Event {
        resetStreaks()
        remainingMeters = nil
        if step + 1 < instructions.count {
            step += 1
            return .advanced
        }
        return .completed
    }

    private mutating func checkOffRoute(offset: Double, accuracy: Double) -> Event? {
        let tolerance = max(configuration.offRouteDistance, accuracy * 1.5)
        if offset > tolerance {
            offRouteStreak += 1
            if !isOffRoute, offRouteStreak >= configuration.samplesToOffRoute {
                isOffRoute = true
                arrivalStreak = 0
                return .wentOffRoute
            }
        } else {
            offRouteStreak = 0
            if isOffRoute {
                isOffRoute = false
                return .backOnRoute
            }
        }
        return nil
    }

    private mutating func updateRemaining(_ meters: Double) {
        let rounded = max(0, Int((meters / 10).rounded()) * 10)
        if let current = remainingMeters, Double(rounded) > Double(current),
           Double(rounded - current) < configuration.remainingIncreaseThreshold {
            return
        }
        remainingMeters = rounded
    }

    private mutating func resetStreaks() {
        arrivalStreak = 0
        offRouteStreak = 0
        lowAccuracyStreak = 0
    }
}
