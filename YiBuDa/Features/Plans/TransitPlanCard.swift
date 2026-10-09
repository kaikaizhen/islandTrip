import SwiftUI

/// 一個轉乘方案：總時間、抵達時間、各段搭乘（標示即時／表定）、轉乘次數與走路距離。
struct TransitPlanCard: View {
    let plan: TransitPlan
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(PlanFormat.duration(plan.durationSeconds))
                .font(.title2.bold())
            if let endAt = plan.endAt {
                Text(TransitFormat.arrival(endAt))
                    .font(.headline)
            }
            ForEach(Array(plan.transitLegs.enumerated()), id: \.offset) { _, leg in
                legRow(leg)
            }
            Text(PlanFormat.summary(plan))
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func legRow(_ leg: TransitLeg) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text([PlanFormat.lineTitle(leg), PlanFormat.headsign(leg)].compactMap { $0 }.joined(separator: " "))
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: leg.mode.symbolName)
                    .foregroundStyle(Theme.accent)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                DataTagView(isRealtime: PlanFormat.isRealtime(leg))
                Text(PlanFormat.boardingTimeWithoutTag(leg, now: now))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 「即時」「表定」小標籤：文字＋外框，不只靠顏色。
struct DataTagView: View {
    let isRealtime: Bool

    var body: some View {
        Text(isRealtime ? "即時" : "表定")
            .font(.footnote.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(isRealtime ? Theme.accent : .secondary)
            .overlay(Capsule().strokeBorder(isRealtime ? Theme.accent : .secondary))
    }
}
