import Foundation

/// 方案的逐步說明（大字、白話）。純函式，方便測試。
struct PlanStep: Identifiable, Hashable {
    enum DataTag: Hashable {
        case realtime
        case scheduled
    }

    var id: Int
    var symbolName: String
    var title: String
    var detail: String
    /// 只有搭乘步驟有；標示時間是即時還是表定。
    var dataTag: DataTag?
}

enum PlanSteps {
    static func make(_ plan: TransitPlan, originName: String, destinationName: String, now: Date) -> [PlanStep] {
        var steps: [PlanStep] = []
        for (index, leg) in plan.legs.enumerated() {
            let isLast = index == plan.legs.count - 1
            switch leg {
            case .walk(let walk):
                let target = isLast ? destinationName : PlanFormat.place(walk.to, fallback: "下一站")
                let distance = walk.meters > 0 ? "走路約 \(WalkInstructionBuilder.spoken(walk.meters))・" : ""
                steps.append(PlanStep(
                    id: index, symbolName: walk.inStation ? "figure.walk.motion" : "figure.walk",
                    title: walk.inStation ? "在站內走到 \(target)" : "走到 \(target)",
                    detail: distance + TransitFormat.walkMinutes(walk.seconds).replacingOccurrences(of: "走過去", with: ""),
                    dataTag: nil
                ))
            case .wait(let wait):
                steps.append(PlanStep(id: index, symbolName: "clock", title: "在 \(PlanFormat.place(wait.at, fallback: "車站")) 等車",
                                      detail: PlanFormat.waitMinutes(wait.seconds), dataTag: nil))
            case .transit(let transit):
                let title = "搭 \(PlanFormat.lineTitle(transit))" + (PlanFormat.headsign(transit).map { "（\($0)）" } ?? "")
                let from = PlanFormat.place(transit.from, fallback: originName)
                let to = PlanFormat.place(transit.to, fallback: destinationName)
                steps.append(PlanStep(
                    id: index, symbolName: transit.mode.symbolName, title: title,
                    detail: "在 \(from) 上車，\(to) 下車\n\(PlanFormat.boardingTimeWithoutTag(transit, now: now))",
                    dataTag: PlanFormat.isRealtime(transit) ? .realtime : .scheduled
                ))
            }
        }
        return steps
    }
}
