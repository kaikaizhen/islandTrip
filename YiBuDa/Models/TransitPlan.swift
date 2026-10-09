import Foundation

/// 跨運具方案（公車、捷運、臺鐵、高鐵…可轉乘），來源為 TDX MaaS 旅運規劃。
/// 時間是表定／預估；只有對得上 TDX 站牌的公車段才有即時到站（`TransitLeg.realtime`）。
struct TransitPlan: Identifiable, Hashable, Sendable {
    var id: String
    var durationSeconds: Int
    var startAt: Date?
    var endAt: Date?
    var transfers: Int
    var legs: [PlanLeg]
    /// 後端產生這份方案的時間。
    var generatedAt: Date

    var transitLegs: [TransitLeg] {
        legs.compactMap { if case .transit(let leg) = $0 { leg } else { nil } }
    }

    /// 全程步行公尺（站內步行不算，長輩在意的是出站後要走多遠）。
    var walkMeters: Int {
        legs.reduce(0) { total, leg in
            if case .walk(let walk) = leg, !walk.inStation { total + walk.meters } else { total }
        }
    }
}

enum PlanLeg: Hashable, Sendable {
    case walk(WalkPlanLeg)
    case wait(WaitPlanLeg)
    case transit(TransitLeg)
}

struct PlanPlace: Hashable, Sendable {
    /// 起點、終點常沒有名稱。
    var name: String?
    var coordinate: Coordinate
}

struct WalkPlanLeg: Hashable, Sendable {
    var from: PlanPlace
    var to: PlanPlace
    var seconds: Int
    var meters: Int
    /// 車站內（入口到月台、月台到出口）。
    var inStation: Bool
}

struct WaitPlanLeg: Hashable, Sendable {
    var at: PlanPlace
    var seconds: Int
}

enum TransitMode: String, Hashable, Sendable, Decodable {
    case bus, metro, tra, thsr, lightRail, ferry, other

    var displayName: String {
        switch self {
        case .bus: "公車"
        case .metro: "捷運"
        case .tra: "臺鐵"
        case .thsr: "高鐵"
        case .lightRail: "輕軌"
        case .ferry: "渡輪"
        case .other: "大眾運輸"
        }
    }

    var symbolName: String {
        switch self {
        case .bus: "bus.fill"
        case .metro, .lightRail: "tram.fill"
        case .tra: "train.side.front.car"
        case .thsr: "train.side.rear.car"
        case .ferry: "ferry.fill"
        case .other: "arrow.triangle.swap"
        }
    }
}

struct TransitLeg: Hashable, Sendable {
    var mode: TransitMode
    /// 路線名稱，例：「88建國幹線」「淡水信義線」。
    var line: String
    var headsign: String?
    var from: PlanPlace
    var to: PlanPlace
    /// 表定出發／抵達。
    var departAt: Date?
    var arriveAt: Date?
    /// 中途站（給地圖畫示意線）。
    var stops: [PlanPlace]
    /// 對得上 TDX 站牌時的即時到站；nil 代表只有表定時間。
    var realtime: LegRealtime?
}

/// 公車段的即時到站。`arrivalAt` 為 nil 時看 `statusNote`（例：尚未發車）。
struct LegRealtime: Hashable, Sendable {
    var stopUID: String
    var arrivalAt: Date?
    var statusNote: String?
    var updatedAt: Date?
}
