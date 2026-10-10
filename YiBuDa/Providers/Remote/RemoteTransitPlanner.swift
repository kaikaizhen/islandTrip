import Foundation

/// 透過 NAS 後端 `/v1/plan` 取得跨運具方案（見 Backend/README.md）。
struct RemoteTransitPlanner: TransitPlanning {
    let client: BackendClient

    /// MaaS 實測要 2～40 秒，後端最多重試一次，所以 App 端等久一點。
    init(client: BackendClient) {
        var client = client
        client.timeout = max(client.timeout, 60)
        self.client = client
    }

    func plans(from origin: Place, to destination: Place) async throws -> [TransitPlan] {
        let response: PlanResponseDTO = try await client.get("/v1/plan", query: [
            URLQueryItem(name: "originLat", value: String(origin.coordinate.latitude)),
            URLQueryItem(name: "originLon", value: String(origin.coordinate.longitude)),
            URLQueryItem(name: "destinationLat", value: String(destination.coordinate.latitude)),
            URLQueryItem(name: "destinationLon", value: String(destination.coordinate.longitude)),
        ])
        let generatedAt = ISODate.parse(response.generatedAt) ?? Date()
        return response.routes.map { Self.plan($0, generatedAt: generatedAt) }
    }

    func refreshed(_ realtime: LegRealtime) async throws -> LegRealtime {
        guard !realtime.city.isEmpty, !realtime.routeUID.isEmpty else { return realtime }
        let response: ArrivalsResponseDTO = try await client.get("/v1/arrivals", query: [
            URLQueryItem(name: "city", value: realtime.city),
            URLQueryItem(name: "stopUID", value: realtime.stopUID),
        ])
        return Self.updating(realtime, with: response)
    }

    func refreshedRail(_ realtime: RailLegRealtime) async throws -> RailLegRealtime? {
        let station = RailStation(system: realtime.system, stationID: realtime.stationID, name: "", coordinate: Coordinate(latitude: 0, longitude: 0))
        let board = try await RemoteRailProvider(client: client).board(for: station)
        return Self.matching(realtime, in: board.departures, now: Date())
    }

    func discoverRail(for leg: TransitLeg, now: Date) async throws -> RailLegRealtime? {
        guard leg.mode == .tra || leg.mode == .metro else { return nil }
        let rail = RemoteRailProvider(client: client)
        let stations = try await rail.nearbyStations(around: leg.from.coordinate, radius: 400)
        for station in Self.candidateStations(stations, for: leg).prefix(4) {
            let board = try await rail.board(for: station)
            if let match = Self.discover(leg, in: board.departures, station: station, now: now) { return match }
        }
        return nil
    }

    /// 同系統類別、站名相同（或 80 公尺內），由近到遠；轉乘站每條線各一筆都要試。
    static func candidateStations(_ stations: [RailStation], for leg: TransitLeg) -> [RailStation] {
        let wanted = RailName.normalized(leg.from.name)
        return stations
            .filter { leg.mode == .tra ? $0.system == .tra : ($0.system != .tra && $0.system != .thsr) }
            .filter { station in
                let distance = station.distance ?? Int(Geo.distance(station.coordinate, leg.from.coordinate))
                return (!wanted.isEmpty && RailName.normalized(station.name) == wanted) ? distance <= 400 : distance <= 80
            }
            .sorted { ($0.distance ?? 0) < ($1.distance ?? 0) }
    }

    /// 與後端相同規則：臺鐵表定開車相差 2 分鐘內且只有一班；捷運同終點最早一班。只用即時資料。
    static func discover(_ leg: TransitLeg, in departures: [RailDeparture], station: RailStation, now: Date) -> RailLegRealtime? {
        let live = departures.filter { $0.dataLevel == .realtime && ($0.expectedAt.map { $0 >= now.addingTimeInterval(-60) } ?? false) }
        let match: RailDeparture?
        if leg.mode == .tra {
            guard let planned = leg.departAt else { return nil }
            let near = live.filter { $0.scheduledAt.map { abs($0.timeIntervalSince(planned)) <= 120 } ?? false }
            match = near.count == 1 ? near.first : nil
        } else {
            let headsign = RailName.normalized(leg.headsign)
            guard !headsign.isEmpty else { return nil }
            match = live.filter { RailName.normalized($0.destination) == headsign }
                .min { ($0.expectedAt ?? .distantFuture) < ($1.expectedAt ?? .distantFuture) }
        }
        guard let match, let expectedAt = match.expectedAt else { return nil }
        return RailLegRealtime(system: station.system, stationID: station.stationID, expectedAt: expectedAt,
                               delayMinutes: leg.mode == .tra ? match.delayMinutes : nil,
                               trainNo: leg.mode == .tra ? match.trainNo : nil, destination: match.destination)
    }

