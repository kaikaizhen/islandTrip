import Foundation

/// 地理計算（純函式）。距離以公尺、方位以度（正北 0，順時針）。
/// 步行導航的距離都在數公里內，用局部平面近似即可。
enum Geo {
    static let earthRadius = 6_371_000.0

    static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    static func bearing(from a: Coordinate, to b: Coordinate) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    /// 兩個方位的夾角，範圍 (-180, 180]；正值代表往右（順時針）。
    static func turnAngle(from incoming: Double, to outgoing: Double) -> Double {
        var delta = (outgoing - incoming).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta <= -180 { delta += 360 }
        return delta
    }

    static func length(of path: [Coordinate]) -> Double {
        zip(path, path.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    /// 沿路徑從起點走 `meters` 公尺後的位置（超過長度則回傳終點）。
    static func point(along path: [Coordinate], meters: Double) -> Coordinate? {
        guard var previous = path.first else { return nil }
        var remaining = meters
        for next in path.dropFirst() {
            let segment = distance(previous, next)
            if segment >= remaining, segment > 0 {
                let t = remaining / segment
                return Coordinate(latitude: previous.latitude + (next.latitude - previous.latitude) * t,
                                  longitude: previous.longitude + (next.longitude - previous.longitude) * t)
            }
            remaining -= segment
            previous = next
        }
        return path.last
    }

    /// 點到路徑的最近距離，以及最近點距離路徑起點多遠（沿路徑）。
    static func projection(of point: Coordinate, onto path: [Coordinate]) -> (distance: Double, along: Double)? {
        guard path.count >= 2 else {
            return path.first.map { (distance(point, $0), 0) }
        }
        var best: (distance: Double, along: Double)?
        var walked = 0.0
        for (a, b) in zip(path, path.dropFirst()) {
            let (offset, t) = localOffset(of: point, segmentStart: a, segmentEnd: b)
            let segment = distance(a, b)
            let candidate = (distance: offset, along: walked + segment * t)
            if best == nil || candidate.distance < best!.distance { best = candidate }
            walked += segment
        }
        return best
    }

    /// 在局部平面上，點到線段的距離與投影位置比例 t（0...1）。
    private static func localOffset(of p: Coordinate, segmentStart a: Coordinate, segmentEnd b: Coordinate) -> (Double, Double) {
        let metersPerDegreeLat = .pi * earthRadius / 180
        let metersPerDegreeLon = metersPerDegreeLat * cos(a.latitude * .pi / 180)
        let bx = (b.longitude - a.longitude) * metersPerDegreeLon, by = (b.latitude - a.latitude) * metersPerDegreeLat
        let px = (p.longitude - a.longitude) * metersPerDegreeLon, py = (p.latitude - a.latitude) * metersPerDegreeLat
        let lengthSquared = bx * bx + by * by
        let t = lengthSquared > 0 ? max(0, min(1, (px * bx + py * by) / lengthSquared)) : 0
        let dx = px - bx * t, dy = py - by * t
        return (sqrt(dx * dx + dy * dy), t)
    }
}
