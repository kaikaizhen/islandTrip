import SwiftUI

/// 標示目前內容為模擬資料，避免被誤認為即時資訊。使用真實班次時不顯示。
struct SimulatedBadge: View {
    /// 內容本身就是模擬（例如能力測試），不論資料來源都要顯示。
    var always = false
    @Environment(\.isMockTransit) private var isMockTransit

    var body: some View {
        if always || isMockTransit {
            badge
        }
    }

    private var badge: some View {
        Text("模擬資料")
            .font(.footnote.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .overlay(Capsule().strokeBorder(.secondary))
            .foregroundStyle(.secondary)
    }
}
