import Foundation

/// Phase 0 用的固定模擬步驟，用來驗證動態島／鎖定畫面的呈現。
/// 內容是模擬資料，不代表真實班次或路線。
struct SimulatedNavigationScript: Sendable {
    struct Step: Equatable, Sendable {
        var maneuver: Maneuver
        var title: String
        var detail: String
        var distanceMeters: Int?
        var nextStep: String?
    }

    let destinationName: String
    let steps: [Step]

    var count: Int { steps.count }

    func state(at index: Int, updatedAt: Date) -> NavigationActivityAttributes.ContentState? {
        guard steps.indices.contains(index) else { return nil }
        let step = steps[index]
        return .init(
            maneuver: step.maneuver,
            title: step.title,
            detail: step.detail,
            distanceMeters: step.distanceMeters,
            nextStep: step.nextStep,
            updatedAt: updatedAt
        )
    }
}

extension SimulatedNavigationScript {
    static let phase0 = SimulatedNavigationScript(
        destinationName: "台北車站",
        steps: [
            Step(maneuver: .turnRight, title: "前方右轉", detail: "120 公尺後右轉",
                 distanceMeters: 120, nextStep: "下一步：搭乘 307 公車"),
            Step(maneuver: .turnRight, title: "前方右轉", detail: "80 公尺後右轉",
                 distanceMeters: 80, nextStep: "下一步：搭乘 307 公車"),
            Step(maneuver: .turnRight, title: "前方右轉", detail: "40 公尺後右轉",
                 distanceMeters: 40, nextStep: "下一步：搭乘 307 公車"),
            Step(maneuver: .straight, title: "直走", detail: "直走 60 公尺到站牌",
                 distanceMeters: 60, nextStep: "到站後：等 307 公車"),
            Step(maneuver: .arrive, title: "到站牌了", detail: "請在這裡等 307 公車",
                 distanceMeters: nil, nextStep: nil),
        ]
    )
}
