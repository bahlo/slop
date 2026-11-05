import Foundation

/// Pure, poll-based break state machine (45/15 method by default).
/// Owns no timers: the app layer calls `poll(now:)` from its ticker and on
/// wake, and forwards user actions. All transitions take injected dates so
/// every path is unit-testable.
public struct BreakScheduler: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        /// Not tracking; no reminders.
        case idle
        /// Tracking since `anchor` (continuous-work reference point).
        case working(anchor: Date)
        /// Work interval elapsed; the reminder panel is up, still tracking.
        case breakPending(since: Date)
        /// On a break (tracking stopped by the app layer) since `start`.
        case onBreak(start: Date)
        /// Break duration elapsed; the resume panel is up.
        case breakOver(since: Date)
    }

    public enum Event: Sendable, Equatable {
        case remindBreak
        case breakOver
    }

    public var config: AppSettings
    public private(set) var phase: Phase = .idle
    public private(set) var suppressedUntil: Date?

    public init(config: AppSettings) {
        self.config = config
    }

    /// Remaining break time; nil unless on a break.
    public func breakRemaining(now: Date) -> TimeInterval? {
        guard case .onBreak(let start) = phase else { return nil }
        return max(0, config.breakDuration - now.timeIntervalSince(start))
    }

    // MARK: - Tracking lifecycle (driven by the app layer)

    /// Tracking began (manual start, resume after break, or app relaunch).
    /// Cancels any break in progress.
    public mutating func trackingStarted(at now: Date) {
        phase = .working(anchor: now)
        suppressedUntil = nil
    }

    /// Tracking stopped manually (not via "Start break").
    public mutating func trackingStopped(at now: Date) {
        phase = .idle
        suppressedUntil = nil
    }

    // MARK: - Polling

    /// Advances the machine against the clock; returns an event when the
    /// app should show a panel. Each event fires exactly once per episode.
    public mutating func poll(now: Date) -> Event? {
        guard config.breakRemindersEnabled else { return nil }
        switch phase {
        case .working(let anchor):
            if let suppressed = suppressedUntil, now < suppressed { return nil }
            guard now.timeIntervalSince(anchor) >= config.workInterval else { return nil }
            phase = .breakPending(since: now)
            return .remindBreak
        case .onBreak(let start):
            guard now.timeIntervalSince(start) >= config.breakDuration else { return nil }
            phase = .breakOver(since: now)
            return .breakOver
        case .idle, .breakPending, .breakOver:
            return nil
        }
    }

    // MARK: - Panel actions

    /// "Start break": the app layer stops the entry and calls this.
    public mutating func startBreak(at now: Date) {
        phase = .onBreak(start: now)
        suppressedUntil = nil
    }

    /// "Snooze": keep working, remind again after the snooze interval.
    public mutating func snooze(at now: Date) {
        guard case .breakPending = phase else { return }
        // Re-anchor so the work interval check passes again after the
        // suppression window rather than the machine re-firing instantly.
        phase = .working(anchor: now.addingTimeInterval(-config.workInterval))
        suppressedUntil = now.addingTimeInterval(config.snoozeInterval)
    }

    /// "Skip": no break; restart the work interval from now.
    public mutating func skipBreak(at now: Date) {
        guard case .breakPending = phase else { return }
        phase = .working(anchor: now)
        suppressedUntil = nil
    }

    /// Reminders were switched on or off. Either way, drop any reminder or
    /// break in progress and, if tracking, count the work interval from now —
    /// re-enabling must not fire at once for work done while it was off.
    public mutating func remindersToggled(isTracking: Bool, at now: Date) {
        isTracking ? trackingStarted(at: now) : trackingStopped(at: now)
    }

    /// "Dismiss" on the break-over panel: stay stopped.
    public mutating func dismissBreakOver() {
        guard case .breakOver = phase else { return }
        phase = .idle
    }

    // MARK: - Sleep/wake

    /// The machine ran wall-clock through system sleep. A sleep at least as
    /// long as the break duration counts as a break taken: while working (or
    /// with a reminder pending), re-anchor instead of nagging right away.
    /// Shorter sleeps keep the anchor — time asleep counts as work.
    public mutating func systemWoke(sleptFor: TimeInterval, at now: Date) {
        guard sleptFor >= config.breakDuration else { return }
        switch phase {
        case .working, .breakPending:
            phase = .working(anchor: now)
            suppressedUntil = nil
        case .onBreak:
            // Slept through the break; the next poll fires breakOver.
            break
        case .idle, .breakOver:
            break
        }
    }
}
