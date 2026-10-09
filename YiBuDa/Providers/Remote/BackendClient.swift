import Foundation

enum BackendError: Error, Equatable {
    case unauthorized
    case rateLimited
    case server(Int)
    case invalidResponse
}

/// 呼叫 NAS 後端：帶 App 金鑰、逾時、狀態碼轉成可理解的錯誤。
struct BackendClient: Sendable {
    let configuration: BackendConfiguration
    var session: URLSession = .shared
    var timeout: TimeInterval = 15

    func get<Response: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> Response {
        guard var components = URLComponents(url: configuration.baseURL.appending(path: path), resolvingAgainstBaseURL: false) else {
            throw BackendError.invalidResponse
        }
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw BackendError.invalidResponse }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(configuration.appKey, forHTTPHeaderField: "x-app-key")
        request.setValue("application/json", forHTTPHeaderField: "accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
        switch http.statusCode {
        case 200: break
        case 401: throw BackendError.unauthorized
        case 429: throw BackendError.rateLimited
        default: throw BackendError.server(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw BackendError.invalidResponse
        }
    }
}

/// ISO 8601 時間：後端 toISOString 有毫秒（…000Z），TDX 原始時間有時區（+08:00）沒有毫秒。
enum ISODate {
    static func parse(_ text: String?) -> Date? {
        guard let text else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
