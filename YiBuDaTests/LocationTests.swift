import Foundation
import Testing
@testable import YiBuDa

/// 測試用位置：可指定回傳位置、錯誤，或一串導航中的更新。
struct FakeLocationProvider: LocationProviding {
    var result: Result<LocationSample, LocationError> = .success(
        LocationSample(coordinate: Coordinate(latitude: 22.6273, longitude: 120.3014), horizontalAccuracy: 8, timestamp: .now))
    var updates: [LocationSample] = []

    func currentLocation() async throws -> LocationSample { try result.get() }

    func liveUpdates() -> AsyncThrowingStream<LocationSample, Error> {
        AsyncThrowingStream { continuation in
            updates.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }
}

struct FailingCurrentPlace: CurrentPlaceProviding {
    var error: LocationError
    func currentPlace() async throws -> Place { throw error }
}

@MainActor
struct OriginTests {
    let mock = MockTransportProvider()

    @Test func gpsOriginShowsAccuracy() async {
        let sut = HomeViewModel(places: mock, favorites: mock,
                                currentPlace: GPSCurrentPlaceProvider(location: FakeLocationProvider()))
        await sut.load()
        #expect(sut.origin?.name == "目前位置")
        #expect(sut.origin?.subtitle == "定位誤差約 8 公尺")
        #expect(sut.originProblem == nil)
    }

    @Test func deniedPermissionExplainsAndAllowsManualOrigin() async {
        let sut = HomeViewModel(places: mock, favorites: mock, currentPlace: FailingCurrentPlace(error: .denied))
        await sut.load()
        #expect(sut.origin == nil)
        #expect(sut.originProblem?.contains("定位權限") == true)
        #expect(!sut.canSearchBuses)

        sut.setManualOrigin(MockTransitFixture.favorites[0])
        sut.select(MockTransitFixture.taipeiMainStation)
        #expect(sut.originProblem == nil)
        #expect(sut.isUsingManualOrigin)
        #expect(sut.canSearchBuses)
    }

    @Test func manualOriginIsNotOverwrittenByRefresh() async {
        let sut = HomeViewModel(places: mock, favorites: mock,
                                currentPlace: GPSCurrentPlaceProvider(location: FakeLocationProvider()))
        sut.setManualOrigin(MockTransitFixture.favorites[1])
        await sut.refreshOrigin()
        #expect(sut.origin == MockTransitFixture.favorites[1])

        await sut.useCurrentLocation()
        #expect(sut.origin?.name == "目前位置")
        #expect(!sut.isUsingManualOrigin)
    }

    @Test func timeoutGivesRetryAdvice() async {
        let sut = HomeViewModel(places: mock, favorites: mock, currentPlace: FailingCurrentPlace(error: .timeout))
        await sut.load()
        #expect(sut.originProblem?.contains("手動輸入") == true)
    }
}

@MainActor
struct LocationSourceTests {
    func makeDefaults() -> UserDefaults {
        let name = "test.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test func defaultsToSimulatedWhileTransitIsMock() {
        #expect(AppSettings(defaults: makeDefaults()).locationSource == .simulated)
    }

    @Test func choiceIsRemembered() {
        let defaults = makeDefaults()
        AppSettings(defaults: defaults).locationSource = .gps
        #expect(AppSettings(defaults: defaults).locationSource == .gps)
    }

    @Test func providerFollowsSetting() async throws {
        let settings = AppSettings(defaults: makeDefaults())
        let sut = SettingsCurrentPlaceProvider(settings: settings,
                                               gps: GPSCurrentPlaceProvider(location: FakeLocationProvider()),
                                               simulated: MockTransportProvider())
        #expect(try await sut.currentPlace().name == "目前位置（模擬）")
        settings.locationSource = .gps
        #expect(try await sut.currentPlace().name == "目前位置")
    }
}
