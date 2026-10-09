import Foundation

/// 後端（家中 NAS）的位址與 App 金鑰，來自 Config/Local.xcconfig → Info.plist。
/// 沒有設定時 App 使用模擬資料。App 金鑰不是 TDX 密鑰，只用來擋掉陌生請求。
struct BackendConfiguration: Equatable, Sendable {
    var baseURL: URL
    var appKey: String

    static func from(info: [String: Any]?) -> BackendConfiguration? {
        guard let urlString = (info?["YiBuDaBackendURL"] as? String)?.trimmingCharacters(in: .whitespaces),
              let url = URL(string: urlString), let scheme = url.scheme, ["https", "http"].contains(scheme), url.host() != nil,
              let key = (info?["YiBuDaAppKey"] as? String)?.trimmingCharacters(in: .whitespaces), key.count >= 24
        else { return nil }
        return BackendConfiguration(baseURL: url, appKey: key)
    }
}