    /// 找同一班車：臺鐵用車次；捷運用終點，取最早一班。只用即時資料。
    static func matching(_ realtime: RailLegRealtime, in departures: [RailDeparture], now: Date) -> RailLegRealtime? {
        let live = departures.filter { $0.dataLevel == .realtime && ($0.expectedAt.map { $0 >= now.addingTimeInterval(-60) } ?? false) }
        let match: RailDeparture?
        if let trainNo = realtime.trainNo {
            match = live.first { $0.trainNo == trainNo }
        } else {
            match = live.filter { $0.destination == realtime.destination }.min { ($0.expectedAt ?? .distantFuture) < ($1.expectedAt ?? .distantFuture) }
        }
        guard let match, let expectedAt = match.expectedAt else { return nil }
        var updated = realtime
        updated.expectedAt = expectedAt
        updated.delayMinutes = realtime.trainNo == nil ? nil : match.delayMinutes
        return updated
    }

    /// 同一站有多條路線：只取這條路線（附屬路線不明時不比對附屬路線）。
    static func updating(_ realtime: LegRealtime, with response: ArrivalsResponseDTO) -> LegRealtime {
        var updated = realtime
        let arrival = response.arrivals.first { arrival in
            arrival.routeUID == realtime.routeUID &&
                (realtime.subRouteUID == nil || arrival.subRouteUID == nil || arrival.subRouteUID == realtime.subRouteUID)
        }
        let at = ISODate.parse(arrival?.arrivalAt)
        updated.arrivalAt = at
        updated.statusNote = at == nil ? RemoteTransportProvider.statusNote(arrival?.status) ?? "查無即時預估" : nil
        updated.updatedAt = ISODate.parse(arrival?.dataTime) ?? ISODate.parse(response.generatedAt) ?? Date()
        return updated
    }

    // MARK: 轉換

    static func plan(_ dto: PlanRouteDTO, generatedAt: Date) -> TransitPlan {
        TransitPlan(id: dto.id, durationSeconds: dto.durationSeconds, startAt: ISODate.parse(dto.startAt),
                    endAt: ISODate.parse(dto.endAt), transfers: dto.transfers,
                    legs: dto.legs.compactMap(leg), generatedAt: generatedAt)
    }

    /// 不認得的段落種類略過（後端日後新增種類時 App 不會壞）。
    static func leg(_ dto: PlanLegDTO) -> PlanLeg? {
        switch dto.kind {
        case "walk":
            guard let from = dto.from, let to = dto.to else { return nil }
            return .walk(WalkPlanLeg(from: place(from), to: place(to), seconds: dto.seconds ?? 0,
                                     meters: dto.meters ?? 0, inStation: dto.inStation ?? false))
        case "wait":
            guard let at = dto.at else { return nil }
            return .wait(WaitPlanLeg(at: place(at), seconds: dto.seconds ?? 0))
        case "transit":
            guard let from = dto.from, let to = dto.to else { return nil }
            return .transit(TransitLeg(
                mode: dto.mode ?? .other, line: dto.line ?? "", headsign: dto.headsign,
                from: place(from), to: place(to),
                departAt: ISODate.parse(dto.departAt), arriveAt: ISODate.parse(dto.arriveAt),
                stops: (dto.stops ?? []).map(place),
                realtime: dto.realtime.map { realtime(from: $0, headsign: dto.headsign) },
                railRealtime: dto.railRealtime.flatMap { rail in
                    ISODate.parse(rail.expectedAt).map {
                        RailLegRealtime(system: rail.system, stationID: rail.stationID, expectedAt: $0,
                                        delayMinutes: rail.delayMinutes, trainNo: rail.trainNo, destination: rail.destination)
                    }
                }
            ))
        default:
            return nil
        }
    }

