import Foundation

/// 上車側結論：使用者的回答優先，其次是穩定的 GPS 判斷，再其次是站牌資料；都沒有就問使用者，不硬猜。
enum BoardingSideResolver {
    static func resolve(
        answer: BoardingSideAnswer?,
        gpsEstimate: BoardingSideEstimator.Estimate?,
        gpsAccuracy: Double?,
        stopSide: BoardingSide?,
        lastEstimate: BoardingSideEstimator.Estimate?
    ) -> BoardingSideResolution {
        switch answer {
        case .nearbyIsCorrect: return .known(needsToCross: false, source: .manual)
        case .nearbyIsOpposite: return .known(needsToCross: true, source: .manual)
        case .cannotSeeSign: return .cannotTell
        case nil: break
        }
        let accuracy = Int(gpsAccuracy?.rounded() ?? 0)
        switch gpsEstimate {
        case .sameSideAsCorrectStop: return .known(needsToCross: false, source: .gps(accuracy: accuracy))
        case .oppositeSide: return .known(needsToCross: true, source: .gps(accuracy: accuracy))
        default: break
        }
        if case .confirmed(let needsToCross, _) = stopSide {
            return .known(needsToCross: needsToCross, source: .stopData)
        }
        if case .uncertain(let reason) = lastEstimate { return .ask(reason: reason) }
        return .ask(reason: nil)
    }
}
