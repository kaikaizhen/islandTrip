import Foundation

/// 以 GPS 取得「目前位置」作為出發地。
struct GPSCurrentPlaceProvider: CurrentPlaceProviding {
    let location: any LocationProviding

    func currentPlace() async throws -> Place {
        let sample = try await location.currentLocation()
        return Place(
            id: "gps.current",
            name: "目前位置",
            subtitle: "定位誤差約 \(Int(sample.horizontalAccuracy.rounded())) 公尺",
            coordinate: sample.coordinate
        )
    }
}

/// 依設定切換 GPS 或模擬位置。
struct SettingsCurrentPlaceProvider: CurrentPlaceProviding {
    let settings: AppSettings
    let gps: any CurrentPlaceProviding
    let simulated: any CurrentPlaceProviding

    func currentPlace() async throws -> Place {
        switch await settings.locationSource {
        case .gps: try await gps.currentPlace()
        case .simulated: try await simulated.currentPlace()
        }
    }
}
