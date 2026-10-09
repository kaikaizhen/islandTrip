import Foundation
import Observation

/// 首頁：選目的地（搜尋或常用地點）。
@MainActor
@Observable
final class HomeViewModel {
    /// 輸入框文字；與已選目的地不同時視為重新搜尋。
    var query = "" {
        didSet { if query != destination?.name { destination = nil } }
    }
    private(set) var suggestions: [Place] = []
    private(set) var destination: Place?
    private(set) var favorites: [Place] = []
    private(set) var origin: Place?
    private(set) var errorMessage: String?

    private let places: any PlaceSearching
    private let favoritesProvider: any FavoritePlacesProviding
    private let currentPlace: any CurrentPlaceProviding

    init(places: any PlaceSearching, favorites: any FavoritePlacesProviding, currentPlace: any CurrentPlaceProviding) {
        self.places = places
        self.favoritesProvider = favorites
        self.currentPlace = currentPlace
    }

    var canSearchBuses: Bool { destination != nil && origin != nil }

    func load() async {
        favorites = await favoritesProvider.favoritePlaces()
        do {
            origin = try await currentPlace.currentPlace()
        } catch {
            errorMessage = "無法取得目前位置。"
        }
    }

    func search() async {
        guard destination == nil else {
            suggestions = []
            return
        }
        do {
            suggestions = try await places.searchPlaces(query)
            errorMessage = nil
        } catch {
            suggestions = []
            errorMessage = "搜尋失敗，請稍後再試。"
        }
    }

    func select(_ place: Place) {
        destination = place
        query = place.name
        suggestions = []
    }

    func clearDestination() {
        query = ""
        suggestions = []
    }
}

extension Place {
    /// 常用地點按鈕上的文字，例：家 →「回家」。
    var favoriteTitle: String {
        kind == .home ? "回家" : name
    }
}
