import Foundation
import Observation

/// 地點搜尋輸入框的狀態：目的地與手動輸入出發地共用。
@MainActor
@Observable
final class PlaceSearchModel {
    /// 輸入框文字；與已選地點不同時視為重新搜尋。
    var query = "" {
        didSet { if query != selected?.name { selected = nil } }
    }
    private(set) var suggestions: [Place] = []
    private(set) var selected: Place?
    private(set) var errorMessage: String?

    private let places: any PlaceSearching

    init(places: any PlaceSearching) {
        self.places = places
    }

    func search(near: Coordinate?) async {
        guard selected == nil else {
            suggestions = []
            return
        }
        do {
            suggestions = try await places.searchPlaces(query, near: near)
            errorMessage = nil
        } catch {
            suggestions = []
            errorMessage = "搜尋失敗，請檢查網路後再試。"
        }
    }

    func select(_ place: Place) {
        selected = place
        query = place.name
        suggestions = []
    }

    func clear() {
        query = ""
        suggestions = []
    }
}

/// 讓搜尋狀態能以 `.sheet(item:)` 呈現。
extension PlaceSearchModel: Identifiable {}
