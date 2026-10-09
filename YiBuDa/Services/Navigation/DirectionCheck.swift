import Foundation

/// 「轉到對的方向會震動」的判斷（純邏輯）。
/// 要走的方向取自步行路線本身（目前位置前方一小段路的方向），不是直線指向目的地，
/// 所以不會指向穿越建物或車道的方向（計畫 4.2）。
struct DirectionCheck: Sendable {
    struct Configuration: Sendable {
        /// 夾角小於此值算對準。
        var alignTolerance = 20.0
        /// 已對準後，夾角大於此值才算偏掉（滯後，避免在邊界反覆震動）。
        var releaseTolerance = 35.0
        /// 指南針誤差大於此值就不判斷。
        var maximumHeadingError = 30.0
        /// 大於此夾角請使用者「向後轉」。
        var turnAroundAngle = 150.0
    }

    enum Guidance: Equatable, Sendable {
        /// 指南針不準或無資料：不顯示方向，請使用者校正。
        case unavailable
        case aligned
        case turnLeft
        case turnRight
        case turnAround
    }

    private let configuration: Configuration
    private(set) var isAligned = false
    /// 要走的方向相對於手機頂端的角度（度，正值在右）；畫面上的箭頭依此旋轉。
    private(set) var relativeAngle: Double?

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    mutating func update(heading: HeadingSample, walkBearing: Double) -> Guidance {
        guard heading.accuracy >= 0, heading.accuracy <= configuration.maximumHeadingError else {
            isAligned = false
            relativeAngle = nil
            return .unavailable
        }
        let angle = Geo.turnAngle(from: heading.degrees, to: walkBearing)
        relativeAngle = angle
        isAligned = abs(angle) <= (isAligned ? configuration.releaseTolerance : configuration.alignTolerance)
        if isAligned { return .aligned }
        if abs(angle) >= configuration.turnAroundAngle { return .turnAround }
        return angle > 0 ? .turnRight : .turnLeft
    }

    mutating func reset() {
        isAligned = false
        relativeAngle = nil
    }

    /// 沿步行路徑「現在該往哪走」的方位：從目前位置在路徑上的投影點，看向前方 `lookAhead` 公尺。
    /// 沒有目前位置時用這一步起點的方向。
    static func walkBearing(along path: [Coordinate], from position: Coordinate?, lookAhead: Double = 20) -> Double? {
        guard path.count >= 2 else { return nil }
        let along = position.flatMap { Geo.projection(of: $0, onto: path)?.along } ?? 0
        let length = Geo.length(of: path)
        // 太接近這一步終點時，往回取一點，避免方向因距離太短而亂跳。
        let start = min(along, max(0, length - lookAhead))
        guard let from = Geo.point(along: path, meters: start),
              let to = Geo.point(along: path, meters: min(length, start + lookAhead)),
              Geo.distance(from, to) > 1 else { return nil }
        return Geo.bearing(from: from, to: to)
    }
}
