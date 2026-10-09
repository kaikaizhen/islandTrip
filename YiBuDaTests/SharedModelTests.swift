import Foundation
import Testing
@testable import YiBuDa

struct ManeuverTests {
    @Test func everyManeuverHasDistinctArrowAndSpokenDescription() {
        let symbols = Maneuver.allCases.map(\.symbolName)
        #expect(Set(symbols).count == symbols.count)
        #expect(Maneuver.allCases.allSatisfy { !$0.accessibilityDescription.isEmpty })
    }
}

struct DistanceFormatterTests {
    @Test(arguments: [(120, "120 公尺", "120m"), (999, "999 公尺", "999m"), (1200, "1.2 公里", "1.2km")])
    func formatsMeters(meters: Int, long: String, compact: String) {
        #expect(DistanceFormatter.long(meters) == long)
        #expect(DistanceFormatter.compact(meters) == compact)
    }
}

struct SimulatedNavigationScriptTests {
    @Test func phase0StartsWithRequiredInstructionAndEndsAtStop() {
        let script = SimulatedNavigationScript.phase0
        let now = Date()

        #expect(script.state(at: 0, updatedAt: now)?.detail == "120 公尺後右轉")
        #expect(script.state(at: script.count - 1, updatedAt: now)?.maneuver == .arrive)
        #expect(script.state(at: script.count, updatedAt: now) == nil)
        #expect(script.state(at: -1, updatedAt: now) == nil)
    }

    @Test func contentStateRoundTripsThroughCodable() throws {
        let state = try #require(SimulatedNavigationScript.phase0.state(at: 0, updatedAt: Date(timeIntervalSince1970: 0)))
        let decoded = try JSONDecoder().decode(
            NavigationActivityAttributes.ContentState.self,
            from: JSONEncoder().encode(state)
        )
        #expect(decoded == state)
    }
}
