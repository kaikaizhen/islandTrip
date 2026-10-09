import SwiftUI

/// 推薦班次：同站多條路線，主推一班，其他可展開。
struct BoardingOptionsView: View {
    @Bindable var viewModel: BoardingOptionsViewModel
    let onStart: (_ journey: Journey, _ alternatives: [Journey]) -> Void
    let makePreview: (RankedJourney) -> RoutePreviewViewModel

    @State private var showsOthers = false
    @State private var preview: RoutePreviewViewModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                HStack {
                    Text("到 \(viewModel.destination.name)")
                        .font(.title.bold())
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    SimulatedBadge()
                }
                // 目的地可能是真實地點，但班次仍是固定的模擬資料，必須說清楚。
                Label("班次與站牌是模擬資料，尚未依這個目的地計算。", systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                content
            }
            .padding(Theme.spacing)
        }
        .navigationTitle("推薦班次")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.load() }
        .bottomAction(viewModel.startTitle, systemImage: "location.fill", isEnabled: viewModel.selected != nil,
                      secondary: viewModel.selected.map { selected in
                          ("在地圖上確認", { preview = makePreview(selected) })
                      }) {
            guard let selected = viewModel.selected else { return }
            onStart(selected.journey, viewModel.alternatives(for: selected))
        }
        .sheet(item: $preview) { preview in
            RoutePreviewView(viewModel: preview) {
                viewModel.select(preview.ranked)
            }
        }
        .task { await viewModel.load() }
        .task {
            // 倒數與「能否趕上」會隨時間改變，定期重新評估。
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                viewModel.rerank()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView("正在找車…")
                .font(.title3)
                .frame(maxWidth: .infinity, minHeight: 200)
        case .failed(let message):
            SafetyNote(text: message)
                .card()
        case .loaded:
            loadedContent
        }
    }

    @ViewBuilder
    private var loadedContent: some View {
        let now = viewModel.currentTime
        if let recommended = viewModel.recommended {
            optionButton(recommended, now: now, isRecommended: true)
        } else {
            SafetyNote(text: "目前沒有確定趕得上的班次，請從下面挑一班或稍後再查。")
                .card()
        }

        if !viewModel.others.isEmpty {
            DisclosureGroup(isExpanded: $showsOthers) {
                VStack(spacing: Theme.spacing) {
                    Picker("排序", selection: $viewModel.order) {
                        Text("最快到目的地").tag(JourneySortOrder.earliestArrival)
                        Text("最快到站").tag(JourneySortOrder.soonestBus)
                    }
                    .pickerStyle(.segmented)
                    ForEach(viewModel.others) { journey in
                        optionButton(journey, now: now)
                    }
                }
                .padding(.top, 8)
            } label: {
                Text("其他 \(viewModel.others.count) 個方案")
                    .font(.title3.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("otherOptions")
        }
    }

    private func optionButton(_ journey: RankedJourney, now: Date, isRecommended: Bool = false) -> some View {
        Button {
            viewModel.select(journey)
        } label: {
            BoardingOptionCard(ranked: journey, now: now, isRecommended: isRecommended,
                               isSelected: viewModel.selectedID == journey.id)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("option-\(journey.option?.routeName ?? journey.id)")
    }
}
