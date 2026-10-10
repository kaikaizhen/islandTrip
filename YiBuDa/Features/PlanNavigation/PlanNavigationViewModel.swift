import Foundation
import Observation

/// 轉乘導航（決策 D9）：依方案逐段帶路——步行、站內步行、確認上車側（公車）、候車、搭乘、到達。
/// 上車、下車都由使用者手動確認；步行段有 GPS 時自動推進，搭乘中以 GPS 或表定時間提醒下車。
@MainActor
@Observable
final class PlanNavigationViewModel {
    private(set) var plan: TransitPlan
    let origin: Place
    let destination: Place
    private(set) var flow: PlanNavigationFlow
    private(set) var isFinished = false
    private(set) var isReplanning = false
    /// 重新規劃的結果說明（成功改走哪條、或失敗原因）。
    private(set) var replanMessage: String?

    // 步行
    private(set) var tracker: WalkProgressTracker?
    private(set) var isRerouting = false
    private(set) var locationProblem: String?
    private(set) var walkingSide: WalkSide?
    private(set) var directionGuidance: DirectionCheck.Guidance?
    private var directionCheck = DirectionCheck()
    private var directionKey: String?

    // 上車側（公車段）
    private(set) var boardingAnswer: BoardingSideAnswer?
    private(set) var gpsBoardingEstimate: BoardingSideEstimator.Estimate?
    private var lastBoardingEstimate: BoardingSideEstimator.Estimate?
    private var boardingStabilizer = SideEstimateStabilizer()

    // 候車
    /// 候車時更新過的公車即時到站（依搭乘段索引）。
    private(set) var liveRealtime: [Int: LegRealtime] = [:]
    /// 候車時更新過的捷運、臺鐵即時預估；值為 nil 代表找不到同一班車，改回表定。
    private(set) var liveRail: [Int: RailLegRealtime?] = [:]
    private(set) var notice: String?

    // 搭乘
    private(set) var alightStatus = AlightReminder.Status(isApproaching: false, source: nil, remainingStops: nil)
    /// 每次進入「快到站」就加一，畫面依此震動提醒。
    private(set) var alertCount = 0

    private var lastSample: LocationSample?
    private var locationTask: Task<Void, Never>?
    private var headingTask: Task<Void, Never>?
    private var planningTask: Task<Void, Never>?

    private let planner: any TransitPlanning
    private let locationUpdates: (@Sendable () -> AsyncThrowingStream<LocationSample, Error>)?
    private let walkPlanner: (any JourneyWalkPlanning)?
    private let headingUpdates: (@MainActor () -> AsyncStream<HeadingSample>)?
    private let reminder: AlightReminder
    /// 步行速度倍數（設定「慢慢走」）：轉乘時間檢查用。
    private let paceFactor: Double
    private let now: () -> Date

    init(
        plan: TransitPlan,
        origin: Place,
        destination: Place,
        planner: any TransitPlanning,
        locationUpdates: (@Sendable () -> AsyncThrowingStream<LocationSample, Error>)? = nil,
        walkPlanner: (any JourneyWalkPlanning)? = nil,
        headingUpdates: (@MainActor () -> AsyncStream<HeadingSample>)? = nil,
        reminder: AlightReminder = AlightReminder(),
        paceFactor: Double = 1.0,
        now: @escaping () -> Date = Date.init
    ) {
        self.plan = plan
        self.origin = origin
        self.destination = destination
        self.planner = planner
        self.locationUpdates = locationUpdates
        self.walkPlanner = walkPlanner
        self.headingUpdates = headingUpdates
        self.reminder = reminder
        self.now = now
        self.paceFactor = paceFactor
        self.flow = PlanNavigationFlow(plan: plan, destinationName: destination.name) { walk, name in
            WalkingJourneyPlanner.estimatedLeg(from: walk.from.coordinate, to: walk.to.coordinate, name: name, speed: 1.0 / paceFactor)
        }
    }

    var stage: PlanStage { flow.stage }
    var currentTime: Date { now() }

    /// 目前（或即將）搭乘的段落，含候車時更新過的即時到站。
    var currentTransit: TransitLeg? {
        guard let index = flow.transitIndex, var leg = flow.transit(at: index) else { return nil }
        if let live = liveRealtime[index] { leg.realtime = live }
        if let rail = liveRail[index] { leg.railRealtime = rail }
        return leg
    }

