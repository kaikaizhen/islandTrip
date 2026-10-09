import SwiftUI

/// 首頁（草圖 A）：目前位置、目的地輸入、常用地點、超大「開始找車」。
struct HomeView: View {
    @Bindable var viewModel: HomeViewModel
    let onSearchBuses: (_ origin: Place, _ destination: Place) -> Void
    let onOpenSettings: () -> Void
    let onOpenStations: (_ origin: Place) -> Void

    @FocusState private var isQueryFocused: Bool
    @State private var originSearch: PlaceSearchModel?

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
                    stationsButton
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
            // 打字停頓後才搜尋，避免每個字都向 Apple 地圖發出請求。
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await viewModel.search()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("島行")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("帶您輕鬆搭車・安心到達")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var originRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                originSearch = viewModel.makeOriginSearch()
            } label: {
                HStack {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("從：\(originTitle)")
                                .font(.title3.weight(.semibold))
                            if let subtitle = viewModel.origin?.subtitle {
                                Text(subtitle)
                                    .font(.subheadline)
                            }
                        }
                    } icon: {
                        Image(systemName: viewModel.isUsingManualOrigin ? "mappin" : "location.fill")
                            .foregroundStyle(Theme.accent)
                    }
                    Spacer(minLength: 8)
                    Text("更改")
                        .font(.headline)
                        .foregroundStyle(Theme.accent)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("出發地：\(originTitle)，點兩下更改")
            .accessibilityIdentifier("originButton")

            if let problem = viewModel.originProblem {
                SafetyNote(text: problem)
            }
        }
        .sheet(item: $originSearch) { search in
            PlacePickerView(
                title: "出發地",
                search: search,
                near: viewModel.origin?.coordinate,
                currentLocationAction: { Task { await viewModel.useCurrentLocation() } }
            ) { place in
                viewModel.setManualOrigin(place)
            }
        }
    }

    private var originTitle: String {
        if let origin = viewModel.origin { return origin.name }
        return viewModel.isLocating ? "正在取得目前位置…" : "尚未取得位置"
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
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.name)
                                .font(.title3.weight(.semibold))
                            if let subtitle = place.subtitle {
                                Text(subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .multilineTextAlignment(.leading)
                    } icon: {
                        Image(systemName: place.symbolName)
                            .foregroundStyle(Theme.accent)
                    }
                    .frame(maxWidth: .infinity, minHeight: Theme.minimumButtonHeight, alignment: .leading)
                    .padding(.horizontal, Theme.spacing)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("suggestion-\(place.name)")
                if place.id != viewModel.suggestions.last?.id {
                    Divider()
                }
            }
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    /// 次要入口：附近的臺鐵、高鐵、捷運車站與即將發車。
    private var stationsButton: some View {
        Button {
            if let origin = viewModel.origin { onOpenStations(origin) }
        } label: {
            Label("附近車站（捷運、臺鐵、高鐵）", systemImage: "tram.fill")
        }
        .buttonStyle(.secondary)
        .disabled(viewModel.origin == nil)
        .accessibilityIdentifier("nearbyStations")
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
