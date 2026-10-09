import Foundation

/// 透過 NAS 後端取得臺鐵、高鐵、捷運資料（見 Backend/README.md 軌道章節）。
struct RemoteRailProvider: RailInfoProviding {
    let client: BackendClient

    private struct StationsResponse: Decodable {
        struct Station: Decodable {
            var system: RailSystem
            var id: String
            var name: String
            var lat: Double
            var lon: Double
            var distance: Int?
        }
        var stations: [Station]
    }

    private struct DeparturesResponse: Decodable {
        struct Item: Decodable {
            struct Headway: Decodable {
                var minMinutes: Int
                var maxMinutes: Int
            }
            var line: String?
            var trainNo: String?
            var destination: String?
            var direction: String?
            var scheduledAt: String?
            var expectedAt: String?
            var delayMinutes: Int?
            var headway: Headway?
            var status: String
            var dataLevel: RailDataLevel
        }
        var generatedAt: String
        var departures: [Item]
        var note: String?
    }

    private struct AlertsResponse: Decodable {
        struct Item: Decodable {
            var id: String
            var title: String
            var description: String
            var severity: String
        }
        var supported: Bool
        var alerts: [Item]
    }

    func nearbyStations(around coordinate: Coordinate, radius: Int) async throws -> [RailStation] {
        let response: StationsResponse = try await client.get("/v1/rail/stations/nearby", query: [
            URLQueryItem(name: "lat", value: String(coordinate.latitude)),
            URLQueryItem(name: "lon", value: String(coordinate.longitude)),
            URLQueryItem(name: "radius", value: String(radius)),
        ])
        return response.stations.map {
            RailStation(system: $0.system, stationID: $0.id, name: $0.name,
                        coordinate: Coordinate(latitude: $0.lat, longitude: $0.lon), distance: $0.distance)
        }
    }

    func board(for station: RailStation) async throws -> StationBoard {
        let response: DeparturesResponse = try await client.get("/v1/rail/departures", query: [
            URLQueryItem(name: "system", value: station.system.rawValue),
            URLQueryItem(name: "stationID", value: station.stationID),
        ])
        let departures = response.departures.enumerated().map { index, item in
            RailDeparture(
                id: "\(index)-\(item.trainNo ?? item.line ?? "")",
                line: item.line, trainNo: item.trainNo, destination: item.destination, direction: item.direction,
                scheduledAt: ISODate.parse(item.scheduledAt), expectedAt: ISODate.parse(item.expectedAt),
                delayMinutes: item.delayMinutes,
                headway: item.headway.map { $0.minMinutes...max($0.minMinutes, $0.maxMinutes) },
                status: RailDepartureStatus(rawValue: item.status) ?? .unknown,
                dataLevel: item.dataLevel
            )
        }
        return StationBoard(station: station, departures: departures, note: response.note,
                            generatedAt: ISODate.parse(response.generatedAt) ?? Date())
    }

    func alerts(for system: RailSystem) async throws -> [RailAlert]? {
        let response: AlertsResponse = try await client.get("/v1/rail/alerts", query: [URLQueryItem(name: "system", value: system.rawValue)])
        guard response.supported else { return nil }
        return response.alerts.map {
            RailAlert(id: $0.id, title: $0.title, description: $0.description, isSuspended: $0.severity == "suspended")
        }
    }
}