    static func realtime(from dto: PlanLegDTO.Realtime, headsign: String?) -> LegRealtime {
        let at = ISODate.parse(dto.arrival?.arrivalAt)
        let updatedAt = ISODate.parse(dto.arrival?.dataTime)
        let direction = headsign.map { $0.hasPrefix("往") ? "\($0)方向" : "往\($0)方向" } ?? "請確認站牌上的方向"
        let boarding = dto.boardingStop.map { RemoteTransportProvider.stop($0, direction: direction, dataTime: updatedAt ?? Date()) }
        let opposite = dto.oppositeStop.map {
            RemoteTransportProvider.stop($0, direction: RemoteTransportProvider.bearingText($0.bearing), dataTime: updatedAt ?? Date())
        }
        return LegRealtime(
            stopUID: dto.stopUID, arrivalAt: at,
            statusNote: at == nil ? RemoteTransportProvider.statusNote(dto.arrival?.status) ?? "查無即時預估" : nil,
            updatedAt: updatedAt, city: dto.city, routeUID: dto.routeUID ?? dto.arrival?.routeUID ?? "",
            subRouteUID: dto.subRouteUID ?? dto.arrival?.subRouteUID,
            boardingStop: boarding, oppositeStop: boarding?.validOpposite(opposite)
        )
    }

    static func place(_ dto: PlanPlaceDTO) -> PlanPlace {
        PlanPlace(name: dto.name, coordinate: Coordinate(latitude: dto.lat, longitude: dto.lon))
    }
}

struct PlanResponseDTO: Decodable, Sendable {
    var generatedAt: String
    var routes: [PlanRouteDTO]
}

struct PlanRouteDTO: Decodable, Sendable {
    var id: String
    var durationSeconds: Int
    var startAt: String?
    var endAt: String?
    var transfers: Int
    var legs: [PlanLegDTO]
}

/// 三種段落共用一個寬鬆結構，依 `kind` 取用欄位。
struct PlanLegDTO: Decodable, Sendable {
    struct Realtime: Decodable, Sendable {
        var city: String
        var stopUID: String
        var arrival: ArrivalDTO?
        /// 以下為較新版後端才有的欄位。
        var routeUID: String?
        var subRouteUID: String?
        var boardingStop: StopDTO?
        var oppositeStop: StopDTO?
    }

    var kind: String
    var from: PlanPlaceDTO?
    var to: PlanPlaceDTO?
    var at: PlanPlaceDTO?
    var seconds: Int?
    var meters: Int?
    var inStation: Bool?
    var mode: TransitMode?
    var line: String?
    var headsign: String?
    var departAt: String?
    var arriveAt: String?
    var stops: [PlanPlaceDTO]?
    var realtime: Realtime?
    var railRealtime: RailRealtime?

    struct RailRealtime: Decodable, Sendable {
        var system: RailSystem
        var stationID: String
        var expectedAt: String
        var delayMinutes: Int?
        var trainNo: String?
        var destination: String?
    }

    private enum CodingKeys: String, CodingKey {
        case kind, from, to, at, seconds, meters, inStation, mode, line, headsign, departAt, arriveAt, stops, realtime, railRealtime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        from = try container.decodeIfPresent(PlanPlaceDTO.self, forKey: .from)
        to = try container.decodeIfPresent(PlanPlaceDTO.self, forKey: .to)
        at = try container.decodeIfPresent(PlanPlaceDTO.self, forKey: .at)
        seconds = try container.decodeIfPresent(Int.self, forKey: .seconds)
        meters = try container.decodeIfPresent(Int.self, forKey: .meters)
        inStation = try container.decodeIfPresent(Bool.self, forKey: .inStation)
        // 不認得的運具當作「其他」，不讓整份方案解析失敗。
        mode = try container.decodeIfPresent(String.self, forKey: .mode).map { TransitMode(rawValue: $0) ?? .other }
        line = try container.decodeIfPresent(String.self, forKey: .line)
        headsign = try container.decodeIfPresent(String.self, forKey: .headsign)
        departAt = try container.decodeIfPresent(String.self, forKey: .departAt)
        arriveAt = try container.decodeIfPresent(String.self, forKey: .arriveAt)
        stops = try container.decodeIfPresent([PlanPlaceDTO].self, forKey: .stops)
        realtime = try container.decodeIfPresent(Realtime.self, forKey: .realtime)
        // 不認得的軌道系統等解析失敗時只當成沒有即時資料，不讓整份方案失敗。
        railRealtime = try? container.decodeIfPresent(RailRealtime.self, forKey: .railRealtime)
    }
}

struct PlanPlaceDTO: Decodable, Sendable {
    var name: String?
    var lat: Double
    var lon: Double
}
