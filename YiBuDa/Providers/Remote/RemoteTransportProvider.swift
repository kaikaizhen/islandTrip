import Foundation

/// 透過家中 NAS 後端取得 TDX 真實資料。步行段由 App 以 Apple 地圖另外計算。
actor RemoteTransportProvider: TransportProvider, ServiceAlertProviding {
    private let client: BackendClient
    /// 最近一次查詢到的站牌（含對面站牌與縣市），供上車側確認、候車更新使用。
    private var knownStops: [String: (stop: Stop, opposite: Stop?, city: String)] = [:]

    init(client: BackendClient) {
        self.client = client
    }

    /// 後端不提供文字搜尋站牌；App 以 Apple 地圖搜尋地點。
    func searchStops(_ query: String) async throws -> [Stop] { [] }

    func findJourneys(from origin: Place, to destination: Place) async throws -> [Journey] {
        let response: JourneyResponseDTO = try await client.get("/v1/journeys", query: [
            URLQueryItem(name: "originLat", value: String(origin.coordinate.latitude)),
            URLQueryItem(name: "originLon", value: String(origin.coordinate.longitude)),
            URLQueryItem(name: "destinationLat", value: String(destination.coordinate.latitude)),
            URLQueryItem(name: "destinationLon", value: String(destination.coordinate.longitude)),
        ])
        let generatedAt = ISODate.parse(response.generatedAt) ?? Date()
        return response.candidates.map { candidate in
            let journey = Self.journey(from: candidate, origin: origin, destination: destination, generatedAt: generatedAt)
            if let bus = journey.busLeg {
                let opposite = candidate.oppositeStop.map { Self.stop($0, direction: Self.bearingText($0.bearing), dataTime: generatedAt) }
                // 多條路線共用同一上車站時，對面站牌是同一個實體位置：找到過就保留，不被其他路線的空值覆蓋。
                let known = knownStops[bus.boardingStop.stopUID]?.opposite
                knownStops[bus.boardingStop.stopUID] = (bus.boardingStop, opposite ?? known, candidate.city)
            }
            return journey
        }
    }

    func getArrivals(stopUID: String) async throws -> [StopArrival] {
        guard let known = knownStops[stopUID] else { throw TransportProviderError.stopNotFound }
        let response: ArrivalsResponseDTO = try await client.get("/v1/arrivals", query: [
            URLQueryItem(name: "city", value: known.city),
            URLQueryItem(name: "stopUID", value: stopUID),
        ])
        let generatedAt = ISODate.parse(response.generatedAt) ?? Date()
        return response.arrivals.map { arrival in
            let at = ISODate.parse(arrival.arrivalAt)
            return StopArrival(
                patternId: Self.patternId(routeUID: arrival.routeUID, subRouteUID: arrival.subRouteUID),
                estimatedArrival: at,
                etaSource: at == nil ? .unknown : .realTime,
                updatedAt: ISODate.parse(arrival.dataTime) ?? generatedAt
            )
        }
    }

    /// 上車側：真實資料不提供「使用者在哪一側」，交給 GPS 判斷或詢問使用者。
    func getStopDetails(stopUID: String) async throws -> StopDetails {
        guard let known = knownStops[stopUID] else { throw TransportProviderError.stopNotFound }
        return StopDetails(stop: known.stop, oppositeStop: known.opposite, side: .unknown)
    }

    func alerts(city: String) async throws -> [ServiceAlert] {
        let response: AlertsResponseDTO = try await client.get("/v1/alerts", query: [URLQueryItem(name: "city", value: city)])
        return response.alerts.map { alert in
            ServiceAlert(id: alert.id, title: alert.title, description: alert.description, effect: alert.effect,
                         routeCodes: alert.routeIDs, url: alert.url.flatMap(URL.init(string:)))
        }
    }

    // MARK: 轉換

    static func patternId(routeUID: String, subRouteUID: String?) -> String {
        "\(routeUID)|\(subRouteUID ?? routeUID)"
    }

    static func journey(from candidate: BusCandidateDTO, origin: Place, destination: Place, generatedAt: Date) -> Journey {
        let route = candidate.route
        let patternId = patternId(routeUID: route.uid, subRouteUID: route.subRouteUID)
        let direction = route.headsign.hasSuffix("方向") ? route.headsign : "\(route.headsign)方向"
        let boarding = stop(candidate.boardingStop, direction: direction, dataTime: generatedAt)
        let alighting = stop(candidate.alightingStop, direction: direction, dataTime: generatedAt)
        let arrivalAt = ISODate.parse(candidate.arrival?.arrivalAt)

        let option = BoardingOption(
            id: candidate.id, routeId: route.uid, routeName: route.name, patternId: patternId, direction: route.headsign,
            boardingStopUID: boarding.stopUID, alightingStopUID: alighting.stopUID,
            estimatedArrivalAtStop: arrivalAt, etaSource: arrivalAt == nil ? .unknown : .realTime,
            updatedAt: ISODate.parse(candidate.arrival?.dataTime) ?? generatedAt,
            rideSeconds: candidate.rideSeconds, rideIsEstimated: candidate.rideSource != "vehicle",
            statusNote: arrivalAt == nil ? statusNote(candidate.arrival?.status) : nil,
            city: candidate.city, routeCode: route.id
        )
        // 後端已依站序確認上車站在下車站之前，這裡只保留兩站讓 App 端再驗證一次方向。
        let pattern = RoutePattern(patternId: patternId, routeId: route.uid, routeName: route.name,
                                   directionName: route.headsign, stopUIDs: [boarding.stopUID, alighting.stopUID])
        return Journey(id: candidate.id, origin: origin, destination: destination,
                       legs: [.bus(BusLeg(option: option, boardingStop: boarding, alightingStop: alighting, pattern: pattern))],
                       computedAt: generatedAt)
    }

    static func stop(_ dto: StopDTO, direction: String, dataTime: Date) -> Stop {
        Stop(stopUID: dto.uid, name: dto.name, coordinate: Coordinate(latitude: dto.lat, longitude: dto.lon),
             directionDescription: direction, dataTime: dataTime)
    }

    /// 沒有預估時間的原因（對應後端的 arrival.status）。
    static func statusNote(_ status: String?) -> String? {
        switch status {
        case "notDeparted": "尚未發車"
        case "noStop": "交管不停靠"
        case "lastBusPassed": "末班車已過"
        case "notOperating": "今日未營運"
        case "noBus": "目前沒有車"
        default: nil
        }
    }

    /// 對面站牌只知道方位：E → 東行。
    static func bearingText(_ bearing: String?) -> String {
        let names = ["E": "東行", "W": "西行", "S": "南行", "N": "北行", "SE": "東南行", "NE": "東北行", "SW": "西南行", "NW": "西北行"]
        return bearing.flatMap { names[$0] }.map { "反方向（\($0)）" } ?? "反方向"
    }
}
