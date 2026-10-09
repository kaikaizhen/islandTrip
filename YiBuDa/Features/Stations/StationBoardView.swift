import SwiftUI

/// 車站即將發車看板：大字顯示幾分鐘後，每一班都標示資料等級。
struct StationBoardView: View {
    @Bindable var viewModel: StationBoardViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                header
                alertSection
                content
            }
            .padding(Theme.spacing)
        }
        .navigationTitle(viewModel.station.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.load() }
        .task { await viewModel.load() }
        .task {
            // 有即時資料才自動更新，避免無意義的呼叫。
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if viewModel.hasRealtime { await viewModel.load() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(viewModel.station.system.displayName, systemImage: viewModel.station.system.symbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Spacer()
                SimulatedBadge()
            }
            Text("\(viewModel.station.name)站")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            if let note = viewModel.board?.note {
                Label(note, systemImage: "info.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var alertSection: some View {
        if let alerts = viewModel.alerts, !alerts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(alerts) { alert in
                    SafetyNote(text: alert.title)
                    if !alert.description.isEmpty {
                        Text(alert.description)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .card()
            .accessibilityIdentifier("railAlerts")
        } else if viewModel.alertsFailed {
            Label("暫時無法取得營運消息。", systemImage: "wifi.exclamationmark")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if viewModel.alerts == nil, viewModel.state == .loaded {
            Label("\(viewModel.station.system.displayName)的營運異常消息目前無法提供，請留意站內公告。", systemImage: "info.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView("正在取得發車資訊…")
                .frame(maxWidth: .infinity, minHeight: 160)
        case .failed(let message):
            SafetyNote(text: message).card()
        case .loaded:
            let departures = viewModel.board?.departures ?? []
            if departures.isEmpty {
                Label("接下來兩小時沒有查到班次。", systemImage: "clock")
                    .font(.title3)
                    .card()
            } else {
                let now = viewModel.currentTime
                ForEach(departures) { departure in
                    row(departure, now: now)
                }
                if let generatedAt = viewModel.board?.generatedAt {
                    Text("資料 \(TransitFormat.clock(generatedAt)) 更新")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func row(_ departure: RailDeparture, now: Date) -> some View {
        HStack(alignment: .center, spacing: Theme.spacing) {
            VStack(alignment: .leading, spacing: 6) {
                Text(RailFormat.title(departure))
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let secondary = RailFormat.secondary(departure) {
                    Text(secondary)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                Text(RailFormat.dataLevel(departure.dataLevel))
                    .font(.footnote.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .foregroundStyle(departure.dataLevel == .realtime ? Color.white : Color.secondary)
                    .background(departure.dataLevel == .realtime ? Theme.accent : Color.clear, in: Capsule())
                    .overlay(Capsule().strokeBorder(departure.dataLevel == .realtime ? Color.clear : Color.secondary))
            }
            Spacer(minLength: 8)
            Text(RailFormat.primary(departure, now: now))
                .font(.title.bold())
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}
