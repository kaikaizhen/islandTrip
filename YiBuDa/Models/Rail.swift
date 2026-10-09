import Foundation

/// 軌道系統（TDX 代碼）。
enum RailSystem: String, Hashable, Sendable, CaseIterable, Decodable {
    case tra = "TRA"
    case thsr = "THSR"
    case trtc = "TRTC"
    case ntmc = "NTMC"
    case tymc = "TYMC"
    case krtc = "KRTC"
    case tmrt = "TMRT"

    var displayName: String {
        switch self {
        case .tra: "臺鐵"
        case .thsr: "高鐵"
        case .trtc: "臺北捷運"
        case .ntmc: "新北捷運"
        case .tymc: "桃園機場捷運"
        case .krtc: "高雄捷運"
        case .tmrt: "臺中捷運"
        }
    }

    var symbolName: String {
        switch self {
        case .tra: "train.side.front.car"
        case .thsr: "train.side.rear.car"
        default: "tram.fill"
        }
    }
}

struct RailStation: Identifiable, Hashable, Sendable {
    var system: RailSystem
    var stationID: String
    var name: String
    var coordinate: Coordinate
    /// 與查詢位置的距離（公尺）。
    var distance: Int?

    var id: String { "\(system.rawValue)-\(stationID)" }
}

/// 資料等級：畫面必須標示，不可把時刻表或班距當成即時資訊。
enum RailDataLevel: String, Hashable, Sendable, Decodable {
    case realtime
    case timetable
    case frequency
}

enum RailDepartureStatus: String, Hashable, Sendable, Decodable {
    case normal, notDeparted, noStop, lastPassed, notOperating, suspended, unknown

    /// 不正常時給使用者看的說明。
    var note: String? {
        switch self {
        case .normal, .unknown: nil
        case .notDeparted: "尚未發車"
        case .noStop: "本站不停靠"
        case .lastPassed: "末班車已過"
        case .notOperating: "目前未營運"
        case .suspended: "本站停駛"
        }
    }
}

struct RailDeparture: Identifiable, Hashable, Sendable {
    var id: String
    var line: String?
    var trainNo: String? = nil
    var destination: String? = nil
    var direction: String? = nil
    var scheduledAt: Date? = nil
    var expectedAt: Date? = nil
    var delayMinutes: Int? = nil
    /// 班距（分鐘）；只有班距資料時才有。
    var headway: ClosedRange<Int>? = nil
    var status: RailDepartureStatus
    var dataLevel: RailDataLevel
}

struct StationBoard: Hashable, Sendable {
    var station: RailStation
    var departures: [RailDeparture]
    /// 資料說明，例：「高鐵沒有即時誤點資料，以下依時刻表。」
    var note: String?
    var generatedAt: Date
}

struct RailAlert: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var description: String
    var isSuspended: Bool
}

/// 軌道資料來源：真實資料由 NAS 後端提供，模擬資料離線可用。
protocol RailInfoProviding: Sendable {
    func nearbyStations(around coordinate: Coordinate, radius: Int) async throws -> [RailStation]
    func board(for station: RailStation) async throws -> StationBoard
    /// 回傳 nil 代表此系統沒有提供通阻資料。
    func alerts(for system: RailSystem) async throws -> [RailAlert]?
}
