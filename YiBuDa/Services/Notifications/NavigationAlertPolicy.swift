import Foundation

/// 導航提醒的通知規則（計畫 Phase 4：接近轉彎、車快到站、準備下車；不重複騷擾）。
/// 純邏輯：依「上一個狀態 → 新狀態」決定要排程或取消哪些通知。
/// 前景時不跳橫幅（見 UserNotificationScheduler），所以這裡不必判斷 App 是否在前景。
enum NavigationAlertPolicy {
    typealias State = NavigationActivityAttributes.ContentState

    static let identifierPrefix = "nav-"
    static let turnID = "nav-turn"
    static let busSoonID = "nav-bus-soon"
    static let alightID = "nav-alight"
    static let allIDs = [turnID, busSoonID, alightID]

    /// 離轉彎點這麼近就提醒。
    static let turnAlertMeters = 30
    /// 車到站、到下車站前多久提醒。
    static let leadTime: TimeInterval = 120

    enum Command: Equatable {
        case schedule(LocalNotification, after: TimeInterval)
        case cancel([String])
    }

    static func commands(from previous: State?, to state: State, now: Date) -> [Command] {
        var commands: [Command] = []
        let stageChanged = previous?.stage != state.stage

        // 離開某階段：取消那個階段排好的通知（已上車就不要再提醒「車快到了」）。
        if stageChanged, let previous {
            switch previous.stage {
            case .waiting: commands.append(.cancel([busSoonID]))
            case .riding where state.stage != .approaching, .approaching: commands.append(.cancel([alightID]))
            default: break
            }
        }

        switch state.stage {
        case .walking:
            if let meters = state.distanceMeters, meters <= turnAlertMeters, isTurn(state.maneuver) {
                let sameStep = previous?.stage == .walking && previous?.title == state.title
                let wasNear = (previous?.distanceMeters).map { $0 <= turnAlertMeters } ?? false
                if !(sameStep && wasNear) {
                    commands.append(.schedule(LocalNotification(identifier: turnID, title: "前方\(state.maneuver.accessibilityDescription)",
                                                                body: state.title), after: 1))
                }
            }
        case .waiting:
            // 新進入候車、或到站時間變了，就重排「車快到了」。
            if let arrivalAt = state.arrivalAt, stageChanged || previous?.arrivalAt != arrivalAt {
                let delay = arrivalAt.addingTimeInterval(-leadTime).timeIntervalSince(now)
                if delay > 0 {
                    let route = state.routeName ?? "車"
                    let body = state.arrivalIsScheduled ? "依表定時間，\(route) 約 2 分鐘後到站。" : "\(route) 約 2 分鐘後到站，請準備上車。"
                    commands.append(.schedule(LocalNotification(identifier: busSoonID, title: "車快到了", body: body), after: delay))
                } else {
                    commands.append(.cancel([busSoonID]))
                }
            }
        case .riding:
            // 預排：地下沒有定位、App 沒被叫醒時，仍會在預計到站前提醒。
            if let alightAt = state.arrivalAt, stageChanged || previous?.arrivalAt != alightAt {
                let delay = alightAt.addingTimeInterval(-leadTime).timeIntervalSince(now)
                if delay > 0 {
                    commands.append(.schedule(LocalNotification(identifier: alightID, title: "準備下車",
                                                                body: "依預計時間快到了：\(state.detail)。請聽車上廣播確認站名。"),
                                              after: delay))
                }
            }
        case .approaching:
            if stageChanged {
                commands.append(.schedule(LocalNotification(identifier: alightID, title: "準備下車", body: state.detail), after: 1))
            }
        case .arrived:
            if stageChanged { commands.append(.cancel(allIDs)) }
        case .boardingSide:
            break
        }
        return commands
    }

    private static func isTurn(_ maneuver: Maneuver) -> Bool {
        switch maneuver {
        case .turnLeft, .turnRight, .slightLeft, .slightRight, .uTurn, .crossStreet: true
        default: false
        }
    }
}
