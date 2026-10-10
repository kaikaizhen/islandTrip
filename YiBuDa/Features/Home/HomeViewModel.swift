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
    private let favoritesStore: any FavoritePlacesStoring
    private let currentPlace: any CurrentPlaceProviding
    /// 設定常用地點時的錯誤（例如定位失敗）。
    private(set) var favoriteProblem: String?

    init(places: any PlaceSearching, favorites: any FavoritePlacesStoring, currentPlace: any CurrentPlaceProviding) {
        self.places = places
        self.favoritesStore = favorites
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
        favorites = await favoritesStore.favoritePlaces()
        await refreshOrigin()
    }

    // MARK: 常用地點（使用者自己設定）

    /// 家、公司、學校三個欄位；沒設定的是 nil。
    var favoriteSlots: [(kind: Place.Kind, place: Place?)] {
        Place.Kind.favoriteSlots.map { kind in (kind, favorites.first { $0.kind == kind }) }
    }

    func setFavorite(_ place: Place, as kind: Place.Kind) async {
        await favoritesStore.setFavorite(place, as: kind)
        favorites = await favoritesStore.favoritePlaces()
        favoriteProblem = nil
        // 正在選這個欄位當目的地時，改成新地點。
        if destination?.kind == kind, let updated = favorites.first(where: { $0.kind == kind }) { select(updated) }
    }

    /// 用手機目前位置設定（例如人在家時設定「家」）。
    func setFavoriteToCurrentLocation(_ kind: Place.Kind) async {
        do {
            let here = try await currentPlace.currentPlace()
            await setFavorite(Place(id: here.id, name: "\(kind.label)（目前位置設定）", subtitle: here.subtitle,
                                    coordinate: here.coordinate, kind: kind), as: kind)
        } catch {
            favoriteProblem = "無法取得目前位置，請改用搜尋地址設定「\(kind.label)」。"
        }
    }

    func removeFavorite(_ kind: Place.Kind) async {
        await favoritesStore.removeFavorite(kind)
        favorites = await favoritesStore.favoritePlaces()
        if destination?.kind == kind { clearDestination() }
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

extension Place.Kind {
    /// 常用地點按鈕上的文字，例：家 →「回家」。
    var favoriteTitle: String {
        self == .home ? "回家" : label
    }

    var symbolName: String {
        switch self {
        case .home: "house.fill"
        case .work: "briefcase.fill"
        case .school: "graduationcap.fill"
        case .other: "mappin.circle.fill"
        }
    }
}
