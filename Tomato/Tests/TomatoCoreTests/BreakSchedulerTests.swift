import Foundation
import Testing
@testable import TomatoCore

private func at(_ minutes: Double) -> Date {
    Date(timeIntervalSince1970: minutes * 60)
}

private func makeScheduler() -> BreakScheduler {
    BreakScheduler(config: AppSettings())  // 45 work / 15 break / 5 snooze
}

@Suite struct BreakSchedulerTests {
    @Test func noReminderWhileIdle() {
        var scheduler = makeScheduler()
        #expect(scheduler.poll(now: at(1000)) == nil)
        #expect(scheduler.phase == .idle)
    }

    @Test func remindsAfterWorkInterval() {
        var scheduler = makeScheduler()
        scheduler.trackingStarted(at: at(0))
        #expect(scheduler.poll(now: at(44)) == nil)
        #expect(scheduler.poll(now: at(45)) == .remindBreak)
        #expect(scheduler.phase == .breakPending(since: at(45)))
        // Fires only once while pending.
        #expect(scheduler.poll(now: at(46)) == nil)
    }

    @Test func manualStopResetsToIdle() {
        var scheduler = makeScheduler()
        scheduler.trackingStarted(at: at(0))
        scheduler.trackingStopped(at: at(30))
        #expect(scheduler.phase == .idle)
        #expect(scheduler.poll(now: at(100)) == nil)
    }

    @Test func snoozeRemindsAgainAfterSnoozeInterval() {
        var scheduler = makeScheduler()
        scheduler.trackingStarted(at: at(0))
        #expect(scheduler.poll(now: at(45)) == .remindBreak)
        scheduler.snooze(at: at(45))
        #expect(scheduler.poll(now: at(46)) == nil)
        #expect(scheduler.poll(now: at(49.9)) == nil)
        #expect(scheduler.poll(now: at(50)) == .remindBreak)
    }

    @Test func skipRestartsWorkInterval() {
        var scheduler = makeScheduler()
        scheduler.trackingStarted(at: at(0))
        _ = scheduler.poll(now: at(45))
        scheduler.skipBreak(at: at(45))
        #expect(scheduler.phase == .working(anchor: at(45)))
        #expect(scheduler.poll(now: at(89)) == nil)
        #expect(scheduler.poll(now: at(90)) == .remindBreak)
    }

    @Test func fullBreakCycle() {
        var scheduler = makeScheduler()
        scheduler.trackingStarted(at: at(0))
        #expect(scheduler.poll(now: at(45)) == .remindBreak)
        scheduler.startBreak(at: at(45))
        #expect(scheduler.phase == .onBreak(start: at(45)))
        #expect(scheduler.breakRemaining(now: at(50)) == TimeInterval(10 * 60))
        #expect(scheduler.poll(now: at(59)) == nil)
        #expect(scheduler.poll(now: at(60)) == .breakOver)
        #expect(scheduler.phase == .breakOver(since: at(60)))
        // Fires only once.
        #expect(scheduler.poll(now: at(61)) == nil)
        // Resume: app starts tracking again.
        scheduler.trackingStarted(at: at(61))
        #expect(scheduler.phase == .working(anchor: at(61)))
    }

    @Test func dismissBreakOverGoesIdle() {
        var scheduler = makeScheduler()
        scheduler.trackingStarted(at: at(0))
        _ = scheduler.poll(now: at(45))
        scheduler.startBreak(at: at(45))
        _ = scheduler.poll(now: at(60))
        scheduler.dismissBreakOver()
        #expect(scheduler.phase == .idle)
        #expect(scheduler.poll(now: at(200)) == nil)
    }

    @Test func manualStartDuringBreakCancelsBreak() {
        var scheduler = makeScheduler()
        scheduler.trackingStarted(at: at(0))
        _ = scheduler.poll(now: at(45))
        scheduler.startBreak(at: at(45))
        // User starts tracking mid-break from the menu.
        scheduler.trackingStarted(at: at(50))
        #expect(scheduler.phase == .working(anchor: at(50)))
        #expect(scheduler.poll(now: at(60)) == nil)
        #expect(scheduler.poll(now: at(95)) == .remindBreak)
    }

