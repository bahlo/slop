import Foundation
import TomatoCore

/// Headless end-to-end checks over the core wiring, run via `--selftest`.
/// Works in any session (no GUI needed) — the always-available smoke check.
enum SelfTest {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func run() throws {
        func check(_ condition: Bool, _ label: String) throws {
            if !condition { throw Failure(description: label) }
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TomatoSelfTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // Store round-trip with a start/stop cycle.
        let store = EntryStore(directory: directory)
        var tracker = Tracker(entries: store.load())
        try check(tracker.entries.isEmpty, "fresh store is empty")
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        tracker.start(at: t0)
        try store.save(tracker.entries)
        var reloaded = Tracker(entries: store.load())
        try check(reloaded.isTracking, "open entry survives reload")
        reloaded.stop(at: t0.addingTimeInterval(3600))
        try store.save(reloaded.entries)
        try check(!Tracker(entries: store.load()).isTracking, "closed entry persists")

        // Stats over the fixture.
        let calendar = Stats.isoCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
        let now = t0.addingTimeInterval(2 * 3600)
        let today = Stats.totalTracked(
            entries: store.load(),
            in: Stats.todayInterval(now: now, calendar: calendar),
            now: now
        )
        try check(today == 3600, "today total is 1h")
        try check(DurationFormatter.hoursMinutes(today, locale: Locale(identifier: "en_US")) == "1:00", "label formats 1:00")

        // Scheduler scenario: work 45m → remind → break 15m → break over → resume.
        var scheduler = BreakScheduler(config: AppSettings())
        scheduler.trackingStarted(at: t0)
        try check(scheduler.poll(now: t0 + 44 * 60) == nil, "no reminder before 45m")
        try check(scheduler.poll(now: t0 + 45 * 60) == .remindBreak, "reminder at 45m")
        scheduler.startBreak(at: t0 + 45 * 60)
        try check(scheduler.breakRemaining(now: t0 + 50 * 60) == 10 * 60, "10m break left at 50m")
        try check(scheduler.poll(now: t0 + 60 * 60) == .breakOver, "break over at 60m")
        scheduler.trackingStarted(at: t0 + 61 * 60)
        try check(scheduler.phase == .working(anchor: t0 + 61 * 60), "resumed working")

        // Sleep/wake: a 30-minute lid-close counts as a break taken.
        var wakeScheduler = BreakScheduler(config: AppSettings())
        wakeScheduler.trackingStarted(at: t0)
        wakeScheduler.systemWoke(sleptFor: 30 * 60, at: t0 + 40 * 60)
        try check(wakeScheduler.phase == .working(anchor: t0 + 40 * 60), "long sleep re-anchors")
        try check(wakeScheduler.poll(now: t0 + 45 * 60) == nil, "no nag right after wake")
        try check(wakeScheduler.poll(now: t0 + 85 * 60) == .remindBreak, "reminder 45m after wake")

        // Menubar label: same-length time strings must render at identical
        // widths or the status item jitters every second.
        let widths = Set(
            ["0:00:00", "0:11:11", "0:20:41", "8:38:59"]
                .map { LabelRenderer.render(icon: "timer", text: $0).size.width }
        )
        try check(widths.count == 1, "label width is stable across digits (got \(widths))")
    }
}
