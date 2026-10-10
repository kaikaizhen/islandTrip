import Foundation

/// 交通資訊的白話文字。集中在這裡，避免各畫面各自拼字串、說法不一致。
enum TransitFormat {
    /// - Parameter unavailableText: 沒有預估時間的原因（例：「末班車已過」）；沒有就說「查無即時預估」。
    static func busCountdown(_ arrival: Date?, now: Date, unavailableText: String? = nil) -> String {
        guard let arrival else { return unavailableText ?? "查無即時預估" }
        let minutes = Int((arrival.timeIntervalSince(now) / 60).rounded(.up))
        return minutes <= 0 ? "即將進站" : "約 \(minutes) 分鐘到"
    }

    /// 路線名拆成主名與補充說明：「小9(台灣好行-北投竹子湖)」→（小9, 台灣好行-北投竹子湖）。
    /// 主名用大字且不可拆行；補充說明可以換行，避免長路線名把畫面撐出螢幕。
    static func routeNameParts(_ name: String) -> (main: String, detail: String?) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let open = trimmed.firstIndex(where: { $0 == "(" || $0 == "（" }), open != trimmed.startIndex else {
            return (trimmed, nil)
        }
        let main = trimmed[..<open].trimmingCharacters(in: .whitespaces)
        var detail = trimmed[trimmed.index(after: open)...].trimmingCharacters(in: .whitespaces)
        if detail.hasSuffix(")") || detail.hasSuffix("）") { detail.removeLast() }
        return (main, detail.isEmpty ? nil : detail)
    }

    /// 按鈕等單行處用的短路線名。
    static func shortRouteName(_ name: String) -> String { routeNameParts(name).main }

    /// 倒數框的內容：大字（分鐘數或狀態）＋小字單位。
    static func countdownParts(_ arrival: Date?, now: Date, unavailableText: String?) -> (value: String, unit: String?) {
        guard let arrival else { return (unavailableText ?? "查無即時預估", nil) }
        let minutes = Int((arrival.timeIntervalSince(now) / 60).rounded(.up))
        return minutes <= 0 ? ("即將進站", nil) : ("\(minutes)", "分鐘")
    }

    static func walkMinutes(_ seconds: Int) -> String {
        "走過去約 \(max(1, Int((Double(seconds) / 60).rounded(.up)))) 分鐘"
    }

    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func arrival(_ date: Date?, isEstimated: Bool = false) -> String {
        guard let date else { return "抵達時間未知" }
        return "預計 \(clock(date)) 到達" + (isEstimated ? "（估計）" : "")
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
