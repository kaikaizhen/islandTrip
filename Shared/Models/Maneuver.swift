import Foundation

/// 導航指令的動作種類，對應到固定的大箭頭圖示。
/// 箭頭由實際步行步驟決定，不由手機朝向或方位角推測。
enum Maneuver: String, Codable, Hashable, Sendable, CaseIterable {
    case straight
    case turnLeft
    case turnRight
    case slightLeft
    case slightRight
    case uTurn
    case crossStreet
    case board
    case alight
    case arrive

    /// SF Symbol 名稱。
    var symbolName: String {
        switch self {
        case .straight: "arrow.up"
        case .turnLeft: "arrow.turn.up.left"
        case .turnRight: "arrow.turn.up.right"
        case .slightLeft: "arrow.up.left"
        case .slightRight: "arrow.up.right"
        case .uTurn: "arrow.uturn.down"
        case .crossStreet: "figure.walk"
        case .board: "bus.fill"
        case .alight: "bell.fill"
        case .arrive: "flag.checkered"
        }
    }

    /// VoiceOver 朗讀用的白話描述。
    var accessibilityDescription: String {
        switch self {
        case .straight: "直走"
        case .turnLeft: "左轉"
        case .turnRight: "右轉"
        case .slightLeft: "往左前方"
        case .slightRight: "往右前方"
        case .uTurn: "迴轉"
        case .crossStreet: "過馬路"
        case .board: "上車"
        case .alight: "準備下車"
        case .arrive: "已到達"
        }
    }
}
