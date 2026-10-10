import SwiftUI

/// Apple Watch Smart Stack 的 Live Activity 版面。
/// 手錶永遠是深色背景，且環境的配色會跟隨 iPhone，所以文字顏色明確指定，不用 .primary。
struct WatchNavigationView: View {
    static let background = Color.black
    /// 40mm 手錶 Smart Stack 的保守內容寬度估計（官方未公布確切值）；版面的理想寬度不得超過此值。
    static let widthBudget: CGFloat = 120

    let state: NavigationActivityAttributes.ContentState
    let isSimulated: Bool
    let isStale: Bool

    var body: some View {
        // 箭頭在左、文字在右；Smart Stack 高度固定，右側最多三列。
        // 40mm 手錶很窄，系統已有邊距，這裡不再加左右 padding。
        HStack(alignment: .center, spacing: 6) {
            StageIcon(state: state, size: 28)
                .foregroundStyle(state.stage == .walking ? Theme.accent : .white)
            VStack(alignment: .leading, spacing: 1) {
                Text(state.shortTitle ?? state.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                KeyValueText(state: state, compact: false, maxRouteLength: 4, isStale: isStale)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let status {
                    Text(status)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var status: String? {
        if isStale { return "資訊可能過期" }
        return isSimulated ? "模擬" : nil
    }
}
