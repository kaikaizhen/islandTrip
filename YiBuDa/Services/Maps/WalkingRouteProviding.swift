import Foundation

/// 步行路線（座標序列 + 預估時間），與 MapKit 型別分離以便測試。
struct WalkingRoute: Hashable, Sendable {
    var coordinates: [Coordinate]
    var expectedSeconds: Int
    var distanceMeters: Int
}

/// 步行路線來源。正式為 Apple MapKit；測試用假物件。
protocol WalkingRouteProviding: Sendable {
    func walkingRoute(from origin: Coordinate, to destination: Coordinate) async throws -> WalkingRoute
}

enum WalkingRouteError: Error, Equatable {
    case noRoute
}
