import SwiftUI

/// 管理常用地點：每個欄位都有明確的「更換」「移除」按鈕（不靠長按等隱藏手勢）。
struct FavoritesManagerView: View {
    let viewModel: HomeViewModel
    /// 要更換某個欄位：由首頁開搜尋頁。
    let onChange: (Place.Kind) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmsRemoval: Place.Kind?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(viewModel.favoriteSlots, id: \.kind) { slot in
                        VStack(alignment: .leading, spacing: 10) {
                            Label(slot.kind.label, systemImage: slot.kind.symbolName)
                                .font(.title3.weight(.semibold))
                            Text(slot.place.map { [$0.name, $0.subtitle].compactMap { $0 }.joined(separator: "\n") } ?? "還沒設定")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: Theme.spacing) {
                                Button(slot.place == nil ? "設定" : "更換") { onChange(slot.kind) }
                                    .buttonStyle(.bordered)
                                    .accessibilityIdentifier("changeFavorite-\(slot.kind.rawValue)")
                                if slot.place != nil {
                                    Button("移除", role: .destructive) { confirmsRemoval = slot.kind }
                                        .buttonStyle(.bordered)
                                        .accessibilityIdentifier("removeFavorite-\(slot.kind.rawValue)")
                                }
                            }
                            .font(.headline)
                        }
                        .padding(.vertical, 6)
                    }
                } footer: {
                    Text("常用地點只存在這支手機，不會上傳。")
                }
            }
            .navigationTitle("常用地點")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .confirmationDialog("要移除「\(confirmsRemoval?.label ?? "")」嗎？", isPresented: Binding(
                get: { confirmsRemoval != nil }, set: { if !$0 { confirmsRemoval = nil } }
            ), titleVisibility: .visible) {
                Button("移除", role: .destructive) {
                    if let kind = confirmsRemoval { Task { await viewModel.removeFavorite(kind) } }
                }
                Button("取消", role: .cancel) {}
            }
        }
    }
}
