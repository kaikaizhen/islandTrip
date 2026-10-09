import Testing
@testable import YiBuDa

struct NavigationStateMachineTests {
    @Test func fullHappyPath() {
        var machine = NavigationStateMachine(walkToStopSteps: 2, walkToDestinationSteps: 1)
        let events: [(NavigationEvent, NavigationPhase)] = [
            (.start, .walkingToStop(step: 0)),
            (.nextStep, .walkingToStop(step: 1)),
            (.nextStep, .checkingBoardingSide),
            (.confirmedBoardingSide, .waitingAtStop),
            (.boarded(walkToDestinationSteps: 1), .onVehicle(approachingAlight: false)),
            (.approachingAlightStop, .onVehicle(approachingAlight: true)),
            (.alighted, .walkingToDestination(step: 0)),
            (.nextStep, .arrived),
            (.cancel, .idle),
        ]
        for (event, expected) in events {
            let accepted = machine.handle(event)
            #expect(accepted, "\(event) 應該被接受")
            #expect(machine.phase == expected)
        }
    }

    @Test func invalidEventsAreIgnored() {
        var machine = NavigationStateMachine(walkToStopSteps: 1, walkToDestinationSteps: 1)
        var accepted = machine.handle(.boarded(walkToDestinationSteps: 1))
        #expect(!accepted)
        accepted = machine.handle(.cancel)
        #expect(!accepted)
        #expect(machine.phase == .idle)

        machine.handle(.start)
        accepted = machine.handle(.alighted)
        #expect(!accepted, "還沒上車不能下車")
        accepted = machine.handle(.boarded(walkToDestinationSteps: 1))
        #expect(!accepted, "還沒確認站牌不能上車")
        accepted = machine.handle(.previousStep)
        #expect(!accepted, "第一步不能再往前")
        #expect(machine.phase == .walkingToStop(step: 0))
    }

    @Test func previousStepGoesBackIncludingFromBoardingSide() {
        var machine = NavigationStateMachine(walkToStopSteps: 2, walkToDestinationSteps: 0)
        machine.handle(.start)
        machine.handle(.nextStep)
        machine.handle(.nextStep)
        #expect(machine.phase == .checkingBoardingSide)

        let accepted = machine.handle(.previousStep)
        #expect(accepted)
        #expect(machine.phase == .walkingToStop(step: 1))
    }

    @Test func noWalkingStepsSkipsStraightThrough() {
        var machine = NavigationStateMachine(walkToStopSteps: 0, walkToDestinationSteps: 0)
        machine.handle(.start)
        #expect(machine.phase == .checkingBoardingSide)
        machine.handle(.confirmedBoardingSide)
        machine.handle(.boarded(walkToDestinationSteps: 0))
        machine.handle(.alighted)
        #expect(machine.phase == .arrived)
    }

    @Test func boardedEventUpdatesRemainingWalkSteps() {
        var machine = NavigationStateMachine(walkToStopSteps: 0, walkToDestinationSteps: 3)
        machine.handle(.start)
        machine.handle(.confirmedBoardingSide)
        machine.handle(.boarded(walkToDestinationSteps: 1))
        machine.handle(.alighted)
        machine.handle(.nextStep)
        #expect(machine.phase == .arrived)
    }

    @Test func cancelWorksFromAnyActivePhase() {
        var machine = NavigationStateMachine(walkToStopSteps: 1, walkToDestinationSteps: 1)
        machine.handle(.start)
        machine.handle(.nextStep)
        machine.handle(.confirmedBoardingSide)

        let accepted = machine.handle(.cancel)
        #expect(accepted)
        #expect(machine.phase == .idle)
    }
}
