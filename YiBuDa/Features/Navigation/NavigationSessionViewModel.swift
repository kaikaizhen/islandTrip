import Foundation
import Observation

/// 一趟導航：步行到站 → 確認上車側 → 候車 → 搭車 → 下車步行 → 到達。
/// 上車、下車都由使用者手動確認（計畫 4.3）。
@MainActor
@Observable
final class NavigationSessionViewModel {
    private(set) var journey: Journey
    private(set) var machine: NavigationStateMachine
    private(set) var stopDetails: StopDetails?
    /// 同站可搭的方案（含目前這班），依抵達時間排序。
    private(set) var waitingOptions: [RankedJourney] = []
    private(set) var selectedWaitingID: Journey.ID
    /// 模擬的剩餘站數；沒有可靠車上位置時為 nil，不可顯示精準站數。
    private(set) var remainingStops: Int?
    private(set) var notice: String?

    private var candidates: [Journey]
    private let transport: any TransportProvider
    private let ranking: TransitRankingService
    private let now: () -> Date

    init(
        journey: Journey,
        alternatives: [Journey],
        transport: any TransportProvider,
        ranking: TransitRankingService = TransitRankingService(),
        now: @escaping () -> Date = Date.init
    ) {
        self.journey = journey
        self.candidates = alternatives.contains { $0.id == journey.id } ? alternatives : [journey] + alternatives
        self.selectedWaitingID = journey.id
        self.transport = transport
        self.ranking = ranking
        self.now = now
        self.machine = NavigationStateMachine(
            walkToStopSteps: journey.walkToStop?.instructions.count ?? 0,
            walkToDestinationSteps: journey.walkToDestination?.instructions.count ?? 0
        )
    }

    var phase: NavigationPhase { machine.phase }
    var isFinished: Bool { machine.phase == .idle }
    var bus: BusLeg? { journey.busLeg }
    var currentTime: Date { now() }

    // MARK: 步行

    var currentInstruction: NavigationInstruction? {
        switch phase {
        case .walkingToStop(let step): journey.walkToStop?.instructions[safe: step]
        case .walkingToDestination(let step): journey.walkToDestination?.instructions[safe: step]
        default: nil
        }
    }

    /// 例：「第 2 步，共 3 步」
    var stepProgress: String? {
        switch phase {
        case .walkingToStop(let step): "第 \(step + 1) 步，共 \(journey.walkToStop?.instructions.count ?? 0) 步"
        case .walkingToDestination(let step): "第 \(step + 1) 步，共 \(journey.walkToDestination?.instructions.count ?? 0) 步"
        default: nil
        }
    }

    var nextStepText: String? {
        switch phase {
        case .walkingToStop(let step):
            if let next = journey.walkToStop?.instructions[safe: step + 1] { return next.displayText }
            return bus.map { "確認在 \($0.boardingStop.name) 正確的一側搭 \($0.option.routeName)" }
        case .walkingToDestination(let step):
            return journey.walkToDestination?.instructions[safe: step + 1]?.displayText ?? "抵達 \(journey.destination.name)"
        default:
            return nil
        }
    }

    var canGoBack: Bool {
        switch phase {
        case .walkingToStop(let step), .walkingToDestination(let step): step > 0
        case .checkingBoardingSide: (journey.walkToStop?.instructions.count ?? 0) > 0
        default: false
        }
    }

    var walkingPrimaryTitle: String {
        switch phase {
        case .walkingToStop(let step): Self.isLast(step, of: journey.walkToStop) ? "我到站牌了" : "下一步"
        case .walkingToDestination(let step): Self.isLast(step, of: journey.walkToDestination) ? "我到了" : "下一步"
        default: "下一步"
        }
    }

    private static func isLast(_ step: Int, of leg: WalkLeg?) -> Bool {
        step + 1 >= (leg?.instructions.count ?? 0)
    }

    // MARK: 動作

    func start() async {
        machine.handle(.start)
        await loadStopDetails()
    }

    func nextStep() { machine.handle(.nextStep) }
    func previousStep() { machine.handle(.previousStep) }

    func confirmBoardingSide() async {
        guard machine.handle(.confirmedBoardingSide) else { return }
        await refreshArrivals()
    }

    func selectWaitingOption(_ option: RankedJourney) {
        selectedWaitingID = option.id
    }

    /// 我已上車：以候車畫面選的那班為準（可能改搭同站的其他路線）。
    func board() {
        let chosen = candidates.first { $0.id == selectedWaitingID } ?? journey
        guard machine.handle(.boarded(walkToDestinationSteps: chosen.walkToDestination?.instructions.count ?? 0)) else { return }
        journey = chosen
        remainingStops = chosen.busLeg.flatMap { $0.pattern.stopCount(from: $0.option.boardingStopUID, to: $0.option.alightingStopUID) }
        notice = nil
        if let remainingStops, remainingStops <= 1 { machine.handle(.approachingAlightStop) }
    }

    /// 模擬車子往前一站。真實資料（Phase 3–4）只有在站序可信時才會提供。
    func simulateNextStop() {
        guard case .onVehicle = phase, let remaining = remainingStops, remaining > 1 else { return }
        remainingStops = remaining - 1
        if remaining - 1 <= 1 { machine.handle(.approachingAlightStop) }
    }

    func alighted() { machine.handle(.alighted) }

    func cancel() { machine.handle(.cancel) }

    func refreshArrivals() async {
        guard let stopUID = bus?.option.boardingStopUID else { return }
        do {
            let arrivals = try await transport.getArrivals(stopUID: stopUID)
            let byPattern = Dictionary(arrivals.map { ($0.patternId, $0) }, uniquingKeysWith: { first, _ in first })
            candidates = candidates.map { candidate in
                guard let option = candidate.busLeg?.option, let arrival = byPattern[option.patternId] else { return candidate }
                return candidate.replacingBusOption(option.updating(with: arrival))
            }
            notice = nil
        } catch {
            notice = "無法更新到站時間，顯示的可能是舊資料。"
        }
        rerankWaitingOptions()
    }

    func rerankWaitingOptions() {
        let stopUID = bus?.option.boardingStopUID
        waitingOptions = ranking.rank(candidates, now: now(), userAtBoardingStop: true)
            .filter { $0.option?.boardingStopUID == stopUID }
    }

    private func loadStopDetails() async {
        guard let stopUID = bus?.option.boardingStopUID else { return }
        stopDetails = try? await transport.getStopDetails(stopUID: stopUID)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
