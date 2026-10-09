import Foundation
import Observation

/// 轉乘方案（含捷運、火車）：只供查看，尚不支援轉乘導航。
/// 與直達公車分開載入：MaaS 較慢，不能拖住直達公車的結果。
@MainActor
@Observable
final class TransitPlansViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    let origin: Place
    let destination: Place
    private(set) var state: LoadState = .idle
    private(set) var plans: [TransitPlan] = []

    private let planner: any TransitPlanning
    private let now: () -> Date

    init(origin: Place, destination: Place, planner: any TransitPlanning, now: @escaping () -> Date = Date.init) {
        self.origin = origin
        self.destination = destination
        self.planner = planner
        self.now = now
    }

    var currentTime: Date { now() }

    func load() async {
        state = .loading
        do {
            let result = try await planner.plans(from: origin, to: destination)
            // 沒有搭乘段的（全程走路）不算轉乘方案；依抵達時間排序，同時抵達時轉乘少的優先。
            plans = result
                .filter { !$0.transitLegs.isEmpty }
                .sorted { lhs, rhs in
                    let left = lhs.endAt ?? .distantFuture, right = rhs.endAt ?? .distantFuture
                    return left != right ? left < right : lhs.transfers < rhs.transfers
                }
            state = .loaded
        } catch {
            plans = []
            state = .failed("暫時查不到轉乘方案，直達公車不受影響。")
        }
    }
}
