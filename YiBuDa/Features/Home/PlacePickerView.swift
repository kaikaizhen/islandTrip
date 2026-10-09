import SwiftUI

/// 搜尋並選一個地點（手動輸入出發地、步行測試的目的地共用）。
struct PlacePickerView: View {
    let title: String
    @Bindable var search: PlaceSearchModel
    let near: Coordinate?
    /// 例如「使用目前位置」；nil 時不顯示。
    var currentLocationAction: (() -> Void)?
    let onPick: (Place) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("輸入地點或地址", text: $search.query)
                        .font(.title2)
                        .focused($isFocused)
                        .accessibilityIdentifier("placePickerField")
                }
                if let currentLocationAction {
                    Section {
                        Button {
                            currentLocationAction()
                            dismiss()
                        } label: {
                            Label("使用目前位置", systemImage: "location.fill")
                                .font(.title3)
                                .frame(minHeight: 44)
                        }
                    }
                }
                Section {
                    ForEach(search.suggestions) { place in
                        Button {
                            onPick(place)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name)
                                    .font(.title3.weight(.semibold))
                                if let subtitle = place.subtitle {
                                    Text(subtitle)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(minHeight: 44, alignment: .leading)
                        }
                        .accessibilityIdentifier("pick-\(place.name)")
                    }
                    if let message = search.errorMessage {
                        SafetyNote(text: message)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear { isFocused = true }
            .task(id: search.query) {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await search.search(near: near)
            }
        }
    }
}
