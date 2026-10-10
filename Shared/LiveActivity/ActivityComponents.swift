import SwiftUI

/// 每個階段的主圖示：步行用箭頭，其他用公車、警告、鈴鐺、旗子。
struct StageIcon: View {
    let state: NavigationActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        switch state.stage {
        case .walking:
            ManeuverArrow(maneuver: state.maneuver, size: size)
        case .boardingSide:
            symbol("exclamationmark.triangle.fill", label: "注意上車側")
        case .waiting, .riding:
            symbol("bus.fill", label: state.stage == .waiting ? "候車" : "搭乘中")
        case .approaching:
            symbol("bell.fill", label: "準備下車")
        case .arrived:
            symbol("flag.checkered", label: "已到達")
        }
    }

    private func symbol(_ name: String, label: String) -> some View {
        Image(systemName: name)
            .font(.system(size: size * 0.8, weight: .bold))
            .frame(width: size, height: size)
            .accessibilityLabel(label)
    }
}

/// 最重要的一個數值：步行距離、候車倒數、剩餘站數或短提示。
struct KeyValueText: View {
    let state: NavigationActivityAttributes.ContentState
    let compact: Bool
    /// 路線名超過這個長度就不顯示（手錶太窄，會被截成「…」）；nil 不限制。
    var maxRouteLength: Int?
    /// Live Activity 已過期（App 太久沒更新）。
    var isStale = false

    var body: some View {
        switch state.stage {
        case .walking:
            if let meters = state.distanceMeters {
                Text(compact ? DistanceFormatter.compact(meters) : DistanceFormatter.long(meters))
            }
        case .boardingSide:
            Text(compact ? "看方向" : "確認站牌")
        case .waiting:
            if let minutes = state.arrivalMinutes {
                if isStale {
                    // 太久沒更新：不顯示可能已過時的分鐘數。
                    Text("—")
                } else if minutes == 0 {
                    Text(compact ? "進站" : "即將進站")
                } else if compact {
                    Text("\(minutes)分")
                } else {
                    Text(maxRouteLength == nil ? "約 \(minutes) 分鐘" : "約\(minutes)分")
                }
            } else if let route = state.routeName, maxRouteLength.map({ route.count <= $0 }) ?? true {
                Text(route)
            }
        case .riding:
            if let stops = state.remainingStops {
                // 手錶（有限制路線長度時）用較短的「剩 N 站」。
                Text(compact ? "\(stops)站" : (maxRouteLength == nil ? "還有 \(stops) 站" : "剩 \(stops) 站"))
            } else if let route = state.routeName, maxRouteLength.map({ route.count <= $0 }) ?? true {
                Text(route)
            }
        case .approaching:
            Text("下車")
        case .arrived:
            Text("到了")
        }
    }
}

