import SwiftUI

/// 步行（草圖 B）：上方一個超大箭頭、中央一句現在指令、下方下一步與安全提示。
struct WalkingStepView: View {
    let instruction: NavigationInstruction
    let progress: String?
    let nextStep: String?

    @ScaledMetric(relativeTo: .largeTitle) private var arrowSize: CGFloat = 120

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                VStack(spacing: Theme.spacing) {
                    if let progress {
                        Text(progress)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ManeuverArrow(maneuver: instruction.kind, size: arrowSize)
                        .padding(.vertical, Theme.spacing)
                    Text(instruction.displayText)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("currentInstruction")
                    if let detail = instruction.detailText {
                        Text(detail)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let safetyNote = instruction.safetyNote {
                        SafetyNote(text: safetyNote)
                    }
                }
                .frame(maxWidth: .infinity)
                .card()
                .accessibilityElement(children: .combine)

                if let nextStep {
                    NextStepCard(text: nextStep)
                }
            }
            .padding(Theme.spacing)
        }
    }
}
