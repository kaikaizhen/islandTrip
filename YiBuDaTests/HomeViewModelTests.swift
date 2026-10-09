import Foundation
import Testing
@testable import YiBuDa

@MainActor
struct HomeViewModelTests {
    let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    func makeSUT(
        liveActivity: FakeLiveActivityController = FakeLiveActivityController(),
        notifications: FakeNotificationScheduler = FakeNotificationScheduler(permission: .authorized)
    ) -> HomeViewModel {
        let now = fixedNow
        return HomeViewModel(script: .phase0, liveActivity: liveActivity, notifications: notifications, now: { now })
    }

    // MARK: 模擬導航

    @Test func startShowsFirstStepAndStartsSimulatedActivity() async {
        let liveActivity = FakeLiveActivityController()
        let sut = makeSUT(liveActivity: liveActivity)

        await sut.start()

        #expect(sut.status == .running(stepIndex: 0))
        #expect(sut.currentStep?.detail == "120 公尺後右轉")
        #expect(sut.currentStep?.updatedAt == fixedNow)
        #expect(liveActivity.startedAttributes?.isSimulated == true)
        #expect(liveActivity.states.count == 1)
        #expect(sut.notice == nil)
    }

    @Test func startTwiceDoesNotStartSecondActivity() async {
        let liveActivity = FakeLiveActivityController()
        let sut = makeSUT(liveActivity: liveActivity)

        await sut.start()
        await sut.start()

        #expect(liveActivity.states.count == 1)
    }

    @Test func advanceUpdatesActivityInOrder() async {
        let liveActivity = FakeLiveActivityController()
        let sut = makeSUT(liveActivity: liveActivity)

        await sut.start()
        await sut.advance()

        #expect(sut.status == .running(stepIndex: 1))
        #expect(liveActivity.states.map(\.distanceMeters) == [120, 80])
    }

    @Test func primaryActionWalksWholeScriptThenEnds() async {
        let liveActivity = FakeLiveActivityController()
        let sut = makeSUT(liveActivity: liveActivity)
        #expect(sut.primaryActionTitle == "開始模擬導航")

        for _ in 0..<sut.script.count {
            await sut.performPrimaryAction()
        }
        #expect(sut.status == .running(stepIndex: sut.script.count - 1))
        #expect(sut.primaryActionTitle == "結束模擬")

        await sut.performPrimaryAction()

        #expect(sut.status == .idle)
        #expect(sut.currentStep == nil)
        #expect(liveActivity.endCount == 1)
        #expect(liveActivity.states.count == sut.script.count)
    }

    @Test func activitiesDisabledStillSimulatesInAppWithWarning() async {
        let liveActivity = FakeLiveActivityController()
        liveActivity.areActivitiesEnabled = false
        let sut = makeSUT(liveActivity: liveActivity)

        await sut.start()

        #expect(sut.status == .running(stepIndex: 0))
        #expect(sut.notice?.kind == .warning)
        #expect(liveActivity.isRunning == false)
    }

    @Test func activityStartFailureStillSimulatesInAppWithWarning() async {
        let liveActivity = FakeLiveActivityController()
        liveActivity.shouldFailToStart = true
        let sut = makeSUT(liveActivity: liveActivity)

        await sut.start()

        #expect(sut.status == .running(stepIndex: 0))
        #expect(sut.notice?.kind == .warning)
    }

    @Test func stopWhenIdleDoesNothing() async {
        let liveActivity = FakeLiveActivityController()
        let sut = makeSUT(liveActivity: liveActivity)

        await sut.stop()

        #expect(sut.notice == nil)
        #expect(liveActivity.endCount == 0)
    }

    // MARK: 測試通知

    @Test func authorizedSchedulesNotificationAfterDelay() async {
        let notifications = FakeNotificationScheduler(permission: .authorized)
        let sut = makeSUT(notifications: notifications)

        await sut.sendTestNotification()

        let scheduled = await notifications.scheduled
        #expect(scheduled.count == 1)
        #expect(scheduled.first?.1 == HomeViewModel.testNotificationDelay)
        #expect(scheduled.first?.0.title.contains("模擬") == true)
        #expect(sut.notice?.kind == .info)
    }

    @Test func notDeterminedRequestsPermissionThenSchedules() async {
        let notifications = FakeNotificationScheduler(permission: .notDetermined, grantOnRequest: true)
        let sut = makeSUT(notifications: notifications)

        await sut.sendTestNotification()

        #expect(await notifications.requestCount == 1)
        #expect(await notifications.scheduled.count == 1)
    }

    @Test func requestRejectedShowsWarningAndSchedulesNothing() async {
        let notifications = FakeNotificationScheduler(permission: .notDetermined, grantOnRequest: false)
        let sut = makeSUT(notifications: notifications)

        await sut.sendTestNotification()

        #expect(await notifications.scheduled.isEmpty)
        #expect(sut.notice?.kind == .warning)
    }

    @Test func deniedShowsWarningWithoutRequesting() async {
        let notifications = FakeNotificationScheduler(permission: .denied)
        let sut = makeSUT(notifications: notifications)

        await sut.sendTestNotification()

        #expect(await notifications.requestCount == 0)
        #expect(await notifications.scheduled.isEmpty)
        #expect(sut.notice?.kind == .warning)
    }

    @Test func scheduleFailureShowsWarning() async {
        let notifications = FakeNotificationScheduler(permission: .authorized, failToSchedule: true)
        let sut = makeSUT(notifications: notifications)

        await sut.sendTestNotification()

        #expect(sut.notice?.kind == .warning)
    }
}
