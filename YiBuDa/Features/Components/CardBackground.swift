import SwiftUI

extension View {
    /// 主要內容卡片：系統次要背景色 + 大圓角，明暗模式自動切換。
    func card() -> some View {
        padding(Theme.spacing + 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}
