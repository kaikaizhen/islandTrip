import Foundation

/// 步行路線（座標序列 + 預估時間），與 MapKit 型別分離以便測試。
struct WalkingRoute: Hashable, Sendable {
    struct Step: Hashable, Sendable {
        /// Apple 地圖的原文指示，例：「右轉進入忠孝東路五段」。
        var mapKitInstruction: String
        var distanceMeters: Int
        var coordinates: [Coordinate]
    }

    var coordinates: [Coordinate]
    var expectedSeconds: Int
    var distanceMeters: Int
    var steps: [Step] = []
}

/// 步行路線來源。正式為 Apple MapKit；測試用假物件。
protocol WalkingRouteProviding: Sendable {
    func walkingRoute(from origin: Coordinate, to destination: Coordinate) async throws -> WalkingRoute
}

enum WalkingRouteError: Error, Equatable {
    case noRoute
}
