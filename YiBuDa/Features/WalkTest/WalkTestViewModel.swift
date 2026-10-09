import Foundation
import Observation

/// 步行導航測試：用真實 GPS 與 Apple 地圖步行路線，走到任一附近地點（不含公車）。
/// 讓不在模擬站牌附近時，也能在真機驗證箭頭與防跳步。
@MainActor
@Observable
final class WalkTestViewModel {
    enum State: Equatable {
        case locating
        case ready(LocationSample)
        case planning
        case failed(String)
    }

    private(set) var state: State = .locating
    let search: PlaceSearchModel

    private let location: any LocationProviding
    private let planner: any JourneyWalkPlanning
    private let now: () -> Date

    init(location: any LocationProviding, places: any PlaceSearching, planner: any JourneyWalkPlanning,
         now: @escaping () -> Date = Date.init) {
        self.location = location
        self.planner = planner
        self.now = now
        self.search = PlaceSearchModel(places: places)
    }

    var currentSample: LocationSample? {
        if case .ready(let sample) = state { sample } else { nil }
    }

    func locate() async {
        state = .locating
        do {
            state = .ready(try await location.currentLocation())
        } catch LocationError.denied {
            state = .failed("定位權限沒有開啟，請到「設定 > 一步搭 > 位置」開啟。")
        } catch {
            state = .failed("暫時無法定位，請到空曠處再試一次。")
        }
    }

    /// 規劃從目前位置走到目的地的路線；失敗時回傳 nil 並說明。
    func makeJourney(to destination: Place) async -> Journey? {
        guard let sample = currentSample else { return nil }
        state = .planning
        let origin = Place(id: "gps.current", name: "目前位置", coordinate: sample.coordinate)
        let leg = await planner.walkLeg(from: sample.coordinate, to: destination.coordinate, name: destination.name)
        state = .ready(sample)
        guard !leg.isEstimated else {
            state = .failed("無法取得步行路線（可能太遠或沒有網路），請換一個近一點的地點。")
            return nil
        }
        return Journey(id: "walktest-\(destination.id)", origin: origin, destination: destination,
                       legs: [.walk(leg)], computedAt: now())
    }
}
