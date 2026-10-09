import Foundation
import Observation

/// 首頁：出發地（GPS、模擬或手動輸入）與目的地（搜尋或常用地點）。
@MainActor
@Observable
final class HomeViewModel {
    let destinationSearch: PlaceSearchModel
    private(set) var favorites: [Place] = []
    private(set) var origin: Place?
    private(set) var isLocating = false
    /// 定位失敗的說明；有值時首頁提供「手動輸入出發地」。
    private(set) var originProblem: String?
    /// 使用者手動指定的出發地；有值時不再用 GPS 覆蓋。
    private var manualOrigin: Place?

    private let places: any PlaceSearching
    private let favoritesProvider: any FavoritePlacesProviding
    private let currentPlace: any CurrentPlaceProviding

    init(places: any PlaceSearching, favorites: any FavoritePlacesProviding, currentPlace: any CurrentPlaceProviding) {
        self.places = places
        self.favoritesProvider = favorites
        self.currentPlace = currentPlace
        self.destinationSearch = PlaceSearchModel(places: places)
    }

    // 目的地輸入框（保留給畫面與測試的簡短介面）
    var query: String {
        get { destinationSearch.query }
        set { destinationSearch.query = newValue }
    }
    var suggestions: [Place] { destinationSearch.suggestions }
    var destination: Place? { destinationSearch.selected }
    var errorMessage: String? { destinationSearch.errorMessage }

    var canSearchBuses: Bool { destination != nil && origin != nil }
    var isUsingManualOrigin: Bool { manualOrigin != nil }

    func load() async {
        favorites = await favoritesProvider.favoritePlaces()
        await refreshOrigin()
    }

    /// 重新取得目前位置（手動指定出發地時不覆蓋）。
    func refreshOrigin() async {
        guard manualOrigin == nil else { return }
        isLocating = true
        defer { isLocating = false }
        do {
            origin = try await currentPlace.currentPlace()
            originProblem = nil
        } catch LocationError.denied {
            origin = nil
            originProblem = "定位權限沒有開啟。可以到「設定 > 島行 > 位置」開啟，或手動輸入出發地。"
        } catch {
            origin = nil
            originProblem = "暫時無法取得目前位置，請到空曠處再試，或手動輸入出發地。"
        }
    }

    func search() async {
        await destinationSearch.search(near: origin?.coordinate)
    }

    func select(_ place: Place) {
        destinationSearch.select(place)
    }

    func clearDestination() {
        destinationSearch.clear()
    }

    func makeOriginSearch() -> PlaceSearchModel {
        PlaceSearchModel(places: places)
    }

    func setManualOrigin(_ place: Place) {
        manualOrigin = place
        origin = place
        originProblem = nil
    }

    /// 改回使用目前位置。
    func useCurrentLocation() async {
        manualOrigin = nil
        await refreshOrigin()
    }
}

extension Place {
    /// 常用地點按鈕上的文字，例：家 →「回家」。
    var favoriteTitle: String {
        kind == .home ? "回家" : name
    }
}
