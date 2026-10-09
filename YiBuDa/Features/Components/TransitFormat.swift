import Foundation

/// 交通資訊的白話文字。集中在這裡，避免各畫面各自拼字串、說法不一致。
enum TransitFormat {
    static func busCountdown(_ arrival: Date?, now: Date) -> String {
        guard let arrival else { return "查無即時預估" }
        let minutes = Int((arrival.timeIntervalSince(now) / 60).rounded(.up))
        return minutes <= 0 ? "即將進站" : "約 \(minutes) 分鐘到"
    }

    static func walkMinutes(_ seconds: Int) -> String {
        "走過去約 \(max(1, Int((Double(seconds) / 60).rounded(.up)))) 分鐘"
    }

    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func arrival(_ date: Date?) -> String {
        date.map { "預計 \(clock($0)) 到達" } ?? "抵達時間未知"
    }

    static func updated(_ date: Date, isStale: Bool) -> String {
        isStale ? "資訊可能過期（\(clock(date)) 更新）" : "資料 \(clock(date)) 更新"
    }

    static func catchStatus(_ status: CatchStatus) -> (text: String, symbol: String) {
        switch status {
        case .canCatch: ("趕得上", "checkmark.circle.fill")
        case .tooLate: ("可能趕不上", "xmark.circle")
        case .unknown: ("無法判斷", "questionmark.circle")
        }
    }
}
