import SwiftUI

/// 首頁（草圖 A）：目前位置、目的地輸入、常用地點、超大「開始找車」。
struct HomeView: View {
    @Bindable var viewModel: HomeViewModel
    let onSearchBuses: (_ origin: Place, _ destination: Place) -> Void
    let onOpenSettings: () -> Void

    @FocusState private var isQueryFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing) {
                    header
                    originRow
                    destinationCard
                    if !viewModel.suggestions.isEmpty {
                        suggestionList
                            .id("suggestions")
                    }
                    favoriteGrid
                    if let message = viewModel.errorMessage {
                        SafetyNote(text: message)
                    }
                }
                .padding(Theme.spacing)
            }
            .onChange(of: viewModel.suggestions) { _, suggestions in
                // 字體放大時建議清單容易被鍵盤擋住，出現時捲到可見處。
                guard !suggestions.isEmpty else { return }
                withAnimation { proxy.scrollTo("suggestions", anchor: .bottom) }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.title2)
                }
                .accessibilityLabel("設定")
            }
        }
        // 輸入目的地時隱藏底部按鈕（此時也還不能按），避免浮在鍵盤上擋住建議清單。
        .bottomAction("開始找車", systemImage: "bus.fill", isEnabled: viewModel.canSearchBuses,
                      isVisible: !isQueryFocused) {
            guard let origin = viewModel.origin, let destination = viewModel.destination else { return }
            onSearchBuses(origin, destination)
        }
        .task { await viewModel.load() }
        .task(id: viewModel.query) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await viewModel.search()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("一步搭")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("帶您輕鬆搭車・安心到達")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var originRow: some View {
        Label(viewModel.origin?.name ?? "正在取得目前位置…", systemImage: "location.fill")
            .font(.title3)
            .foregroundStyle(.secondary)
            .accessibilityLabel("出發地：\(viewModel.origin?.name ?? "正在取得目前位置")")
    }

    private var destinationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("目的地", systemImage: "mappin.circle.fill")
                .font(.headline)
                .foregroundStyle(Theme.accent)
            HStack {
                TextField("要去哪裡？", text: $viewModel.query)
                    .font(.title.bold())
                    .focused($isQueryFocused)
                    .submitLabel(.search)
                    .accessibilityIdentifier("destinationField")
                if !viewModel.query.isEmpty {
                    Button {
                        viewModel.clearDestination()
                        isQueryFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("清除目的地")
                }
            }
            .padding(Theme.spacing)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: Theme.cornerRadius - 6, style: .continuous))
        }
        .card()
    }

    private var suggestionList: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.suggestions) { place in
                Button {
                    viewModel.select(place)
                    isQueryFocused = false
                } label: {
                    Label(place.name, systemImage: place.symbolName)
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: Theme.minimumButtonHeight, alignment: .leading)
                        .padding(.horizontal, Theme.spacing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if place.id != viewModel.suggestions.last?.id {
                    Divider()
                }
            }
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private var favoriteGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: Theme.spacing)], spacing: Theme.spacing) {
            ForEach(viewModel.favorites) { place in
                Button {
                    viewModel.select(place)
                    isQueryFocused = false
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: place.symbolName)
                            .font(.largeTitle)
                        Text(place.favoriteTitle)
                            .font(.title3.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 110)
                    .foregroundStyle(viewModel.destination?.id == place.id ? Color.white : Color.primary)
                    .background(
                        viewModel.destination?.id == place.id ? Theme.accent : Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(viewModel.destination?.id == place.id ? .isSelected : [])
            }
        }
    }
}