    // MARK: 轉乘來不及（Phase 5）

    /// 目前這段或下一個轉乘可能來不及；只在候車、搭乘時判斷。
    var transferWarning: TransferWarning? {
        guard let index = flow.transitIndex, let leg = currentTransit else { return nil }
        switch stage {
        case .waiting, .riding:
            return TransferCheck.evaluate(plan: plan, transitIndex: index, currentLeg: leg, isRiding: stage == .riding(transitIndex: index),
                                          now: now(), paceFactor: paceFactor)
        default:
            return nil
        }
    }

    /// 已上車時不重新規劃（人在車上，從這裡規劃會叫人下車步行）；下車後再規劃。
    var canReplan: Bool {
        guard !isReplanning, stage != .arrived else { return false }
        if case .riding = stage { return false }
        return true
    }

    /// 從目前位置重新規劃到目的地，改走最早抵達的方案，從第一步開始。
    func replan() async {
        guard canReplan else { return }
        isReplanning = true
        defer { isReplanning = false }
        let here = lastSample.map { Place(id: "replan", name: "目前位置", coordinate: $0.coordinate) }
            ?? currentTransit.map { Place(id: "replan", name: PlanFormat.place($0.from, fallback: "目前位置"), coordinate: $0.from.coordinate) }
            ?? origin
        do {
            let plans = try await planner.plans(from: here, to: destination).filter { !$0.transitLegs.isEmpty }
            guard let best = TransitPlansViewModel.sorted(plans, by: .fastest).first else {
                replanMessage = "找不到其他方案，請依現場指示或詢問站務人員。"
                return
            }
            plan = best
            flow = PlanNavigationFlow(plan: best, destinationName: destination.name) { [paceFactor] walk, name in
                WalkingJourneyPlanner.estimatedLeg(from: walk.from.coordinate, to: walk.to.coordinate, name: name, speed: 1.0 / paceFactor)
            }
            liveRealtime = [:]
            liveRail = [:]
            tracker = nil
            walkingSide = nil
            alightStatus = AlightReminder.Status(isApproaching: false, source: nil, remainingStops: nil)
            replanMessage = "已改走新路線：" + best.transitLegs.map(PlanFormat.lineTitle).joined(separator: " → ")
            syncStage()
            planWalkingRoutes()
        } catch {
            replanMessage = "暫時無法重新規劃，請稍後再試。"
        }
    }

    // MARK: 開始／結束

    func start() async {
        startLocationUpdates()
        syncStage()
        planWalkingRoutes()
    }

    func cancel() {
        isFinished = true
        locationTask?.cancel()
        headingTask?.cancel()
        planningTask?.cancel()
        locationTask = nil
        headingTask = nil
        planningTask = nil
    }

    /// 戶外步行段：在背景向 Apple 地圖要路線，拿到就換掉直線估計。
    private func planWalkingRoutes() {
        guard let walkPlanner else { return }
        let targets = flow.stages.indices.compactMap { index -> (Int, WalkPlanLeg, String)? in
            guard case .walk(let leg) = flow.stages[index], let walk = flow.walkEndpoints(at: index) else { return nil }
            return (index, walk, leg.destinationName)
        }
        planningTask?.cancel()  // 重新規劃後，舊路線的步行規劃不要再寫回來
        planningTask = Task { [weak self] in
            for (index, walk, name) in targets {
                let leg = await walkPlanner.walkLeg(from: walk.from.coordinate, to: walk.to.coordinate, name: name)
                if Task.isCancelled { return }
                guard let self, !leg.isEstimated else { continue }
                // 正在走而且已經往前走了幾步，就不換（避免步驟跳回第一步）。
                if self.flow.index == index, self.flow.walkStep > 0 { continue }
                if self.flow.index > index { continue }
                self.flow.replaceWalk(at: index, with: leg)
                if self.flow.index == index { self.tracker = nil }
                self.syncStage()
            }
        }
    }

    // MARK: 前進／後退

    var canGoBack: Bool { flow.canGoBack }

    func next() {
        if let kind = flow.currentInstruction?.kind {
            walkingSide = TurnSideAdvice.sideAfterTurning(kind, previous: walkingSide)
        }
        let leaving = flow.stage
        flow.next()
        if case .riding = leaving {
            walkingSide = nil  // 下車後重新確認在哪一邊
            alightStatus = AlightReminder.Status(isApproaching: false, source: nil, remainingStops: nil)
        }
        if flow.currentWalk != nil, flow.walkStep == 0 { walkingSide = nil }
        syncStage()
    }

