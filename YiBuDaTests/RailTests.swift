import Foundation
import Testing
@testable import YiBuDa

struct RailFormatTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func primaryTextByDataLevel() {
        let realtime = RailDeparture(id: "1", line: "板南線", expectedAt: now.addingTimeInterval(150), status: .normal, dataLevel: .realtime)
        #expect(RailFormat.primary(realtime, now: now) == "3 分鐘")
        let arriving = RailDeparture(id: "2", line: "板南線", expectedAt: now.addingTimeInterval(-10), status: .normal, dataLevel: .realtime)
        #expect(RailFormat.primary(arriving, now: now) == "即將進站")
        let headway = RailDeparture(id: "3", line: "綠線", headway: 4...6, status: .normal, dataLevel: .frequency)
        #expect(RailFormat.primary(headway, now: now) == "約每 4–6 分鐘一班")
        let last = RailDeparture(id: "4", line: "板南線", status: .lastPassed, dataLevel: .realtime)
        #expect(RailFormat.primary(last, now: now) == "末班車已過")
        let suspended = RailDeparture(id: "5", line: "區間", trainNo: "1", expectedAt: now, status: .suspended, dataLevel: .timetable)
        #expect(RailFormat.primary(suspended, now: now) == "本站停駛")
    }

    @Test func secondaryShowsDelayOnlyWhenKnown() {
        let late = RailDeparture(id: "1", line: "自強", trainNo: "111", expectedAt: now, delayMinutes: 5, status: .normal, dataLevel: .realtime)
        #expect(RailFormat.secondary(late)?.hasSuffix("開・誤點 5 分") == true)
        let onTime = RailDeparture(id: "2", line: "自強", trainNo: "112", expectedAt: now, delayMinutes: 0, status: .normal, dataLevel: .realtime)
        #expect(RailFormat.secondary(onTime)?.hasSuffix("準點") == true)
        let scheduled = RailDeparture(id: "3", line: "高鐵", trainNo: "0603", expectedAt: now, status: .normal, dataLevel: .timetable)
        #expect(RailFormat.secondary(scheduled)?.contains("誤點") == false, "時刻表資料不能說準點或誤點")
        #expect(RailFormat.dataLevel(.timetable) == "依時刻表")
        #expect(RailFormat.title(late) == "自強 111")
    }
}

@MainActor
struct StationViewModelTests {
    @Test func nearbyStationsWithinRadiusSortedByDistance() async {
        let sut = NearbyStationsViewModel(origin: MockTransitFixture.currentPlace, rail: MockRailProvider())
        await sut.load()
        #expect(sut.state == .loaded)
        #expect(sut.stations.map(\.name) == ["市政府"])
        #expect((sut.stations.first?.distance ?? 9999) < 100)
    }

    @Test func boardSeparatesUnsupportedAlertsFromFailures() async throws {
        let tra = try #require(MockRailProvider.stations.first { $0.system == .tra })
        let sut = StationBoardViewModel(station: tra, rail: MockRailProvider())
        await sut.load()
        #expect(sut.board?.departures.first?.delayMinutes == 5)
        #expect(sut.alerts == nil, "臺鐵通阻欄位尚未核對：顯示「無法提供」")
        #expect(!sut.alertsFailed)
        #expect(sut.hasRealtime)

        struct FailingAlerts: RailInfoProviding {
            func nearbyStations(around coordinate: Coordinate, radius: Int) async throws -> [RailStation] { [] }
            func board(for station: RailStation) async throws -> StationBoard {
                StationBoard(station: station, departures: [], note: nil, generatedAt: .now)
            }
            func alerts(for system: RailSystem) async throws -> [RailAlert]? { throw BackendError.server(502) }
        }
        let failing = StationBoardViewModel(station: tra, rail: FailingAlerts())
        await failing.load()
        #expect(failing.alertsFailed)
        #expect(failing.state == .loaded)
    }

    @Test func thsrBoardIsTimetableWithNote() async throws {
        let thsr = try #require(MockRailProvider.stations.first { $0.system == .thsr })
        let sut = StationBoardViewModel(station: thsr, rail: MockRailProvider())
        await sut.load()
        #expect(sut.board?.note?.contains("時刻表") == true)
        #expect(sut.board?.departures.allSatisfy { $0.dataLevel == .timetable } == true)
        #expect(!sut.hasRealtime)
    }
}
