import Foundation
@testable import YiBuDa

@MainActor
final class FakeLiveActivityController: LiveActivityControlling {
    struct StartError: Error {}

    var areActivitiesEnabled = true
    var shouldFailToStart = false
    private(set) var startedAttributes: NavigationActivityAttributes?
    private(set) var states: [NavigationActivityAttributes.ContentState] = []
    private(set) var endCount = 0

    var isRunning: Bool { startedAttributes != nil }

    func start(attributes: NavigationActivityAttributes, state: NavigationActivityAttributes.ContentState) throws {
        if shouldFailToStart { throw StartError() }
        startedAttributes = attributes
        states.append(state)
    }

    func update(_ state: NavigationActivityAttributes.ContentState) async {
        guard isRunning else { return }
        states.append(state)
    }

    func end(finalState: NavigationActivityAttributes.ContentState?) async {
        guard isRunning else { return }
        startedAttributes = nil
        endCount += 1
    }
}
