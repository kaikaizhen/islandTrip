import SwiftUI

/// 全 App 共用的視覺規範：單一藍色、大圓角、大觸控區。
enum Theme {
    /// 唯一的強調色，只用來標示目前主要動作。系統藍會自動適應明暗模式。
    static let accent = Color.blue

    static let cornerRadius: CGFloat = 24
    static let minimumButtonHeight: CGFloat = 60
    static let spacing: CGFloat = 16
}
