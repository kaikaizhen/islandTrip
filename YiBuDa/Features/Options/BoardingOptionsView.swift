import SwiftUI

/// 推薦班次：同站多條路線，主推一班，其他可展開。
struct BoardingOptionsView: View {
    @Bindable var viewModel: BoardingOptionsViewModel
    /// 轉乘方案（只供查看）；nil 時不顯示。
    var plans: TransitPlansViewModel?
    let onStart: (_ journey: Journey, _ alternatives: [Journey]) -> Void
    let makePreview: (RankedJourney) -> RoutePreviewViewModel

    @State private var showsOthers = false
    @Environment(\.isMockTransit) private var isMockTransit
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
                if isMockTransit {
                    // 目的地可能是真實地點，但班次仍是固定的模擬資料，必須說清楚。
                    Label("班次與站牌是模擬資料，尚未依這個目的地計算。", systemImage: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                alertBanner
                content
                if let plans {
                    TransitPlansSection(viewModel: plans)
                        .padding(.top, Theme.spacing)
                }
            }
            .padding(Theme.spacing)
        }
        .navigationTitle("推薦班次")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            async let plansLoad: Void = plans?.load() ?? ()
            await viewModel.load()
            await plansLoad
        }
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
        // 轉乘方案較慢（MaaS），獨立載入，不拖住直達公車。
        .task { if plans?.state == .idle { await plans?.load() } }
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

    @ViewBuilder
    private var alertBanner: some View {
        if !viewModel.alerts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(viewModel.alerts) { alert in
                    VStack(alignment: .leading, spacing: 4) {
                        SafetyNote(text: alert.title)
                        if !alert.description.isEmpty {
                            Text(alert.description)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .card()
            .accessibilityIdentifier("serviceAlerts")
        } else if viewModel.alertsUnavailable {
            Label("暫時無法取得公車異常消息。", systemImage: "wifi.exclamationmark")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func optionButton(_ journey: RankedJourney, now: Date, isRecommended: Bool = false) -> some View {
        Button {
            viewModel.select(journey)
        } label: {
            BoardingOptionCard(ranked: journey, now: now, isRecommended: isRecommended,
                               isSelected: viewModel.selectedID == journey.id, alerts: viewModel.alerts(for: journey))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("option-\(journey.option?.routeName ?? journey.id)")
    }
}