    func previous() {
        flow.previous()
        walkingSide = nil
        syncStage()
    }

    /// 進入新階段時的準備：步行進度、上車側、候車更新、搭乘提醒。
    private func syncStage() {
        if let walk = flow.currentWalk {
            if tracker == nil || tracker?.step != flow.walkStep || trackedKey != walkKey(walk) {
                tracker = WalkProgressTracker(instructions: walk.instructions, step: flow.walkStep)
                trackedKey = walkKey(walk)
            }
        } else {
            tracker = nil
            trackedKey = nil
        }
        switch stage {
        case .boardingSide:
            break
        case .riding:
            updateAlightStatus()
        case .arrived:
            locationTask?.cancel()
            locationTask = nil
        default:
            boardingAnswer = nil
            gpsBoardingEstimate = nil
            lastBoardingEstimate = nil
            boardingStabilizer = SideEstimateStabilizer()
        }
        syncDirectionCheck()
    }

    private var trackedKey: String?
    private func walkKey(_ walk: WalkLeg) -> String {
        "\(flow.index)|\(walk.instructions.map(\.id).joined(separator: ","))"
    }

    // MARK: 步行

    var stepProgress: String? {
        guard let walk = flow.currentWalk else { return nil }
        return "第 \(flow.walkStep + 1) 步，共 \(walk.instructions.count) 步"
    }

    var nextStepText: String? {
        guard let walk = flow.currentWalk else { return nil }
        if let next = walk.instructions[safe: flow.walkStep + 1] { return next.displayText }
        if let transit = flow.upcomingTransit, flow.stages[safe: flow.index + 1] != .arrived {
            return "到 \(PlanFormat.place(transit.from, fallback: "車站")) 搭 \(PlanFormat.lineTitle(transit))"
        }
        return "抵達 \(destination.name)"
    }

    var walkingPrimaryTitle: String {
        guard let walk = flow.currentWalk else { return "下一步" }
        guard flow.walkStep + 1 >= walk.instructions.count else { return "下一步" }
        return flow.stages[safe: flow.index + 1] == .arrived ? "我到了" : "我到了，下一步"
    }

    var isTrackingGPS: Bool { locationUpdates != nil && tracker?.isTrackable == true && locationProblem == nil }
    var liveRemainingMeters: Int? { isTrackingGPS ? tracker?.remainingMeters : nil }
    var isOffRoute: Bool { isTrackingGPS && tracker?.isOffRoute == true }
    var isLowAccuracy: Bool { isTrackingGPS && tracker?.isLowAccuracy == true }
    var canReroute: Bool { walkPlanner != nil && lastSample != nil && !isRerouting && flow.currentWalk != nil }

    var turnAdvice: TurnSideAdvice {
        guard let kind = flow.currentInstruction?.kind else { return .none }
        return TurnSideAdvice.advice(for: kind, userSide: walkingSide)
    }

    func setWalkingSide(_ side: WalkSide?) {
        walkingSide = side
    }

    /// 走錯路：從目前位置重新規劃這一段步行。
    func reroute() async {
        guard let walkPlanner, let sample = lastSample, let walk = flow.walkEndpoints(at: flow.index),
              let name = flow.currentWalk?.destinationName else { return }
        isRerouting = true
        defer { isRerouting = false }
        let index = flow.index
        let leg = await walkPlanner.walkLeg(from: sample.coordinate, to: walk.to.coordinate, name: name)
        guard flow.index == index else { return }
        flow.replaceWalk(at: index, with: leg)
        tracker = nil
        walkingSide = nil
        syncStage()
    }

    /// 依目前位置找出應該在哪一步（只往前）。
    func relocate() {
        guard let sample = lastSample, var tracker else { return }
        tracker.relocate(to: sample)
        flow.advanceWalk(to: tracker.step)
        self.tracker = nil
        syncStage()
    }

    // MARK: 上車側

    var boardingTarget: BoardingTarget? {
        guard case .boardingSide = stage, let transit = currentTransit, let stop = transit.realtime?.boardingStop else { return nil }
        return BoardingTarget(routeName: transit.line, direction: PlanFormat.headsign(transit) ?? "請看站牌上的方向", stop: stop)
    }

