import Foundation

/// 後端回應格式（見 Backend/README.md）。
struct JourneyResponseDTO: Decodable, Sendable {
    var generatedAt: String
    var candidates: [BusCandidateDTO]
}

struct BusCandidateDTO: Decodable, Sendable {
    struct Route: Decodable, Sendable {
        var uid: String
        var id: String?
        var name: String
        var subRouteUID: String?
        var headsign: String
    }

    var id: String
    var city: String
    var route: Route
    var boardingStop: StopDTO
    var alightingStop: StopDTO
    var oppositeStop: StopDTO?
    var stopCount: Int
    var arrival: ArrivalDTO?
    var rideSeconds: Int
    /// vehicle：同一部車的預估相減；stopCount：依站數估計。
    var rideSource: String
}

struct StopDTO: Decodable, Sendable {
    var uid: String
    var name: String
    var lat: Double
    var lon: Double
    var bearing: String?
    var city: String
}

struct ArrivalDTO: Decodable, Sendable {
    var routeUID: String
    var subRouteUID: String?
    var stopUID: String
    var plateNumber: String?
    var arrivalAt: String?
    var status: String
    var isLastBus: Bool
    var dataTime: String?
}

struct ArrivalsResponseDTO: Decodable, Sendable {
    var generatedAt: String
    var arrivals: [ArrivalDTO]
}

struct AlertsResponseDTO: Decodable, Sendable {
    var alerts: [AlertDTO]
}

struct AlertDTO: Decodable, Sendable {
    var id: String
    var city: String
    var title: String
    var description: String
    var status: Int?
    var effect: Int?
    var routeIDs: [String]
    var stopIDs: [String]
    var url: String?
}
