import SwiftUI

/// 「現在該做什麼」：一個大箭頭 + 一句指令，下方只放下一步。
struct InstructionCard: View {
    let step: NavigationActivityAttributes.ContentState
    @ScaledMetric(relativeTo: .largeTitle) private var arrowSize: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            SimulatedBadge(always: true)

            ManeuverArrow(maneuver: step.maneuver, size: arrowSize)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

            Text(step.title)
                .font(.largeTitle.bold())
            Text(step.detail)
                .font(.title2)
                .foregroundStyle(.secondary)

            if let nextStep = step.nextStep {
                Divider()
                Label(nextStep, systemImage: "bus.fill")
                    .font(.title3.weight(.semibold))
            }

            Text("更新時間 \(step.updatedAt.formatted(date: .omitted, time: .shortened))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("instructionCard")
    }
}
