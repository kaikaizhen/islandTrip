import SwiftUI

/// 一個方案：路線號、方向、站牌、到站倒數、步行時間、預計抵達、能否趕上、資料時間。
struct BoardingOptionCard: View {
    let ranked: RankedJourney
    let now: Date
    var isRecommended = false
    var isSelected = false
    /// 影響這條路線的異常消息。
    var alerts: [ServiceAlert] = []

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let bus = ranked.journey.busLeg {
            VStack(alignment: .leading, spacing: 10) {
                if isRecommended {
                    Label("推薦", systemImage: "star.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.accent)
                }
                headerRow {
                    VStack(alignment: .leading, spacing: 4) {
                        RouteBadge(routeName: bus.option.routeName, size: isRecommended ? .largeTitle : .title)
                        Text(bus.option.direction)
                            .font(.title3.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    CountdownBox(arrival: bus.option.estimatedArrivalAtStop, now: now,
                                 unavailableText: bus.option.statusNote, isLarge: isRecommended)
                }
                Text("在 \(bus.boardingStop.name)（\(bus.boardingStop.directionDescription)）上車")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                if let walk = ranked.journey.walkToStop {
                    Label(TransitFormat.walkMinutes(walk.seconds) + (walk.isEstimated ? "（估計）" : ""), systemImage: "figure.walk")
                        .font(.body)
                }
                adaptiveRow {
                    CatchStatusLabel(status: ranked.catchStatus)
                    Text(TransitFormat.arrival(ranked.arrivalAtDestination, isEstimated: bus.option.rideIsEstimated))
                        .font(.headline)
                }
                if !alerts.isEmpty {
                    Label("有異常消息：\(alerts.map(\.title).joined(separator: "、"))", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Label(TransitFormat.updated(bus.option.updatedAt, isStale: ranked.isStale),
                      systemImage: ranked.isStale ? "exclamationmark.triangle" : "clock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(Theme.spacing + 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? Theme.accent : .clear, lineWidth: 3)
            }
            .overlay(alignment: .bottomTrailing) {
                // 右上角是倒數框，勾選標記放右下角。
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(Theme.accent)
                        .padding(Theme.spacing)
                        .accessibilityLabel("已選擇")
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        }
    }

    /// 路線與倒數框：一般字體時左右並排、上緣對齊；特大字體時倒數框移到下方。
    private func headerRow(@ViewBuilder content: () -> some View) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return layout(content)
    }

    /// 一般字體時並排；特大字體時改為上下排列，避免文字被擠壓或拆字。
    private func adaptiveRow(@ViewBuilder content: () -> some View) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return layout(content)
    }
}
