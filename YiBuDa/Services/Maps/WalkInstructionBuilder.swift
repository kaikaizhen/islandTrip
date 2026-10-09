import Foundation

/// 把 Apple 地圖的步行步驟轉成大箭頭 + 白話短句。
/// 轉向由路線幾何（轉彎前後的行進方位）判斷，不解析地圖文字，也不依手機朝向。
enum WalkInstructionBuilder {
    /// 判斷轉彎時，取轉彎點前後各多少公尺的路段計算方位，避免路線上的小抖動。
    static let bearingSampleMeters = 15.0

    static func instructions(for route: WalkingRoute, destinationName: String) -> [NavigationInstruction] {
        let steps = route.steps.filter { $0.distanceMeters > 0 && $0.coordinates.count >= 2 }
        guard !steps.isEmpty else {
            return [instruction(id: "walk-0", path: route.coordinates, upcoming: .arrive, upcomingText: nil,
                                destinationName: destinationName)]
        }

        var result: [NavigationInstruction] = []
        var path: [Coordinate] = []
        for (index, step) in steps.enumerated() {
            path += path.isEmpty ? step.coordinates : Array(step.coordinates.dropFirst())
            let next = steps[safe: index + 1]
            let upcoming = next.map { maneuver(after: step.coordinates, before: $0.coordinates) } ?? .arrive
            // 直走（只是路名改變）就與下一段合併，不多出一個「直走」步驟。
            if upcoming == .straight { continue }
            result.append(instruction(id: "walk-\(result.count)", path: path, upcoming: upcoming,
                                      upcomingText: next?.mapKitInstruction, destinationName: destinationName))
            path = []
        }
        return result
    }

    static func maneuver(after incomingPath: [Coordinate], before outgoingPath: [Coordinate]) -> Maneuver {
        let incomingLength = Geo.length(of: incomingPath)
        guard let incomingStart = Geo.point(along: incomingPath, meters: max(0, incomingLength - bearingSampleMeters)),
              let turnPoint = incomingPath.last,
              let outgoingEnd = Geo.point(along: outgoingPath, meters: bearingSampleMeters) else { return .straight }

        let angle = Geo.turnAngle(from: Geo.bearing(from: incomingStart, to: turnPoint),
                                  to: Geo.bearing(from: turnPoint, to: outgoingEnd))
        switch abs(angle) {
        case ..<30: return .straight
        case ..<60: return angle > 0 ? .slightRight : .slightLeft
        case ..<150: return angle > 0 ? .turnRight : .turnLeft
        default: return .uTurn
        }
    }

    private static func instruction(id: String, path: [Coordinate], upcoming: Maneuver, upcomingText: String?,
                                    destinationName: String) -> NavigationInstruction {
        let meters = Int(Geo.length(of: path).rounded())
        let distance = spoken(meters)
        let text = switch upcoming {
        case .turnLeft: "往前走 \(distance)，到路口左轉"
        case .turnRight: "往前走 \(distance)，到路口右轉"
        case .slightLeft: "往前走 \(distance)，再往左前方走"
        case .slightRight: "往前走 \(distance)，再往右前方走"
        case .uTurn: "往前走 \(distance)，再迴轉"
        case .arrive: "往前走 \(distance)，就到\(destinationName)"
        default: "往前直走 \(distance)"
        }
        let detail = upcomingText?.trimmingCharacters(in: .whitespacesAndNewlines)
        return NavigationInstruction(
            id: id, kind: upcoming, displayText: text, detailText: detail?.isEmpty == false ? detail : nil,
            distanceMeters: meters, targetCoordinate: path.last, safetyNote: nil, source: .mapKit, path: path
        )
    }

    /// 例：「120 公尺」「1.2 公里」。公尺取到十位，避免假精確。
    static func spoken(_ meters: Int) -> String {
        meters >= 1000 ? DistanceFormatter.long(meters) : "\(max(10, (meters + 5) / 10 * 10)) 公尺"
    }
}
