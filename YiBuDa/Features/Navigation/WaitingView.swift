import SwiftUI

/// 候車：正確站牌與方向、同站可搭的多班公車（可改選）、「我已上車」。
struct WaitingView: View {
    let bus: BusLeg
    let options: [RankedJourney]
    let selectedID: Journey.ID
    let now: Date
    let notice: String?
    let onSelect: (RankedJourney) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("在 \(bus.boardingStop.name) 等車")
                        .font(.largeTitle.bold())
                    Text(bus.boardingStop.directionDescription)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

                Text("這些公車都能到目的地，上了哪一班就選哪一班：")
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(options) { option in
                    Button {
                        onSelect(option)
                    } label: {
                        row(option)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("waiting-\(option.option?.routeName ?? option.id)")
                }

                if let notice {
                    SafetyNote(text: notice)
                }
            }
            .padding(Theme.spacing)
        }
    }

    private func row(_ ranked: RankedJourney) -> some View {
        let isSelected = ranked.id == selectedID
        // 特大字體時改為上下排列，倒數時間不被擠壓。
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.spacing))
        return layout {
            VStack(alignment: .leading, spacing: 6) {
                RouteBadge(routeName: ranked.option?.routeName ?? "", size: .title)
                Text(ranked.option?.direction ?? "")
                    .font(.headline)
                Text(TransitFormat.arrival(ranked.arrivalAtDestination, isEstimated: ranked.option?.rideIsEstimated ?? false))
                    .font(.subheadline)
                if ranked.isStale {
                    Label("資訊可能過期", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 8)
            }
            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 6) {
                Text(TransitFormat.busCountdown(ranked.option?.estimatedArrivalAtStop, now: now, unavailableText: ranked.option?.statusNote))
                    .font(.title2.bold())
                    .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                if isSelected {
                    Label("要搭這班", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.spacing)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(isSelected ? Theme.accent : .clear, lineWidth: 3)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
