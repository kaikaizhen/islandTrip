import Foundation

struct Coordinate: Hashable, Sendable {
    var latitude: Double
    var longitude: Double
}

/// 起點或目的地。
struct Place: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case home, work, school, other
    }

    var id: String
    var name: String
    var coordinate: Coordinate
    var kind: Kind = .other

    /// 常用地點的圖示。
    var symbolName: String {
        switch kind {
        case .home: "house.fill"
        case .work: "briefcase.fill"
        case .school: "graduationcap.fill"
        case .other: "mappin.circle.fill"
        }
    }
}
