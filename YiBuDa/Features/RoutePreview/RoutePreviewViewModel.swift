import Foundation
import Observation

struct RouteMarker: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case origin
        case boardingStop
        /// 馬路對面同名、反方向的站牌，提醒「不是這個」。
        case wrongDirectionStop
        case alightingStop
        case destination
    }

    var kind: Kind
    var title: String
    var subtitle: String?
    var coordinate: Coordinate

    var id: Kind { kind }
}

struct RouteSegment: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case walkToStop
        case bus
        case walkToDestination
    }

    var kind: Kind
    var coordinates: [Coordinate]
    /// 不是真實路線（直線示意），畫面需用虛線並說明。
    var isApproximate: Bool

    var id: Kind { kind }
}

/// 選方案前在地圖上確認：起點、正確上車站、對面反向站牌、下車站、目的地與路線。
@MainActor
@Observable
final class RoutePreviewViewModel {
    enum WalkState: Equatable {
        case loading
        case route(WalkingRoute)
        case unavailable
    }

    let ranked: RankedJourney
    /// 使用真實位置時才在地圖上顯示「我在哪、手機朝哪」；模擬位置與實際所在地不同，不顯示。
    let showsLiveLocation: Bool
    private(set) var oppositeStop: Stop?
    private(set) var walkToStop: WalkState = .loading
    private(set) var walkToDestination: WalkState = .loading

    private let transport: any TransportProvider
    private let routes: any WalkingRouteProviding

    init(ranked: RankedJourney, transport: any TransportProvider, routes: any WalkingRouteProviding,
         showsLiveLocation: Bool = false) {
        self.ranked = ranked
        self.showsLiveLocation = showsLiveLocation
        self.transport = transport
        self.routes = routes
    }

    private var journey: Journey { ranked.journey }
    var bus: BusLeg? { journey.busLeg }

    func load() async {
        guard let bus else { return }
        let routes = routes
        let transport = transport
        let origin = journey.origin.coordinate
        let destination = journey.destination.coordinate

        async let toStop = Self.route(routes, from: origin, to: bus.boardingStop.coordinate)
        async let toDestination = Self.route(routes, from: bus.alightingStop.coordinate, to: destination)
        async let details = try? transport.getStopDetails(stopUID: bus.boardingStop.stopUID)

        walkToStop = await toStop
        walkToDestination = await toDestination
        oppositeStop = bus.boardingStop.validOpposite(await details?.oppositeStop)
    }

    var markers: [RouteMarker] {
        guard let bus else { return [] }
        var markers = [
            RouteMarker(kind: .origin, title: "你在這裡", subtitle: journey.origin.name, coordinate: journey.origin.coordinate),
            RouteMarker(kind: .alightingStop, title: "在這裡下車", subtitle: bus.alightingStop.name, coordinate: bus.alightingStop.coordinate),
            RouteMarker(kind: .destination, title: "目的地", subtitle: journey.destination.name, coordinate: journey.destination.coordinate),
        ]
        if let oppositeStop = bus.boardingStop.validOpposite(oppositeStop) {
            markers.append(RouteMarker(kind: .wrongDirectionStop, title: "不是這個",
                                       subtitle: "\(oppositeStop.name)・\(oppositeStop.directionDescription)",
                                       coordinate: oppositeStop.coordinate))
        }
        // 上車站最後加入：地圖上畫在最上層，不會被其他標記蓋住。
        markers.append(RouteMarker(kind: .boardingStop, title: "在這裡上車",
                                   subtitle: "\(bus.boardingStop.name)・\(bus.boardingStop.directionDescription)",
                                   coordinate: bus.boardingStop.coordinate))
        return markers
    }

    var segments: [RouteSegment] {
        guard let bus else { return [] }
        return [
            Self.segment(.walkToStop, state: walkToStop, from: journey.origin.coordinate, to: bus.boardingStop.coordinate),
            // 尚無公車路線形狀資料（Phase 3 由 TDX 提供），先以直線示意。
            RouteSegment(kind: .bus, coordinates: [bus.boardingStop.coordinate, bus.alightingStop.coordinate], isApproximate: true),
            Self.segment(.walkToDestination, state: walkToDestination, from: bus.alightingStop.coordinate, to: journey.destination.coordinate),
        ]
    }

    /// 上車站附近要看清楚的點：你、正確站牌、對面反向站牌。用來把地圖放大到能分辨馬路兩側。
    var boardingAreaCoordinates: [Coordinate] {
        markers.filter { [.origin, .boardingStop, .wrongDirectionStop].contains($0.kind) }.map(\.coordinate)
    }

    /// 例：「走約 3 分鐘（Apple 地圖）」
    func walkSummary(_ state: WalkState) -> String {
        switch state {
        case .loading: "正在計算步行路線…"
        case .route(let route): "走約 \(max(1, Int((Double(route.expectedSeconds) / 60).rounded(.up)))) 分鐘・\(route.distanceMeters) 公尺（Apple 地圖）"
        case .unavailable: "無法取得步行路線，地圖上以直線示意"
        }
    }

    private static func route(_ routes: any WalkingRouteProviding, from: Coordinate, to: Coordinate) async -> WalkState {
        do {
            return .route(try await routes.walkingRoute(from: from, to: to))
        } catch {
            return .unavailable
        }
    }

    private static func segment(_ kind: RouteSegment.Kind, state: WalkState, from: Coordinate, to: Coordinate) -> RouteSegment {
        if case .route(let route) = state, route.coordinates.count >= 2 {
            return RouteSegment(kind: kind, coordinates: route.coordinates, isApproximate: false)
        }
        return RouteSegment(kind: kind, coordinates: [from, to], isApproximate: true)
    }
}

/// 讓地圖預覽能以 `.sheet(item:)` 呈現；以物件身分識別。
extension RoutePreviewViewModel: Identifiable {}
