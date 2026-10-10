import ActivityKit
import Foundation

/// App 與 Live Activity 擴充共用的資料契約。
/// Live Activity 本身不連網、不讀 GPS，所有內容都由 App 更新。
struct NavigationActivityAttributes: ActivityAttributes {
    /// 導航階段（決策 D4 的各階段呈現）。
    enum Stage: String, Codable, Hashable, Sendable {
        case walking
        /// 確認上車側：需要過馬路時特別提醒。
        case boardingSide
        case waiting
        case riding
        /// 準備下車。
        case approaching
        case arrived
    }

    /// 鎖定畫面按鈕（D4）：只在候車、搭乘時出現。
    enum Action: String, Codable, Hashable, Sendable {
        case board
        case alight

        var title: String {
            switch self {
            case .board: "我已上車"
            case .alight: "我已下車"
            }
        }
    }

    struct ContentState: Codable, Hashable, Sendable {
        var maneuver: Maneuver
        /// 現在指令，例：「前方右轉」
        var title: String
        /// 補充說明，例：「120 公尺後右轉」
        var detail: String
        var distanceMeters: Int?
        /// 下一步，例：「下一步：搭乘 307 公車」
        var nextStep: String?
        /// 狀態產生時間；畫面需顯示，過期時提示使用者。
        var updatedAt: Date
        var stage: Stage = .walking
        /// 路線名（短名，例：「小9」）。
        var routeName: String?
        /// 車預計到站時間（候車）或預計到下車站時間（搭乘）。
        var arrivalAt: Date?
        /// 候車：還有幾分鐘到站（App 每 30 秒重算）。不用「7:43」式的倒數計時，長輩容易看成時刻。
        var arrivalMinutes: Int?
        /// 到站時間是表定（不是即時）。
        var arrivalIsScheduled = false
        /// 剩餘站數：資料可信時才有，否則為 nil（不可假精確）。
        var remainingStops: Int?
        var action: Action?
        /// 手錶用的短標題（40mm 手錶很窄，例：「等小9」）；nil 時用 title。
        var shortTitle: String?
    }

    var destinationName: String
    /// 為 true 時畫面必須標示「模擬」，避免假資料被當成即時資料。
    var isSimulated: Bool
}
