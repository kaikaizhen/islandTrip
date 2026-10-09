import Foundation

/// 離線模擬的車站與發車資訊（不是真實班次）。涵蓋三種資料等級，方便檢查畫面標示。
struct MockRailProvider: RailInfoProviding {
    var now: @Sendable () -> Date = { Date() }

    static let stations: [RailStation] = [
        RailStation(system: .trtc, stationID: "BL18", name: "市政府", coordinate: Coordinate(latitude: 25.0412, longitude: 121.5652)),
        RailStation(system: .tra, stationID: "1000", name: "臺北", coordinate: Coordinate(latitude: 25.0478, longitude: 121.5170)),
        RailStation(system: .thsr, stationID: "1000", name: "台北", coordinate: Coordinate(latitude: 25.0477, longitude: 121.5171)),
        RailStation(system: .tmrt, stationID: "103", name: "文心崇德", coordinate: Coordinate(latitude: 24.1701, longitude: 120.6852)),
    ]

    func nearbyStations(around coordinate: Coordinate, radius: Int) async throws -> [RailStation] {
        Self.stations
            .map { station in
                var copy = station
                copy.distance = Int(Geo.distance(coordinate, station.coordinate).rounded())
                return copy
            }
            .filter { ($0.distance ?? .max) <= radius }
            .sorted { ($0.distance ?? 0) < ($1.distance ?? 0) }
    }

    func board(for station: RailStation) async throws -> StationBoard {
        let now = now()
        let minutes = { (value: Double) in now.addingTimeInterval(value * 60) }
        let departures: [RailDeparture]
        let note: String?
        switch station.system {
        case .tra:
            departures = [
                RailDeparture(id: "1", line: "自強", trainNo: "111", destination: "高雄", direction: "順行",
                              scheduledAt: minutes(6), expectedAt: minutes(11), delayMinutes: 5, status: .normal, dataLevel: .realtime),
                RailDeparture(id: "2", line: "區間", trainNo: "1234", destination: "基隆", direction: "逆行",
                              scheduledAt: minutes(14), expectedAt: minutes(14), delayMinutes: nil, status: .normal, dataLevel: .timetable),
            ]
            note = nil
        case .thsr:
            departures = [
                RailDeparture(id: "1", line: "高鐵", trainNo: "0603", destination: "左營", direction: "南下",
                              scheduledAt: minutes(9), expectedAt: minutes(9), delayMinutes: nil, status: .normal, dataLevel: .timetable),
            ]
            note = "高鐵沒有即時誤點資料，以下依時刻表。"
        case .tmrt:
            departures = [RailDeparture(id: "1", line: "綠線", headway: 4...6, status: .normal, dataLevel: .frequency)]
            note = "此系統只提供班距，沒有每班時間。"
        default:
            departures = [
                RailDeparture(id: "1", line: "板南線", destination: "南港展覽館", direction: "往南港展覽館",
                              expectedAt: minutes(2), status: .normal, dataLevel: .realtime),
                RailDeparture(id: "2", line: "板南線", destination: "頂埔", direction: "往頂埔",
                              expectedAt: minutes(4), status: .normal, dataLevel: .realtime),
            ]
            note = nil
        }
        return StationBoard(station: station, departures: departures, note: note, generatedAt: now)
    }

    func alerts(for system: RailSystem) async throws -> [RailAlert]? {
        system == .tra || system == .ntmc ? nil : []
    }
}
