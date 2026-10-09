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
                realtime: dto.realtime.map { realtime in
                    let at = ISODate.parse(realtime.arrival?.arrivalAt)
                    return LegRealtime(
                        stopUID: realtime.stopUID, arrivalAt: at,
                        statusNote: at == nil ? RemoteTransportProvider.statusNote(realtime.arrival?.status) ?? "查無即時預估" : nil,
                        updatedAt: ISODate.parse(realtime.arrival?.dataTime)
                    )
                }
            ))
        default:
            return nil
        }
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

    private enum CodingKeys: String, CodingKey {
        case kind, from, to, at, seconds, meters, inStation, mode, line, headsign, departAt, arriveAt, stops, realtime
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
    }
}

struct PlanPlaceDTO: Decodable, Sendable {
    var name: String?
    var lat: Double
    var lon: Double
}
