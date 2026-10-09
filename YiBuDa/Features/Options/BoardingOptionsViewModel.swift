import Foundation
import Observation

/// 推薦班次：列出所有可搭方案，主推「趕得上且最快抵達」。
@MainActor
@Observable
final class BoardingOptionsViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    let origin: Place
    let destination: Place
    private(set) var state: LoadState = .loading
    private(set) var ranked: [RankedJourney] = []
    private(set) var recommended: RankedJourney?
    private(set) var selectedID: RankedJourney.ID?
    var order: JourneySortOrder = .earliestArrival {
        didSet { rerank() }
    }

    private var journeys: [Journey] = []
    private let transport: any TransportProvider
    private let ranking: TransitRankingService
    private let now: () -> Date

    init(
        origin: Place,
        destination: Place,
        transport: any TransportProvider,
        ranking: TransitRankingService = TransitRankingService(),
        now: @escaping () -> Date = Date.init
    ) {
        self.origin = origin
        self.destination = destination
        self.transport = transport
        self.ranking = ranking
        self.now = now
    }

    var currentTime: Date { now() }

    /// 主推以外的方案，依使用者選的排序方式。
    var others: [RankedJourney] { ranked.filter { $0.id != recommended?.id } }

    var selected: RankedJourney? { ranked.first { $0.id == selectedID } }

    var startTitle: String {
        selected?.option.map { "開始導航（搭 \($0.routeName)）" } ?? "請先選一班公車"
    }

    func load() async {
        state = .loading
        do {
            journeys = try await transport.findJourneys(from: origin, to: destination)
            rerank()
            state = .loaded
        } catch {
            state = .failed("找不到班次資料，請檢查網路後再試一次。")
        }
    }

    /// 重新以目前時間評估（倒數、能否趕上會隨時間改變）。
    func rerank() {
        let time = now()
        ranked = ranking.rank(journeys, now: time, order: order)
        recommended = ranking.recommendation(in: ranking.rank(journeys, now: time, order: .earliestArrival))
        if selectedID == nil || !ranked.contains(where: { $0.id == selectedID }) {
            selectedID = recommended?.id
        }
    }

    func select(_ journey: RankedJourney) {
        selectedID = journey.id
    }

    /// 同一個上車站的其他有效方案，給候車畫面當替代班次。
    func alternatives(for journey: RankedJourney) -> [Journey] {
        let stopUID = journey.option?.boardingStopUID
        return ranked.map(\.journey).filter { $0.busLeg?.option.boardingStopUID == stopUID }
    }
}
