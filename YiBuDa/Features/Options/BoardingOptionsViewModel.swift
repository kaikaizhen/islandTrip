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
    /// 影響目前方案的異常消息（改道、停駛…）。
    private(set) var alerts: [ServiceAlert] = []
    private(set) var alertsUnavailable = false
    var order: JourneySortOrder = .earliestArrival {
        didSet { rerank() }
    }

    private var journeys: [Journey] = []
    private let transport: any TransportProvider
    /// nil 時沿用資料來源提供的步行段（測試用）。
    private let walkPlanner: (any JourneyWalkPlanning)?
    /// nil 時沒有異常消息（模擬資料）。
    private let alertProvider: (any ServiceAlertProviding)?
    private let ranking: TransitRankingService
    private let now: () -> Date

    init(
        origin: Place,
        destination: Place,
        transport: any TransportProvider,
        walkPlanner: (any JourneyWalkPlanning)? = nil,
        alerts: (any ServiceAlertProviding)? = nil,
        ranking: TransitRankingService = TransitRankingService(),
        now: @escaping () -> Date = Date.init
    ) {
        self.origin = origin
        self.destination = destination
        self.transport = transport
        self.walkPlanner = walkPlanner
        self.alertProvider = alerts
        self.ranking = ranking
        self.now = now
    }

    var currentTime: Date { now() }

    /// 主推以外的方案，依使用者選的排序方式。
    var others: [RankedJourney] { ranked.filter { $0.id != recommended?.id } }

    var selected: RankedJourney? { ranked.first { $0.id == selectedID } }

    var startTitle: String {
        selected?.option.map { "開始導航（搭 \(TransitFormat.shortRouteName($0.routeName))）" } ?? "請先選一班公車"
    }

    func load() async {
        state = .loading
        do {
            let candidates = try await transport.findJourneys(from: origin, to: destination)
            // 步行時間會影響「趕不趕得上」，所以先換成真實步行路線再排序。
            journeys = await walkPlanner?.plan(candidates) ?? candidates
            rerank()
            state = .loaded
            await loadAlerts()
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

    /// 影響這個方案路線的異常消息。
    func alerts(for journey: RankedJourney) -> [ServiceAlert] {
        guard let code = journey.option?.routeCode else { return [] }
        return alerts.filter { $0.routeCodes.contains(code) }
    }

    /// 只保留影響目前任一方案的消息；取得失敗不影響找車，但要讓使用者知道。
    private func loadAlerts() async {
        guard let alertProvider else { return }
        let cities = Set(journeys.compactMap { $0.busLeg?.option.city })
        let codes = Set(journeys.compactMap { $0.busLeg?.option.routeCode })
        var collected: [ServiceAlert] = []
        alertsUnavailable = false
        for city in cities.sorted() {
            do {
                collected += try await alertProvider.alerts(city: city).filter { !codes.isDisjoint(with: $0.routeCodes) }
            } catch {
                alertsUnavailable = true
            }
        }
        alerts = collected
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
