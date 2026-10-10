import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// 導航 Live Activity：依階段呈現（決策 D4）。
struct NavigationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NavigationActivityAttributes.self) { context in
            // 鎖定畫面（同時用於 Apple Watch Smart Stack）
            LockScreenNavigationView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    StageIcon(state: context.state, size: 40)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    // 展開時右側也很窄，用短字（「8分」「70m」），長字會被截成「約…」。
                    KeyValueText(state: context.state, compact: true, isStale: context.isStale)
                        .font(.title2.bold())
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.title)
                            .font(.title3.bold())
                            .lineLimit(2)
                        Text(context.state.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        if let action = context.state.action {
                            ActionButton(action: action)
                        }
                        FooterRow(context: context)
                    }
                }
            } compactLeading: {
                StageIcon(state: context.state, size: 18)
            } compactTrailing: {
                KeyValueText(state: context.state, compact: true, isStale: context.isStale)
                    .font(.subheadline.bold())
                    .frame(maxWidth: 64)
            } minimal: {
                StageIcon(state: context.state, size: 16)
            }
        }
        // Apple Watch Smart Stack 使用 .small 版面
        .supplementalActivityFamilies([.small])
    }
}

/// 鎖定畫面按鈕：直接在鎖定畫面確認上車／下車（D4）。
private struct ActionButton: View {
    let action: NavigationActivityAttributes.Action

    var body: some View {
        Button(intent: NavigationActionIntent(action: action)) {
            Label(action.title, systemImage: action == .board ? "bus.fill" : "figure.walk")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .tint(.accentColor)
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
                StageIcon(state: context.state, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.title)
                        .font(.title2.bold())
                        .lineLimit(2)
                    Text(context.state.detail)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                KeyValueText(state: context.state, compact: false, isStale: context.isStale)
                    .font(.title2.bold())
            }
            if let action = context.state.action {
                ActionButton(action: action)
            }
            FooterRow(context: context)
        }
        .padding(16)
    }
}

/// 下一步 + 資料狀態（模擬／表定／過期／更新時間）。
private struct FooterRow: View {
    let context: ActivityViewContext<NavigationActivityAttributes>

    var body: some View {
        HStack {
            if let nextStep = context.state.nextStep {
                Text(nextStep)
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
        var parts: [String] = []
        if context.attributes.isSimulated { parts.append("模擬") }
        if context.state.stage == .waiting, context.state.arrivalIsScheduled { parts.append("表定") }
        parts.append(time)
        return parts.joined(separator: "・")
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
    static let waiting = Self(
        maneuver: .board, title: "等 307", detail: "在 市政府 往板橋方向", distanceMeters: nil,
        nextStep: "在 台北車站 下車", updatedAt: .now, stage: .waiting, routeName: "307",
        arrivalAt: .now.addingTimeInterval(300), arrivalMinutes: 5, action: .board
    )
    static let approaching = Self(
        maneuver: .alight, title: "準備下車", detail: "下一站：台北車站", distanceMeters: nil,
        nextStep: nil, updatedAt: .now, stage: .approaching, routeName: "307", action: .alight
    )
}

#Preview("鎖定畫面", as: .content, using: NavigationActivityAttributes.preview) {
    NavigationLiveActivity()
} contentStates: {
    NavigationActivityAttributes.ContentState.turnRight
    NavigationActivityAttributes.ContentState.waiting
    NavigationActivityAttributes.ContentState.approaching
}

#Preview("動態島・展開", as: .dynamicIsland(.expanded), using: NavigationActivityAttributes.preview) {
    NavigationLiveActivity()
} contentStates: {
    NavigationActivityAttributes.ContentState.turnRight
    NavigationActivityAttributes.ContentState.waiting
}

#Preview("動態島・收合", as: .dynamicIsland(.compact), using: NavigationActivityAttributes.preview) {
    NavigationLiveActivity()
} contentStates: {
    NavigationActivityAttributes.ContentState.turnRight
    NavigationActivityAttributes.ContentState.waiting
}
#endif