    @Test func breakRemainingClampsToZeroAndIsNilOffBreak() {
        var scheduler = makeScheduler()
        #expect(scheduler.breakRemaining(now: at(0)) == nil)
        scheduler.trackingStarted(at: at(0))
        _ = scheduler.poll(now: at(45))
        scheduler.startBreak(at: at(45))
        #expect(scheduler.breakRemaining(now: at(90)) == TimeInterval(0))
    }

    @Test func longSleepWhileWorkingReanchors() {
        var scheduler = makeScheduler()
        scheduler.trackingStarted(at: at(0))
        _ = scheduler.poll(now: at(30))
        // Machine slept 20 minutes (>= 15 min break) from minute 30 to 50.
        scheduler.systemWoke(sleptFor: 20 * 60, at: at(50))
        #expect(scheduler.phase == .working(anchor: at(50)))
        #expect(scheduler.poll(now: at(94)) == nil)
        #expect(scheduler.poll(now: at(95)) == .remindBreak)
    }

    @Test func shortSleepKeepsAnchor() {
        var scheduler = makeScheduler()
        scheduler.trackingStarted(at: at(0))
        scheduler.systemWoke(sleptFor: 5 * 60, at: at(40))
        #expect(scheduler.phase == .working(anchor: at(0)))
        #expect(scheduler.poll(now: at(45)) == .remindBreak)
    }

    @Test func longSleepWhilePendingReanchors() {
        var scheduler = makeScheduler()
        scheduler.trackingStarted(at: at(0))
        #expect(scheduler.poll(now: at(45)) == .remindBreak)
        scheduler.systemWoke(sleptFor: 30 * 60, at: at(75))
        #expect(scheduler.phase == .working(anchor: at(75)))
    }

    @Test func sleepThroughBreakFiresBreakOverOnNextPoll() {
        var scheduler = makeScheduler()
        scheduler.trackingStarted(at: at(0))
        _ = scheduler.poll(now: at(45))
        scheduler.startBreak(at: at(45))
        scheduler.systemWoke(sleptFor: 30 * 60, at: at(75))
        #expect(scheduler.poll(now: at(75)) == .breakOver)
    }

    @Test func configurableIntervalsAreRespected() {
        var scheduler = BreakScheduler(config: AppSettings(
            workInterval: 25 * 60, breakDuration: 5 * 60, snoozeInterval: 2 * 60
        ))
        scheduler.trackingStarted(at: at(0))
        #expect(scheduler.poll(now: at(24)) == nil)
        #expect(scheduler.poll(now: at(25)) == .remindBreak)
        scheduler.startBreak(at: at(25))
        #expect(scheduler.poll(now: at(30)) == .breakOver)
    }

    @Test func noRemindersWhenDisabled() {
        var scheduler = BreakScheduler(config: AppSettings(breakRemindersEnabled: false))
        scheduler.trackingStarted(at: at(0))
        #expect(scheduler.poll(now: at(45)) == nil)
        #expect(scheduler.poll(now: at(500)) == nil)
    }

    @Test func disablingMidBreakDropsTheBreak() {
        var scheduler = makeScheduler()
        scheduler.trackingStarted(at: at(0))
        _ = scheduler.poll(now: at(45))
        scheduler.startBreak(at: at(45))
        scheduler.config.breakRemindersEnabled = false
        scheduler.remindersToggled(isTracking: false, at: at(50))
        #expect(scheduler.phase == .idle)
        #expect(scheduler.breakRemaining(now: at(50)) == nil)
        #expect(scheduler.poll(now: at(60)) == nil)
    }

    @Test func reenablingCountsWorkFromNow() {
        var scheduler = BreakScheduler(config: AppSettings(breakRemindersEnabled: false))
        scheduler.trackingStarted(at: at(0))
        #expect(scheduler.poll(now: at(100)) == nil)
        scheduler.config.breakRemindersEnabled = true
        scheduler.remindersToggled(isTracking: true, at: at(100))
        #expect(scheduler.poll(now: at(144)) == nil)
        #expect(scheduler.poll(now: at(145)) == .remindBreak)
    }
}
