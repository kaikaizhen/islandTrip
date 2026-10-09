import Foundation

/// 導航階段。上車、下車都由使用者手動確認（計畫 4.3）。
/// 重新規劃步行路線以 `.rerouted` 事件處理（回到該段第一步）；paused / error 待即時資料（Phase 3）時加入。
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
    /// 走錯路後重新規劃步行路線，帶入新路線的步驟數。
    case rerouted(walkSteps: Int)
    case cancel
}

/// 導航狀態轉移。純邏輯；不合法的事件會被忽略並回傳 false。
struct NavigationStateMachine: Sendable {
    private(set) var phase: NavigationPhase = .idle
    private var walkToStopSteps: Int
    private var walkToDestinationSteps: Int
    /// false 為純步行（步行測試）：走完就到達，不經過搭車階段。
    private let hasTransit: Bool

    init(walkToStopSteps: Int, walkToDestinationSteps: Int, hasTransit: Bool = true) {
        self.walkToStopSteps = walkToStopSteps
        self.walkToDestinationSteps = walkToDestinationSteps
        self.hasTransit = hasTransit
    }

    @discardableResult
    mutating func handle(_ event: NavigationEvent) -> Bool {
        guard let next = nextPhase(for: event) else { return false }
        switch (event, phase) {
        case (.boarded(let steps), _):
            walkToDestinationSteps = steps
        case (.rerouted(let steps), .walkingToStop):
            walkToStopSteps = steps
        case (.rerouted(let steps), .walkingToDestination):
            walkToDestinationSteps = steps
        default:
            break
        }
        phase = next
        return true
    }

    private func nextPhase(for event: NavigationEvent) -> NavigationPhase? {
        switch (phase, event) {
        case (.idle, .start):
            walkToStopSteps > 0 ? .walkingToStop(step: 0) : (hasTransit ? .checkingBoardingSide : .arrived)
        case (.idle, _):
            nil
        case (_, .cancel):
            .idle

        case (.walkingToStop(let step), .nextStep):
            step + 1 < walkToStopSteps ? .walkingToStop(step: step + 1) : (hasTransit ? .checkingBoardingSide : .arrived)
        case (.walkingToStop(let step), .previousStep):
            step > 0 ? .walkingToStop(step: step - 1) : nil
        case (.walkingToStop, .rerouted(let steps)):
            steps > 0 ? .walkingToStop(step: 0) : nil

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
        case (.walkingToDestination, .rerouted(let steps)):
            steps > 0 ? .walkingToDestination(step: 0) : nil

        default:
            nil
        }
    }
}
