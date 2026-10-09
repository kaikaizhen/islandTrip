import Foundation
import Observation

/// 一趟導航：步行到站 → 確認上車側 → 候車 → 搭車 → 下車步行 → 到達。
/// 上車、下車都由使用者手動確認（計畫 4.3）；步行段有 GPS 時自動推進，也可手動。
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

    /// 步行段的 GPS 進度；模擬步行段（沒有路徑）時為 nil。
    private(set) var tracker: WalkProgressTracker?
    private(set) var isRerouting = false
    /// 定位權限被拒或定位失敗時的說明。
    private(set) var locationProblem: String?
    private var lastSample: LocationSample?
    private var locationTask: Task<Void, Never>?

    private var candidates: [Journey]
    private let transport: any TransportProvider
    private let ranking: TransitRankingService
    private let locationUpdates: (@Sendable () -> AsyncThrowingStream<LocationSample, Error>)?
    private let walkPlanner: (any JourneyWalkPlanning)?
    private let now: () -> Date

    init(
        journey: Journey,
        alternatives: [Journey],
        transport: any TransportProvider,
        ranking: TransitRankingService = TransitRankingService(),
        locationUpdates: (@Sendable () -> AsyncThrowingStream<LocationSample, Error>)? = nil,
        walkPlanner: (any JourneyWalkPlanning)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.journey = journey
        self.candidates = alternatives.contains { $0.id == journey.id } ? alternatives : [journey] + alternatives
        self.selectedWaitingID = journey.id
        self.transport = transport
        self.ranking = ranking
        self.locationUpdates = locationUpdates
        self.walkPlanner = walkPlanner
        self.now = now
        self.machine = NavigationStateMachine(
            walkToStopSteps: journey.walkToStop?.instructions.count ?? 0,
            walkToDestinationSteps: journey.walkToDestination?.instructions.count ?? 0,
            hasTransit: journey.busLeg != nil
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
                ?? "抵達 \(journey.destination.name)"
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
        case .walkingToStop(let step) where Self.isLast(step, of: journey.walkToStop): journey.isWalkOnly ? "我到了" : "我到站牌了"
        case .walkingToStop: "下一步"
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
        syncTracker()
        startLocationUpdates()
        await loadStopDetails()
    }

    func nextStep() {
        machine.handle(.nextStep)
        syncTracker()
    }

    func previousStep() {
        machine.handle(.previousStep)
        syncTracker()
    }

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
        syncTracker()
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

    func alighted() {
        machine.handle(.alighted)
        syncTracker()
    }

    func cancel() {
        machine.handle(.cancel)
        syncTracker()
    }

    // MARK: GPS

    /// 有 GPS 而且這一步有真實路徑時，才自動推進。
    var isTrackingGPS: Bool { locationUpdates != nil && tracker?.isTrackable == true && locationProblem == nil }
    var liveRemainingMeters: Int? { isTrackingGPS ? tracker?.remainingMeters : nil }
    var isOffRoute: Bool { isTrackingGPS && tracker?.isOffRoute == true }
    var isLowAccuracy: Bool { isTrackingGPS && tracker?.isLowAccuracy == true }
    var canReroute: Bool { walkPlanner != nil && lastSample != nil && !isRerouting }

    /// 走錯路：從目前位置重新規劃這一段步行，從第一步開始。
    func reroute() async {
        guard let walkPlanner, let sample = lastSample, let target = walkingTarget else { return }
        isRerouting = true
        defer { isRerouting = false }
        let toStop = { if case .walkingToStop = phase { true } else { false } }()
        let leg = await walkPlanner.walkLeg(from: sample.coordinate, to: target.coordinate, name: target.name)
        journey = journey.replacingWalkLeg(toStop: toStop, with: leg)
        machine.handle(.rerouted(walkSteps: leg.instructions.count))
        tracker = nil  // 新路線：重新建立進度判斷
        syncTracker()
    }

    /// 重新定位：依目前位置找出應該在哪一步（只往前，不往回）。
    func relocate() {
        guard let sample = lastSample, var tracker, let current = currentStepIndex else { return }
        tracker.relocate(to: sample)
        for _ in current..<max(current, tracker.step) { machine.handle(.nextStep) }
        syncTracker()
    }

    private var currentStepIndex: Int? {
        switch phase {
        case .walkingToStop(let step), .walkingToDestination(let step): step
        default: nil
        }
    }

    private var currentWalkLeg: WalkLeg? {
        switch phase {
        case .walkingToStop: journey.walkToStop
        case .walkingToDestination: journey.walkToDestination
        default: nil
        }
    }

    /// 目前步行段要走到哪裡。
    private var walkingTarget: (name: String, coordinate: Coordinate)? {
        switch phase {
        case .walkingToStop:
            if let bus { return (bus.boardingStop.name, bus.boardingStop.coordinate) }
            return (journey.destination.name, journey.destination.coordinate)
        case .walkingToDestination:
            return (journey.destination.name, journey.destination.coordinate)
        default:
            return nil
        }
    }

    /// 依目前階段準備（或清除）步行進度判斷；行程結束時停止定位。
    private func syncTracker() {
        if let leg = currentWalkLeg, let step = currentStepIndex {
            if tracker == nil || tracker?.step != step || leg.instructions.count != trackedInstructionCount {
                tracker = WalkProgressTracker(instructions: leg.instructions, step: step)
                trackedInstructionCount = leg.instructions.count
            }
        } else {
            tracker = nil
        }
        if phase == .idle || phase == .arrived {
            locationTask?.cancel()
            locationTask = nil
        }
    }

    private var trackedInstructionCount = 0

    private func startLocationUpdates() {
        guard let locationUpdates, locationTask == nil else { return }
        locationTask = Task { [weak self] in
            do {
                for try await sample in locationUpdates() {
                    guard let self else { return }
                    self.handle(sample)
                }
            } catch LocationError.denied {
                self?.locationProblem = "定位權限沒有開啟，請依指示走並手動按「下一步」。"
            } catch {
                self?.locationProblem = "暫時無法定位，請依指示走並手動按「下一步」。"
            }
        }
    }

    private func handle(_ sample: LocationSample) {
        lastSample = sample
        guard var tracker else { return }
        let event = tracker.process(sample)
        self.tracker = tracker
        switch event {
        case .advanced, .completed:
            machine.handle(.nextStep)
            syncTracker()
        case .wentOffRoute, .backOnRoute, nil:
            break
        }
    }

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
