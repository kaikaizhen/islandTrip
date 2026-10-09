import Foundation
import MapKit

/// 以 Apple MapKit（MKLocalSearch）搜尋真實地點，取得名稱、地址與座標。需要網路。
struct MapKitPlaceSearch: PlaceSearching {
    /// 沒有目前位置時的搜尋中心（台北市中心）。
    var fallbackCenter = Coordinate(latitude: 25.0375, longitude: 121.5637)
    /// 優先搜尋的範圍（公尺）。
    var searchRadius: CLLocationDistance = 30_000
    var maxResults = 8

    func searchPlaces(_ query: String, near: Coordinate?) async throws -> [Place] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.region = MKCoordinateRegion(center: (near ?? fallbackCenter).clCoordinate,
                                            latitudinalMeters: searchRadius, longitudinalMeters: searchRadius)
        request.resultTypes = [.pointOfInterest, .address]

        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.prefix(maxResults).map(Self.place(from:))
        } catch let error as MKError where error.code == .placemarkNotFound {
            // 查無結果不是錯誤，顯示空清單即可。
            return []
        }
    }

    private static func place(from item: MKMapItem) -> Place {
        let coordinate: CLLocationCoordinate2D
        let address: String?
        if #available(iOS 26, *) {
            coordinate = item.location.coordinate
            address = item.address?.shortAddress ?? item.address?.fullAddress
        } else {
            coordinate = item.placemark.coordinate
            address = item.placemark.title
        }
        let name = item.name ?? address ?? "未命名地點"
        return Place(
            id: "mapkit:\(coordinate.latitude),\(coordinate.longitude):\(name)",
            name: name,
            subtitle: address == name ? nil : address,
            coordinate: Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        )
    }
}
