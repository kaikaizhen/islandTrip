import Foundation

struct Coordinate: Hashable, Sendable {
    var latitude: Double
    var longitude: Double
}

/// 起點或目的地。
struct Place: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable, Codable, CaseIterable {
        case home, work, school, other

        /// 常用地點的三個欄位（依序顯示）。
        static let favoriteSlots: [Kind] = [.home, .work, .school]

        var label: String {
            switch self {
            case .home: "家"
            case .work: "公司"
            case .school: "學校"
            case .other: "其他"
            }
        }
    }

    var id: String
    var name: String
    /// 地址等補充說明，用來分辨同名地點。
    var subtitle: String? = nil
    var coordinate: Coordinate
    var kind: Kind = .other

    /// 常用地點的圖示。
    var symbolName: String { kind.symbolName }
}