    var boardingDetails: StopDetails? {
        guard let target = boardingTarget else { return nil }
        return StopDetails(stop: target.stop, oppositeStop: currentTransit?.realtime?.oppositeStop, side: .unknown)
    }

    var boardingResolution: BoardingSideResolution {
        BoardingSideResolver.resolve(answer: boardingAnswer, gpsEstimate: gpsBoardingEstimate,
                                     gpsAccuracy: lastSample?.horizontalAccuracy, stopSide: nil,
                                     lastEstimate: lastBoardingEstimate)
    }

    func answerBoardingSide(_ answer: BoardingSideAnswer?) {
        boardingAnswer = answer
    }

    private func updateBoardingEstimate(with sample: LocationSample) {
        guard let target = boardingTarget, let opposite = boardingDetails?.oppositeStop else { return }
        let estimate = BoardingSideEstimator.estimate(user: sample, correctStop: target.stop, oppositeStop: opposite)
        lastBoardingEstimate = estimate
        if let stable = boardingStabilizer.add(estimate) { gpsBoardingEstimate = stable }
    }

    // MARK: 候車

    /// 有即時資料（公車到站、捷運臺鐵看板）時更新倒數；只有表定的段落不更新。
    func refreshArrival() async {
        guard case .waiting(let index) = stage, let leg = currentTransit else { return }
        do {
            if let realtime = leg.realtime {
                liveRealtime[index] = try await planner.refreshed(realtime)
            } else if let rail = leg.railRealtime {
                liveRail[index] = .some(try await planner.refreshedRail(rail))
            } else if leg.mode == .tra || leg.mode == .metro {
                // 規劃時是表定：看看車站即時看板上出現這班車了沒。
                if let found = try await planner.discoverRail(for: leg, now: now()) { liveRail[index] = .some(found) }
            } else {
                return
            }
            notice = nil
        } catch {
            notice = "無法更新到站時間，顯示的可能是舊資料。"
        }
    }

    // MARK: 搭乘

    private func updateAlightStatus() {
        guard case .riding = stage, let leg = currentTransit else { return }
        let status = reminder.status(for: leg, sample: lastSample, now: now())
        // 一旦提醒過就維持「準備下車」，不因 GPS 飄移又取消。
        let wasApproaching = alightStatus.isApproaching
        alightStatus = AlightReminder.Status(
            isApproaching: wasApproaching || status.isApproaching,
            source: wasApproaching ? alightStatus.source : status.source,
            remainingStops: status.remainingStops
        )
        // 震動提醒；通知由 NavigationActivityCoordinator 依狀態送出。
        if !wasApproaching, alightStatus.isApproaching { alertCount += 1 }
    }

    /// 搭乘時每 30 秒用時間再判斷一次（沒有 GPS 時靠表定時間）。
    func tick() {
        updateAlightStatus()
    }

    // MARK: 定位與指南針

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
        switch stage {
        case .boardingSide:
            updateBoardingEstimate(with: sample)
        case .riding:
            updateAlightStatus()
        case .walk:
            guard var tracker else { return }
            let event = tracker.process(sample)
            self.tracker = tracker
            switch event {
            case .advanced, .completed:
                next()
            case .wentOffRoute, .backOnRoute, nil:
                break
            }
        default:
            break
        }
    }

    var directionRelativeAngle: Double? { directionCheck.relativeAngle }

    private func syncDirectionCheck() {
        let shouldRun = headingUpdates != nil && flow.currentInstruction.map { $0.path.count >= 2 } == true
        guard shouldRun else {
            headingTask?.cancel()
            headingTask = nil
            directionGuidance = nil
            directionCheck.reset()
            directionKey = nil
            return
        }
        let key = "\(flow.index)-\(flow.walkStep)"
        if directionKey != key {
            directionCheck.reset()
            directionGuidance = nil
            directionKey = key
        }
        guard headingTask == nil, let headingUpdates else { return }
        headingTask = Task { [weak self] in
            for await heading in headingUpdates() {
                guard let self, !Task.isCancelled else { return }
                self.handle(heading)
            }
        }
    }

    private func handle(_ heading: HeadingSample) {
        guard let path = flow.currentInstruction?.path,
              let bearing = DirectionCheck.walkBearing(along: path, from: lastSample?.coordinate) else {
            directionGuidance = nil
            return
        }
        directionGuidance = directionCheck.update(heading: heading, walkBearing: bearing)
    }
}
