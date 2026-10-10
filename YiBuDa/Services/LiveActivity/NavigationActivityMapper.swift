import Foundation

/// 把導航狀態換成 Live Activity 內容（決策 D4 的各階段呈現）。
/// 直達公車與轉乘導航共用；`updatedAt` 由呼叫端決定，比較是否需要更新時要忽略它。
enum NavigationActivityMapper {
    typealias State = NavigationActivityAttributes.ContentState

    // MARK: 直達公車

    @MainActor
    static func state(for viewModel: NavigationSessionViewModel, now: Date) -> State? {
        let destination = viewModel.journey.destination.name
        switch viewModel.phase {
        case .idle:
            return nil
        case .walkingToStop, .walkingToDestination:
            guard let instruction = viewModel.currentInstruction else { return nil }
            return walking(instruction, remaining: viewModel.liveRemainingMeters, next: viewModel.nextStepText, now: now)
        case .checkingBoardingSide:
            guard let bus = viewModel.bus else { return nil }
            return boardingSide(route: bus.option.routeName, stop: bus.boardingStop, resolution: viewModel.boardingResolution, now: now)
        case .waitingAtStop:
            guard let bus = viewModel.bus else { return nil }
            let selected = viewModel.waitingOptions.first { $0.id == viewModel.selectedWaitingID }?.option ?? bus.option
            return waiting(route: selected.routeName, stopName: bus.boardingStop.name, direction: selected.direction,
                           arrivalAt: selected.estimatedArrivalAtStop, isScheduled: false,
                           alightName: bus.alightingStop.name, now: now)
        case .onVehicle(let approaching):
            guard let bus = viewModel.bus else { return nil }
            return riding(route: bus.option.routeName, alightName: bus.alightingStop.name, approaching: approaching,
                          remainingStops: viewModel.remainingStops, alightAt: viewModel.expectedAlightAt, now: now)
        case .arrived:
            return arrived(destination, now: now)
        }
    }

    // MARK: 轉乘導航

    @MainActor
    static func state(for viewModel: PlanNavigationViewModel, now: Date) -> State? {
        switch viewModel.stage {
        case .walk:
            guard let instruction = viewModel.flow.currentInstruction else { return nil }
            return walking(instruction, remaining: viewModel.liveRemainingMeters, next: viewModel.nextStepText, now: now)
        case .stationWalk(_, let to, _):
            let target = to.flatMap { $0.isEmpty ? nil : $0 } ?? "月台"
            return State(maneuver: .straight, title: "在站內走到 \(target)", detail: "跟著站內指標走", distanceMeters: nil,
                         nextStep: viewModel.flow.upcomingTransit.map { "搭 \(PlanFormat.lineTitle($0))" },
                         updatedAt: now, stage: .walking, shortTitle: "站內步行")
        case .boardingSide:
            guard let target = viewModel.boardingTarget else { return nil }
            return boardingSide(route: target.routeName, stop: target.stop, resolution: viewModel.boardingResolution, now: now)
        case .waiting:
            guard let leg = viewModel.currentTransit else { return nil }
            let live = leg.realtime?.arrivalAt
            return waiting(route: leg.line, stopName: PlanFormat.place(leg.from, fallback: "車站"),
                           direction: PlanFormat.headsign(leg) ?? "", arrivalAt: live ?? leg.departAt,
                           isScheduled: live == nil, alightName: PlanFormat.place(leg.to, fallback: "下車站"), now: now)
        case .riding:
            guard let leg = viewModel.currentTransit else { return nil }
            let status = viewModel.alightStatus
            return riding(route: leg.line, alightName: PlanFormat.place(leg.to, fallback: "下車站"),
                          approaching: status.isApproaching,
                          remainingStops: status.source == .gps ? status.remainingStops : nil, alightAt: leg.arriveAt, now: now)
        case .arrived:
            return arrived(viewModel.destination.name, now: now)
        }
    }

    // MARK: 各階段

