import SwiftUI

/// 標示目前內容為模擬資料，避免被誤認為即時資訊。
struct SimulatedBadge: View {
    var body: some View {
        Text("模擬資料")
            .font(.footnote.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .overlay(Capsule().strokeBorder(.secondary))
            .foregroundStyle(.secondary)
    }
}
