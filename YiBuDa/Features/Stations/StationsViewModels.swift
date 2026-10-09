import Foundation
import Observation

/// 附近車站（臺鐵、高鐵、捷運）。
@MainActor
@Observable
final class NearbyStationsViewModel {
    enum State: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    let origin: Place
    let radius: Int
    private(set) var state: State = .loading
    private(set) var stations: [RailStation] = []
    private let rail: any RailInfoProviding

    init(origin: Place, rail: any RailInfoProviding, radius: Int = 1500) {
        self.origin = origin
        self.rail = rail
        self.radius = radius
    }

    func load() async {
        state = .loading
        do {
            stations = try await rail.nearbyStations(around: origin.coordinate, radius: radius)
            state = .loaded
        } catch {
            state = .failed("無法取得附近車站，請檢查網路後再試一次。")
        }
    }
}

/// 單一車站的即將發車看板。
@MainActor
@Observable
final class StationBoardViewModel {
    enum State: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    let station: RailStation
    private(set) var state: State = .loading
    private(set) var board: StationBoard?
    /// nil 代表此系統沒有提供通阻資料。
    private(set) var alerts: [RailAlert]?
    /// 通阻消息暫時取不到（和「此系統沒有提供」不同）。
    private(set) var alertsFailed = false
    private let rail: any RailInfoProviding
    private let now: () -> Date

    init(station: RailStation, rail: any RailInfoProviding, now: @escaping () -> Date = Date.init) {
        self.station = station
        self.rail = rail
        self.now = now
    }

    var currentTime: Date { now() }

    /// 有即時資料時才需要自動更新。
    var hasRealtime: Bool { board?.departures.contains { $0.dataLevel == .realtime } == true }

    func load() async {
        do {
            board = try await rail.board(for: station)
            state = .loaded
        } catch {
            // 已有資料時保留舊看板，不清空畫面。
            if board == nil { state = .failed("無法取得發車資訊，請稍後再試。") }
        }
        do {
            alerts = try await rail.alerts(for: station.system)
            alertsFailed = false
        } catch {
            alertsFailed = true
        }
    }
}
