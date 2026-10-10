import Foundation

/// 轉乘導航的一個階段。依方案的段落依序排列；上車、下車都由使用者手動確認（計畫 4.3）。
enum PlanStage: Hashable, Sendable {
    /// 戶外步行：用 Apple 地圖步行指引（取得前先用直線估計）。
    case walk(WalkLeg)
    /// 車站內步行（入口→月台、月台→出口、站內轉乘）：跟著站內指標走，不做 GPS 推進。
    case stationWalk(from: String?, to: String?, seconds: Int)
    /// 公車段：確認站牌在馬路哪一側（只有對得上 TDX 站牌的公車段才有）。
    case boardingSide(transitIndex: Int)
    case waiting(transitIndex: Int)
    case riding(transitIndex: Int)
    case arrived
}

/// 轉乘導航的階段推進。純邏輯，不合法的操作回傳 false。
struct PlanNavigationFlow: Sendable {
    /// 走路距離與時間都很短的戶外步行段（例：下公車就是捷運入口）不另外導航。
    static let negligibleWalkMeters = 20

    let plan: TransitPlan
    private(set) var stages: [PlanStage]
    private(set) var index = 0
    /// 目前步行階段走到第幾步。
    private(set) var walkStep = 0
    /// 每個戶外步行階段對應方案中的哪一段（重新規劃時找起訖點）。
    private(set) var walkLegIndex: [Int: Int] = [:]

    init(plan: TransitPlan, destinationName: String, walkLeg: (WalkPlanLeg, String) -> WalkLeg) {
        self.plan = plan
        var stages: [PlanStage] = []
        var walkLegIndex: [Int: Int] = [:]
        var transitIndex = 0
        var legIndex = 0
        let legs = plan.legs
        while legIndex < legs.count {
            switch legs[legIndex] {
            case .walk(let walk) where walk.inStation:
                // 連續的站內步行合併成一段。
                var last = walk
                var seconds = walk.seconds
                while legIndex + 1 < legs.count, case .walk(let next) = legs[legIndex + 1], next.inStation {
                    last = next
                    seconds += next.seconds
                    legIndex += 1
                }
                stages.append(.stationWalk(from: walk.from.name, to: last.to.name, seconds: seconds))
            case .walk(let walk):
                if walk.meters >= Self.negligibleWalkMeters || walk.seconds >= 60 {
                    let isLast = legIndex == legs.count - 1
                    let name = isLast ? destinationName : PlanFormat.place(walk.to, fallback: "下一站")
                    walkLegIndex[stages.count] = legIndex
                    stages.append(.walk(walkLeg(walk, name)))
                }
            case .wait:
                break // 併入下一段搭乘的候車階段
            case .transit(let transit):
                if transit.mode == .bus, transit.realtime?.boardingStop != nil {
                    stages.append(.boardingSide(transitIndex: transitIndex))
                }
                stages.append(.waiting(transitIndex: transitIndex))
                stages.append(.riding(transitIndex: transitIndex))
                transitIndex += 1
            }
            legIndex += 1
        }
        stages.append(.arrived)
        self.stages = stages
        self.walkLegIndex = walkLegIndex
    }

    var stage: PlanStage { stages[index] }

    var currentWalk: WalkLeg? {
        if case .walk(let leg) = stage { leg } else { nil }
    }

    var currentInstruction: NavigationInstruction? {
        currentWalk?.instructions[safe: walkStep]
    }

    /// 目前或下一段搭乘（候車、搭乘、上車側都指向同一段）。
    var transitIndex: Int? {
        switch stage {
        case .boardingSide(let index), .waiting(let index), .riding(let index): index
        default: nil
        }
    }

    func transit(at index: Int) -> TransitLeg? { plan.transitLegs[safe: index] }

    /// 接下來第一段搭乘（步行時顯示「走到 ○○ 搭 ○○」用）。
    var upcomingTransit: TransitLeg? {
        for stage in stages[index...] {
            switch stage {
            case .boardingSide(let i), .waiting(let i), .riding(let i): return transit(at: i)
            default: continue
            }
        }
        return nil
    }

    /// 例：「第 2 段，共 3 段」（只算搭乘段，長輩比較好理解）。
    var transitProgress: String? {
        guard let transitIndex, plan.transitLegs.count > 1 else { return nil }
        return "第 \(transitIndex + 1) 段車，共 \(plan.transitLegs.count) 段"
    }

    var canGoBack: Bool {
        if currentWalk != nil, walkStep > 0 { return true }
        guard index > 0 else { return false }
        // 上車後不能退回候車（車已經開了），其他階段可以退回上一個。
        switch stage {
        case .riding, .arrived: return false
        default: break
        }
        if case .riding = stages[index - 1] { return false }
        return true
    }

    /// 前進：步行中先走完每一步，再進下一個階段。
    @discardableResult
    mutating func next() -> Bool {
        guard stage != .arrived else { return false }
        if let walk = currentWalk, walkStep + 1 < walk.instructions.count {
            walkStep += 1
            return true
        }
        index += 1
        walkStep = 0
        return true
    }

    @discardableResult
    mutating func previous() -> Bool {
        guard canGoBack else { return false }
        if currentWalk != nil, walkStep > 0 {
            walkStep -= 1
            return true
        }
        index -= 1
        walkStep = max(0, (currentWalk?.instructions.count ?? 1) - 1)
        return true
    }

    /// 換掉某個步行階段的路線（取得 Apple 地圖路線、或走錯路重新規劃）。
    /// 正在走這一段時從第一步開始。
    mutating func replaceWalk(at stageIndex: Int, with leg: WalkLeg) {
        guard stages.indices.contains(stageIndex), case .walk = stages[stageIndex] else { return }
        stages[stageIndex] = .walk(leg)
        if stageIndex == index { walkStep = 0 }
    }

    /// GPS 判斷已走到後面的步驟（只往前）。
    mutating func advanceWalk(to step: Int) {
        guard let walk = currentWalk, step > walkStep else { return }
        walkStep = min(step, walk.instructions.count - 1)
    }

    /// 戶外步行階段的起訖點（重新規劃用）。
    func walkEndpoints(at stageIndex: Int) -> WalkPlanLeg? {
        guard let legIndex = walkLegIndex[stageIndex], case .walk(let walk) = plan.legs[safe: legIndex] else { return nil }
        return walk
    }
}
