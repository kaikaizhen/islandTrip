import SwiftUI

/// 附近車站：臺鐵、高鐵、捷運，由近到遠。
struct NearbyStationsView: View {
    @Bindable var viewModel: NearbyStationsViewModel
    let onSelect: (RailStation) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                HStack {
                    Text("\(RailFormat.distance(viewModel.radius) ?? "")內的車站")
                        .font(.title2.bold())
                    Spacer()
                    SimulatedBadge()
                }
                switch viewModel.state {
                case .loading:
                    ProgressView("正在找車站…")
                        .frame(maxWidth: .infinity, minHeight: 160)
                case .failed(let message):
                    SafetyNote(text: message).card()
                case .loaded where viewModel.stations.isEmpty:
                    Label("附近沒有臺鐵、高鐵或捷運車站。", systemImage: "info.circle")
                        .font(.title3)
                        .card()
                case .loaded:
                    ForEach(viewModel.stations) { station in
                        Button { onSelect(station) } label: { row(station) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("station-\(station.id)")
                    }
                }
            }
            .padding(Theme.spacing)
        }
        .navigationTitle("附近車站")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.load() }
        .task { await viewModel.load() }
    }

    private func row(_ station: RailStation) -> some View {
        HStack(spacing: Theme.spacing) {
            Image(systemName: station.system.symbolName)
                .font(.title)
                .foregroundStyle(Theme.accent)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(station.name)
                    .font(.title2.bold())
                Text(station.system.displayName)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let distance = RailFormat.distance(station.distance) {
                Text(distance)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: Theme.minimumButtonHeight)
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