    static func walking(_ instruction: NavigationInstruction, remaining: Int?, next: String?, now: Date) -> State {
        let meters = (remaining ?? instruction.distanceMeters).map { max(0, ($0 + 5) / 10 * 10) }
        return State(
            maneuver: instruction.kind, title: instruction.displayText,
            detail: remaining.map { "還有 \(WalkInstructionBuilder.spoken($0))" } ?? instruction.detailText ?? "",
            distanceMeters: meters, nextStep: next, updatedAt: now, stage: .walking,
            shortTitle: instruction.kind.accessibilityDescription
        )
    }

    static func boardingSide(route: String, stop: Stop, resolution: BoardingSideResolution, now: Date) -> State {
        let short = TransitFormat.shortRouteName(route)
        let (title, shortTitle): (String, String) = switch resolution {
        case .known(needsToCross: true, _): ("請到對面站牌搭車", "對面搭車")
        case .known(needsToCross: false, _): ("就在這一側搭車", "這側搭車")
        default: ("確認站牌方向", "確認站牌")
        }
        return State(maneuver: .crossStreet, title: title, detail: "\(stop.name)・\(stop.directionDescription)",
                     distanceMeters: nil, nextStep: "搭 \(short)", updatedAt: now, stage: .boardingSide,
                     routeName: short, shortTitle: shortTitle)
    }

    static func waiting(route: String, stopName: String, direction: String, arrivalAt: Date?, isScheduled: Bool,
                        alightName: String, now: Date) -> State {
        let short = TransitFormat.shortRouteName(route)
        return State(maneuver: .board, title: "等 \(short)", detail: "在 \(stopName) \(direction)".trimmingCharacters(in: .whitespaces),
                     distanceMeters: nil, nextStep: "在 \(alightName) 下車", updatedAt: now, stage: .waiting,
                     routeName: short, arrivalAt: arrivalAt,
                     arrivalMinutes: arrivalAt.map { max(0, Int(($0.timeIntervalSince(now) / 60).rounded(.up))) },
                     arrivalIsScheduled: isScheduled, action: .board,
                     shortTitle: fitsWatch(short) ? "等\(short)" : "候車")
    }

    /// - Parameter alightAt: 預計（表定或估計）到下車站的時間；用來預排「準備下車」通知。
    static func riding(route: String, alightName: String, approaching: Bool, remainingStops: Int?, alightAt: Date?, now: Date) -> State {
        let short = TransitFormat.shortRouteName(route)
        if approaching {
            return State(maneuver: .alight, title: "準備下車", detail: "下一站：\(alightName)", distanceMeters: nil,
                         nextStep: nil, updatedAt: now, stage: .approaching, routeName: short, arrivalAt: alightAt,
                         action: .alight, shortTitle: "準備下車")
        }
        return State(maneuver: .board, title: "搭乘 \(short)", detail: "在 \(alightName) 下車", distanceMeters: nil,
                     nextStep: nil, updatedAt: now, stage: .riding, routeName: short, arrivalAt: alightAt,
                     arrivalIsScheduled: true, remainingStops: remainingStops, action: .alight,
                     shortTitle: fitsWatch(short) ? "搭\(short)" : "搭乘中")
    }

    /// 40mm 手錶標題寬度有限（約 120pt）：路線名超過 4 個字就不放進短標題。
    static let watchRouteLimit = 4
    static func fitsWatch(_ route: String) -> Bool { route.count <= watchRouteLimit }

    static func arrived(_ destination: String, now: Date) -> State {
        State(maneuver: .arrive, title: "已抵達", detail: destination, distanceMeters: nil, nextStep: nil,
              updatedAt: now, stage: .arrived, shortTitle: "已抵達")
    }
}

extension NavigationActivityAttributes.ContentState {
    /// 除了更新時間以外是否相同（相同就不必更新 Live Activity）。
    func sameContent(as other: Self) -> Bool {
        var lhs = self
        lhs.updatedAt = other.updatedAt
        return lhs == other
    }
}
