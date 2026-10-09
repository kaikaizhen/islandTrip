import SwiftUI

/// 「轉到對的方向會震動」：平拿手機慢慢轉身，對準步行路線的方向時圓圈變藍並震動。
struct DirectionCheckCard: View {
    let guidance: DirectionCheck.Guidance
    /// 要走的方向相對手機頂端的角度（度，正值在右）。
    let relativeAngle: Double?

    @ScaledMetric(relativeTo: .largeTitle) private var ringSize: CGFloat = 150

    var body: some View {
        Group {
            switch guidance {
            case .aligned:
                Label("方向對了，往前走", systemImage: "checkmark.circle.fill")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: Theme.minimumButtonHeight)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            case .unavailable:
                Label("指南針不準：請讓手機遠離金屬，在空中慢慢畫「8」字校正。", systemImage: "location.north.line")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .card()
            case .turnLeft, .turnRight, .turnAround:
                aligningCard
            }
        }
        .sensoryFeedback(.success, trigger: guidance == .aligned) { _, isAligned in isAligned }
        .onChange(of: guidance == .aligned) { _, isAligned in
            if isAligned { AccessibilityNotification.Announcement("方向對了，往前走").post() }
        }
        .accessibilityIdentifier("directionCheck")
    }

    private var aligningCard: some View {
        VStack(spacing: Theme.spacing) {
            Text("先對準方向")
                .font(.title2.bold())
            ZStack {
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 6)
                // 手機頂端（正前方）的記號
                Capsule()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 18)
                    .offset(y: -ringSize / 2 + 9)
                Image(systemName: "iphone")
                    .font(.system(size: ringSize * 0.28))
                    .foregroundStyle(.secondary)
                // 要走的方向
                Image(systemName: "arrow.up")
                    .font(.system(size: ringSize * 0.3, weight: .heavy))
                    .foregroundStyle(Theme.accent)
                    .offset(y: -ringSize * 0.3)
                    .rotationEffect(.degrees(relativeAngle ?? 0))
                    .animation(.easeOut(duration: 0.2), value: relativeAngle)
            }
            .frame(width: ringSize, height: ringSize)
            .accessibilityHidden(true)

            Label(instruction, systemImage: symbol)
                .font(.title2.weight(.semibold))
            Text("平拿手機，慢慢轉身，對準時會震動。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .card()
        .accessibilityElement(children: .combine)
    }

    private var instruction: String {
        switch guidance {
        case .turnLeft: "往左轉一點"
        case .turnRight: "往右轉一點"
        case .turnAround: "向後轉"
        default: ""
        }
    }

    private var symbol: String {
        switch guidance {
        case .turnLeft: "arrow.counterclockwise"
        case .turnRight: "arrow.clockwise"
        default: "arrow.uturn.down"
        }
    }
}
