import Foundation

/// 導航階段。第一版上車、下車都由使用者手動確認。
/// 計畫中的 rerouting / paused / error 會在 Phase 2–3 有 GPS 與即時資料後加入。
enum NavigationPhase: Hashable, Sendable {
    case idle
    case walkingToStop(step: Int)
    /// 到站前確認正確上車側。
    case checkingBoardingSide
    case waitingAtStop
    case onVehicle(approachingAlight: Bool)
    case walkingToDestination(step: Int)
    case arrived
}

enum NavigationEvent: Hashable, Sendable {
    case start
    case nextStep
    case previousStep
    case confirmedBoardingSide
    /// 上車後的步行步驟數可能因改搭別班而不同，由事件帶入。
    case boarded(walkToDestinationSteps: Int)
    case approachingAlightStop
    case alighted
    case cancel
}

/// 導航狀態轉移。純邏輯；不合法的事件會被忽略並回傳 false。
struct NavigationStateMachine: Sendable {
    private(set) var phase: NavigationPhase = .idle
    private let walkToStopSteps: Int
    private var walkToDestinationSteps: Int

    init(walkToStopSteps: Int, walkToDestinationSteps: Int) {
        self.walkToStopSteps = walkToStopSteps
        self.walkToDestinationSteps = walkToDestinationSteps
    }

    @discardableResult
    mutating func handle(_ event: NavigationEvent) -> Bool {
        guard let next = nextPhase(for: event) else { return false }
        if case .boarded(let steps) = event { walkToDestinationSteps = steps }
        phase = next
        return true
    }

    private func nextPhase(for event: NavigationEvent) -> NavigationPhase? {
        switch (phase, event) {
        case (.idle, .start):
            walkToStopSteps > 0 ? .walkingToStop(step: 0) : .checkingBoardingSide
        case (.idle, _):
            nil
        case (_, .cancel):
            .idle

        case (.walkingToStop(let step), .nextStep):
            step + 1 < walkToStopSteps ? .walkingToStop(step: step + 1) : .checkingBoardingSide
        case (.walkingToStop(let step), .previousStep):
            step > 0 ? .walkingToStop(step: step - 1) : nil

        case (.checkingBoardingSide, .previousStep):
            walkToStopSteps > 0 ? .walkingToStop(step: walkToStopSteps - 1) : nil
        case (.checkingBoardingSide, .confirmedBoardingSide):
            .waitingAtStop

        case (.waitingAtStop, .boarded):
            .onVehicle(approachingAlight: false)

        case (.onVehicle(approachingAlight: false), .approachingAlightStop):
            .onVehicle(approachingAlight: true)
        case (.onVehicle, .alighted):
            walkToDestinationSteps > 0 ? .walkingToDestination(step: 0) : .arrived

        case (.walkingToDestination(let step), .nextStep):
            step + 1 < walkToDestinationSteps ? .walkingToDestination(step: step + 1) : .arrived
        case (.walkingToDestination(let step), .previousStep):
            step > 0 ? .walkingToDestination(step: step - 1) : nil

        default:
            nil
        }
    }
}
