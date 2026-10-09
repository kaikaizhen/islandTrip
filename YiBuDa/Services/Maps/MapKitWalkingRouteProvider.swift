import Foundation
import MapKit

/// 以 Apple MapKit（MKDirections，步行模式）計算合法的步行路線。需要網路。
struct MapKitWalkingRouteProvider: WalkingRouteProviding {
    func walkingRoute(from origin: Coordinate, to destination: Coordinate) async throws -> WalkingRoute {
        let request = MKDirections.Request()
        request.source = Self.mapItem(origin)
        request.destination = Self.mapItem(destination)
        request.transportType = .walking

        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else { throw WalkingRouteError.noRoute }

        return WalkingRoute(
            coordinates: Self.coordinates(of: route.polyline),
            expectedSeconds: Int(route.expectedTravelTime.rounded()),
            distanceMeters: Int(route.distance.rounded()),
            steps: route.steps.map { step in
                WalkingRoute.Step(mapKitInstruction: step.instructions, distanceMeters: Int(step.distance.rounded()),
                                  coordinates: Self.coordinates(of: step.polyline))
            }
        )
    }

    private static func coordinates(of polyline: MKPolyline) -> [Coordinate] {
        var points = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: polyline.pointCount)
        polyline.getCoordinates(&points, range: NSRange(location: 0, length: polyline.pointCount))
        return points.map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
    }
}

private extension MapKitWalkingRouteProvider {
    static func mapItem(_ coordinate: Coordinate) -> MKMapItem {
        if #available(iOS 26, *) {
            MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
        } else {
            MKMapItem(placemark: MKPlacemark(coordinate: coordinate.clCoordinate))
        }
    }
}

extension Coordinate {
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
