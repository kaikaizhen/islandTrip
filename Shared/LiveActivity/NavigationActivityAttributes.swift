import ActivityKit
import Foundation

/// App 與 Live Activity 擴充共用的資料契約。
/// Live Activity 本身不連網、不讀 GPS，所有內容都由 App 更新。
struct NavigationActivityAttributes: ActivityAttributes {
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
    }

    var destinationName: String
    /// 為 true 時畫面必須標示「模擬」，避免假資料被當成即時資料。
    var isSimulated: Bool
}
