import Foundation

/// 轉乘方案的白話文字。即時與表定一定要分清楚，不可把表定時間說成即時。
enum PlanFormat {
    static func duration(_ seconds: Int) -> String {
        let minutes = max(1, Int((Double(seconds) / 60).rounded(.up)))
        return minutes >= 60 ? "約 \(minutes / 60) 小時 \(minutes % 60) 分鐘" : "約 \(minutes) 分鐘"
    }

    /// 例：「不用轉乘・走路約 650 公尺」「轉乘 1 次・走路約 650 公尺」。
    static func summary(_ plan: TransitPlan) -> String {
        let transfers = plan.transfers == 0 ? "不用轉乘" : "轉乘 \(plan.transfers) 次"
        return "\(transfers)・走路約 \(WalkInstructionBuilder.spoken(plan.walkMeters))"
    }

    /// 例：「捷運 板南線」「公車 88建國幹線」。
    static func lineTitle(_ leg: TransitLeg) -> String {
        leg.line.isEmpty ? leg.mode.displayName : "\(leg.mode.displayName) \(leg.line)"
    }

    static func headsign(_ leg: TransitLeg) -> String? {
        guard let headsign = leg.headsign?.trimmingCharacters(in: .whitespaces), !headsign.isEmpty else { return nil }
        return headsign.hasPrefix("往") ? headsign : "往\(headsign)"
    }

    static func isRealtime(_ leg: TransitLeg) -> Bool { leg.realtime != nil || leg.railRealtime != nil }

    static func dataTag(_ leg: TransitLeg) -> String { isRealtime(leg) ? "即時" : "表定" }

    /// 上車時間：有即時就說倒數（或沒有預估的原因），否則說表定時刻並標「表定」。
    static func boardingTime(_ leg: TransitLeg, now: Date) -> String {
        if let rail = leg.railRealtime {
            let minutes = Int((rail.expectedAt.timeIntervalSince(now) / 60).rounded(.up))
            let base = minutes <= 0 ? "即時：即將進站" : "即時：約 \(minutes) 分鐘開"
            switch rail.delayMinutes {
            case .some(let delay) where delay > 0: return "\(base)（誤點 \(delay) 分）"
            case .some(0): return "\(base)（準點）"
            default: return base
            }
        }
        if let realtime = leg.realtime {
            if let arrival = realtime.arrivalAt {
                return "即時：" + TransitFormat.busCountdown(arrival, now: now)
            }
            let reason = "即時：\(realtime.statusNote ?? "查無即時預估")"
            return leg.departAt.map { "\(reason)（表定 \(TransitFormat.clock($0))）" } ?? reason
        }
        return leg.departAt.map { "表定 \(TransitFormat.clock($0)) 開" } ?? "時間未提供"
    }

    /// 旁邊已有「即時／表定」標籤時用：不重複標籤文字，例：「約 6 分鐘到」「08:05 開」。
    static func boardingTimeWithoutTag(_ leg: TransitLeg, now: Date) -> String {
        let text = boardingTime(leg, now: now)
        for prefix in ["即時：", "表定 "] where text.hasPrefix(prefix) {
            return String(text.dropFirst(prefix.count))
        }
        return text
    }

    static func place(_ place: PlanPlace, fallback: String) -> String {
        guard let name = place.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return fallback }
        return name
    }

    static func waitMinutes(_ seconds: Int) -> String {
        "等車約 \(max(1, Int((Double(seconds) / 60).rounded(.up)))) 分鐘"
    }
}
