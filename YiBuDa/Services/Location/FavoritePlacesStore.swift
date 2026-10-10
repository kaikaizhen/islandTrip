import Foundation

/// 存在 UserDefaults 的常用地點。只存使用者自己設定的地點名稱與座標，不上傳。
actor UserDefaultsFavoritePlacesStore: FavoritePlacesStoring {
    private struct Record: Codable {
        var name: String
        var subtitle: String?
        var latitude: Double
        var longitude: Double
    }

    static let key = "favoritePlaces.v1"
    private let defaults: UserDefaults

    /// - Parameter suiteName: 測試用；nil 為 App 的標準設定。
    init(suiteName: String? = nil) {
        self.defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    func favoritePlaces() async -> [Place] {
        let records = load()
        return Place.Kind.favoriteSlots.compactMap { kind in
            records[kind.rawValue].map { record in
                Place(id: "favorite.\(kind.rawValue)", name: record.name, subtitle: record.subtitle,
                      coordinate: Coordinate(latitude: record.latitude, longitude: record.longitude), kind: kind)
            }
        }
    }

    func setFavorite(_ place: Place, as kind: Place.Kind) async {
        var records = load()
        records[kind.rawValue] = Record(name: place.name, subtitle: place.subtitle,
                                        latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
        save(records)
    }

    func removeFavorite(_ kind: Place.Kind) async {
        var records = load()
        records[kind.rawValue] = nil
        save(records)
    }

    private func load() -> [String: Record] {
        guard let data = defaults.data(forKey: Self.key) else { return [:] }
        return (try? JSONDecoder().decode([String: Record].self, from: data)) ?? [:]
    }

    private func save(_ records: [String: Record]) {
        defaults.set(try? JSONEncoder().encode(records), forKey: Self.key)
    }
}

/// 只在記憶體的常用地點（測試與離線模擬用；可預先放入地點）。
actor InMemoryFavoritePlacesStore: FavoritePlacesStoring {
    private var places: [Place.Kind: Place]

    init(_ places: [Place] = []) {
        self.places = Dictionary(places.map { ($0.kind, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func favoritePlaces() async -> [Place] {
        Place.Kind.favoriteSlots.compactMap { places[$0] }
    }

    func setFavorite(_ place: Place, as kind: Place.Kind) async {
        var copy = place
        copy.kind = kind
        copy.id = "favorite.\(kind.rawValue)"
        places[kind] = copy
    }

    func removeFavorite(_ kind: Place.Kind) async {
        places[kind] = nil
    }
}
