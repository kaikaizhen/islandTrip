import Foundation

/// 將公尺數轉成長輩易讀的文字，避免各畫面自行拼字串。
enum DistanceFormatter {
    /// 例：「120 公尺」、「1.2 公里」
    static func long(_ meters: Int) -> String {
        guard meters >= 1000 else { return "\(meters) 公尺" }
        return String(format: "%.1f 公里", Double(meters) / 1000)
    }

    /// 動態島等狹窄空間使用，例：「120m」、「1.2km」
    static func compact(_ meters: Int) -> String {
        guard meters >= 1000 else { return "\(meters)m" }
        return String(format: "%.1fkm", Double(meters) / 1000)
    }
}
