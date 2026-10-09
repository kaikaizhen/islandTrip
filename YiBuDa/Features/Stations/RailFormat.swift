import Foundation

/// 軌道發車資訊的白話文字。資料等級一定要說清楚（即時／依時刻表／班距）。
enum RailFormat {
    static func dataLevel(_ level: RailDataLevel) -> String {
        switch level {
        case .realtime: "即時"
        case .timetable: "依時刻表"
        case .frequency: "班距"
        }
    }

    /// 大字主要資訊，例：「3 分鐘」「約每 4–6 分鐘一班」「末班車已過」。
    static func primary(_ departure: RailDeparture, now: Date) -> String {
        if let headway = departure.headway {
            return headway.lowerBound == headway.upperBound ? "約每 \(headway.lowerBound) 分鐘一班" : "約每 \(headway.lowerBound)–\(headway.upperBound) 分鐘一班"
        }
        if departure.status != .normal, let note = departure.status.note, departure.expectedAt == nil || departure.status == .suspended {
            return note
        }
        guard let expected = departure.expectedAt else { return departure.status.note ?? "時間未提供" }
        let minutes = Int((expected.timeIntervalSince(now) / 60).rounded(.up))
        return minutes <= 0 ? "即將進站" : "\(minutes) 分鐘"
    }

    /// 小字補充，例：「08:15 開・誤點 5 分」「08:15 開・準點」。
    static func secondary(_ departure: RailDeparture) -> String? {
        guard let expected = departure.expectedAt else { return nil }
        var parts = ["\(TransitFormat.clock(expected)) \(departure.trainNo == nil ? "到站" : "開")"]
        if let delay = departure.delayMinutes {
            parts.append(delay > 0 ? "誤點 \(delay) 分" : "準點")
        }
        return parts.joined(separator: "・")
    }

    /// 例：「自強 111・往高雄」。
    static func title(_ departure: RailDeparture) -> String {
        let line = [departure.line, departure.trainNo].compactMap { $0 }.joined(separator: " ")
        let destination = departure.destination.map { "往\($0)" } ?? departure.direction
        return [line.isEmpty ? nil : line, destination].compactMap { $0 }.joined(separator: "・")
    }

    static func distance(_ meters: Int?) -> String? {
        meters.map { $0 >= 1000 ? "約 \(DistanceFormatter.long($0))" : "約 \(WalkInstructionBuilder.spoken($0))" }
    }
}
