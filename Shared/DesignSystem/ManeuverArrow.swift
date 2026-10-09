import SwiftUI

/// 高辨識度的大箭頭。App 與 Live Activity 共用同一套圖示。
struct ManeuverArrow: View {
    let maneuver: Maneuver
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: maneuver.symbolName)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(Theme.accent)
            .accessibilityLabel(maneuver.accessibilityDescription)
    }
}
