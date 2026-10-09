import Foundation

/// 確認一段公車行程真的能從上車站坐到下車站：
/// 站牌 UID 一致、停靠模式一致，而且上車站在下車站之前。只看路線編號是不夠的。
enum BoardingDirectionValidator {
    static func isValid(_ leg: BusLeg) -> Bool {
        let option = leg.option
        return leg.boardingStop.stopUID == option.boardingStopUID
            && leg.alightingStop.stopUID == option.alightingStopUID
            && leg.pattern.patternId == option.patternId
            && leg.pattern.serves(from: option.boardingStopUID, to: option.alightingStopUID)
    }
}
