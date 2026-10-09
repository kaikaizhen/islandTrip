import ActivityKit
import SwiftUI
import WidgetKit

struct NavigationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NavigationActivityAttributes.self) { context in
            // 鎖定畫面（同時用於 Apple Watch Smart Stack）
            LockScreenNavigationView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ManeuverArrow(maneuver: context.state.maneuver, size: 40)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let meters = context.state.distanceMeters {
                        Text(DistanceFormatter.compact(meters))
                            .font(.title2.bold())
                            .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.title)
                            .font(.title3.bold())
                        Text(context.state.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    FooterRow(context: context)
                }
            } compactLeading: {
                ManeuverArrow(maneuver: context.state.maneuver, size: 18)
            } compactTrailing: {
                if let meters = context.state.distanceMeters {
                    Text(DistanceFormatter.compact(meters))
                        .font(.subheadline.bold())
                }
            } minimal: {
                ManeuverArrow(maneuver: context.state.maneuver, size: 16)
            }
        }
        // Apple Watch Smart Stack 使用 .small 版面
        .supplementalActivityFamilies([.small])
    }
}

private struct LockScreenNavigationView: View {
    let context: ActivityViewContext<NavigationActivityAttributes>
    @Environment(\.activityFamily) private var family

    var body: some View {
        switch family {
        case .small:
            WatchNavigationView(
                state: context.state,
                isSimulated: context.attributes.isSimulated,
                isStale: context.isStale
            )
            .activityBackgroundTint(WatchNavigationView.background)
        default:
            phoneLayout
                .activityBackgroundTint(Color(.systemBackground))
        }
    }

    private var phoneLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                ManeuverArrow(maneuver: context.state.maneuver, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.title)
                        .font(.title2.bold())
                    Text(context.state.detail)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            FooterRow(context: context)
        }
        .padding(16)
    }
}

/// 下一步 + 資料狀態（模擬／過期／更新時間）。
private struct FooterRow: View {
    let context: ActivityViewContext<NavigationActivityAttributes>

    var body: some View {
        HStack {
            if let nextStep = context.state.nextStep {
                Label(nextStep, systemImage: "bus.fill")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        if context.isStale { return "資訊可能過期" }
        let time = context.state.updatedAt.formatted(date: .omitted, time: .shortened)
        return context.attributes.isSimulated ? "模擬・\(time)" : time
    }
}

#if DEBUG
private extension NavigationActivityAttributes {
    static let preview = NavigationActivityAttributes(destinationName: "台北車站", isSimulated: true)
}

private extension NavigationActivityAttributes.ContentState {
    static let turnRight = Self(
        maneuver: .turnRight, title: "前方右轉", detail: "120 公尺後右轉",
        distanceMeters: 120, nextStep: "下一步：搭乘 307 公車", updatedAt: .now
    )
}

#Preview("鎖定畫面", as: .content, using: NavigationActivityAttributes.preview) {
    NavigationLiveActivity()
} contentStates: {
    NavigationActivityAttributes.ContentState.turnRight
}

#Preview("動態島・展開", as: .dynamicIsland(.expanded), using: NavigationActivityAttributes.preview) {
    NavigationLiveActivity()
} contentStates: {
    NavigationActivityAttributes.ContentState.turnRight
}

#Preview("動態島・收合", as: .dynamicIsland(.compact), using: NavigationActivityAttributes.preview) {
    NavigationLiveActivity()
} contentStates: {
    NavigationActivityAttributes.ContentState.turnRight
}
#endif
