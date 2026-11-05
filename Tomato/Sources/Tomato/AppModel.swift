import AppKit
import Foundation
import Observation
import TomatoCore

/// Owns the tracker, stores, break scheduler, and the ticker that keeps the
/// menubar label fresh. All elapsed values derive from persisted wall-clock
/// timestamps, so restarts and sleep/wake self-correct on the next tick.
@Observable
final class AppModel {
    private let entryStore: EntryStore
    private let settingsStore: SettingsStore

    private(set) var tracker: Tracker
    private(set) var scheduler: BreakScheduler
    var settings: AppSettings {
        didSet {
            scheduler.config = settings
            if settings.breakRemindersEnabled != oldValue.breakRemindersEnabled {
                // Toggling off mid-break would otherwise leave the break
                // countdown (and its panel) running.
                scheduler.remindersToggled(isTracking: tracker.isTracking, at: Date())
                refresh()
                restartTicker()
            }
            try? settingsStore.save(settings)
        }
    }

    private(set) var labelText: String = "0:00:00"
    private(set) var iconName: String = "timer"
    private(set) var labelImage: NSImage = LabelRenderer.render(icon: "timer", text: "0:00:00")
    // Stored (not computed) so every ticker update reaches the open menu.
    private(set) var todayText: String = "0:00:00"
    private(set) var weekText: String = "0:00:00"
    private(set) var lastWeekText: String = "0:00:00"

    /// Shared instance: the SwiftUI scenes and the AppDelegate (sleep/wake
    /// notifications) must observe the same model.
    static let shared = AppModel()

    @ObservationIgnored private lazy var breakPanel = FloatingPanelController()
    @ObservationIgnored private lazy var stalePanel = FloatingPanelController()
    private var tickerTask: Task<Void, Never>?
    private var sleepStarted: Date?

    private struct StalePromptKey: Equatable {
        let entryID: UUID
        let day: Date
    }

    /// Prompt at most once per entry per day (re-prompts after the next
    /// midnight if the user chose to keep the timer running).
    @ObservationIgnored private var lastStalePrompt: StalePromptKey?

    init(directory: URL = EntryStore.defaultDirectory()) {
        let entryStore = EntryStore(directory: directory)
        self.entryStore = entryStore
        self.settingsStore = SettingsStore(directory: directory)
        let settings = settingsStore.load()
        self.settings = settings
        self.tracker = Tracker(entries: entryStore.load())
        self.scheduler = BreakScheduler(config: settings)
        if tracker.isTracking {
            // Resumed a still-open entry after a relaunch. The break clock
            // counts from now — the entry's past span may include a break.
            scheduler.trackingStarted(at: Date())
        }
        refresh()
        restartTicker()
    }

    var isTracking: Bool { tracker.isTracking }
    var isOnBreak: Bool {
        if case .onBreak = scheduler.phase { return true }
        return false
    }

    // MARK: - Actions

    func startTracking(now: Date = Date()) {
        guard tracker.start(at: now) else { return }
        scheduler.trackingStarted(at: now)
        persist()
        refresh(now: now)
        restartTicker()
    }

    func stopTracking(now: Date = Date()) {
        guard tracker.stop(at: now) else { return }
        scheduler.trackingStopped(at: now)
        persist()
        refresh(now: now)
        restartTicker()
    }

    func toggleTracking() {
        isTracking ? stopTracking() : startTracking()
    }

    // MARK: - Break flow (panel actions)

    /// "Start break": stop the entry (break time is never tracked) and count
    /// down the configured break duration.
    func beginBreak(now: Date = Date()) {
        breakPanel.hide()
        tracker.stop(at: now)
        scheduler.startBreak(at: now)
        persist()
        refresh(now: now)
        restartTicker()
    }

    func snoozeBreak(now: Date = Date()) {
        breakPanel.hide()
        scheduler.snooze(at: now)
    }

    func skipBreak(now: Date = Date()) {
        breakPanel.hide()
        scheduler.skipBreak(at: now)
    }

    func resumeFromBreak(now: Date = Date()) {
        breakPanel.hide()
        startTracking(now: now)
    }

    func dismissBreakOver() {
        breakPanel.hide()
        scheduler.dismissBreakOver()
        refresh()
    }

    // MARK: - Stale timer prompt

    /// Called from applicationDidFinishLaunching: an entry that survived a
    /// relaunch was likely forgotten — ask instead of silently resuming.
    func promptIfRunningAtLaunch(now: Date = Date()) {
        guard let entry = tracker.runningEntry else { return }
        showStalePrompt(for: entry, now: now)
    }

    /// Called from the ticker: a running timer that crossed midnight was
    /// likely forgotten at the end of the day.
    private func checkMidnightWrap(now: Date) {
        guard let entry = tracker.runningEntry else { return }
        let calendar = Stats.isoCalendar()
        guard entry.start < calendar.startOfDay(for: now) else { return }
        let key = StalePromptKey(entryID: entry.id, day: calendar.startOfDay(for: now))
        guard lastStalePrompt != key else { return }
        showStalePrompt(for: entry, now: now)
    }

    private func showStalePrompt(for entry: TimeEntry, now: Date) {
        lastStalePrompt = StalePromptKey(
            entryID: entry.id,
            day: Stats.isoCalendar().startOfDay(for: now)
        )
        stalePanel.show(StaleTimerView(model: self, entry: entry))
    }

    func stopStaleTimer(entryID: UUID, end: Date) {
        stalePanel.hide()
        guard var entry = tracker.entries.first(where: { $0.id == entryID }),
              entry.isRunning
        else { return }
        entry.end = end
        updateEntry(entry)
    }

    func keepStaleTimerRunning() {
        stalePanel.hide()
    }

    // MARK: - Sleep/wake

    func systemWillSleep(now: Date = Date()) {
        sleepStarted = now
    }

    func systemDidWake(now: Date = Date()) {
        let sleptFor = sleepStarted.map { now.timeIntervalSince($0) } ?? 0
        sleepStarted = nil
        scheduler.systemWoke(sleptFor: sleptFor, at: now)
        // Re-poll and repaint immediately: the label is stale after sleep and
        // a slept-through break should surface its panel right away.
        tick(now: now)
        restartTicker()
    }

    // MARK: - Stats

    func todayTotal(now: Date = Date()) -> TimeInterval {
        let calendar = Stats.isoCalendar()
        return Stats.totalTracked(
            entries: tracker.entries,
            in: Stats.todayInterval(now: now, calendar: calendar),
            now: now
        )
    }

    /// Tracked time this week plus this week's manual carryover. Can go
    /// negative when the carryover is hours owed.
    func weekTotal(now: Date = Date()) -> TimeInterval {
        let calendar = Stats.isoCalendar()
        let week = Stats.weekInterval(now: now, calendar: calendar)
        let tracked = Stats.totalTracked(entries: tracker.entries, in: week, now: now)
        return tracked + settings.carryover(forWeekStarting: week.start)
    }

    func carryover(forWeekStarting weekStart: Date) -> TimeInterval {
        settings.carryover(forWeekStarting: weekStart)
    }

    /// Manual by design: a week's balance depends on vacation days etc.
    /// that the app can't know.
    func setCarryover(_ amount: TimeInterval, forWeekStarting weekStart: Date) {
        settings.setCarryover(amount, forWeekStarting: weekStart)
        refresh()
    }

    /// Includes last week's carryover — the same number "This week" showed
    /// while that week was current.
    func lastWeekTotal(now: Date = Date()) -> TimeInterval {
        let calendar = Stats.isoCalendar()
        let week = Stats.lastWeekInterval(now: now, calendar: calendar)
        let tracked = Stats.totalTracked(entries: tracker.entries, in: week, now: now)
        return tracked + settings.carryover(forWeekStarting: week.start)
    }

    // MARK: - Label + ticker

    func refresh(now: Date = Date()) {
        let today = DurationFormatter.hoursMinutesSeconds(todayTotal(now: now))
        let week = DurationFormatter.signedHoursMinutesSeconds(weekTotal(now: now))
        if todayText != today { todayText = today }
        if weekText != week { weekText = week }
        let lastWeek = DurationFormatter.signedHoursMinutesSeconds(lastWeekTotal(now: now))
        if lastWeekText != lastWeek { lastWeekText = lastWeek }
        if let remaining = scheduler.breakRemaining(now: now) {
            setLabel(icon: "cup.and.saucer", text: DurationFormatter.minutesSeconds(remaining))
        } else {
            setLabel(icon: "timer", text: today)
        }
        // Sleep/wake and manual edits can move the scheduler out of a panel
        // phase without a panel action (e.g. an overnight sleep re-anchors
        // .breakPending to .working); don't leave the panel up rendering its
        // empty state.
        switch scheduler.phase {
        case .breakPending, .breakOver:
            break
        case .idle, .working, .onBreak:
            breakPanel.hide()
        }
    }

    private func setLabel(icon: String, text: String) {
        // Assign only on change so SwiftUI re-renders the label at most once
        // per visible transition.
        guard iconName != icon || labelText != text else { return }
        iconName = icon
        labelText = text
        labelImage = LabelRenderer.render(icon: icon, text: text)
    }

    /// The ticker runs for the app's lifetime; only its cadence changes.
    /// Restart it whenever tracking/break state flips so a long idle sleep
    /// doesn't swallow a state change.
    private func restartTicker() {
        tickerTask?.cancel()
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(for: .seconds(self.nextTickDelay(now: Date())))
                if Task.isCancelled { return }
                self.tick(now: Date())
            }
        }
    }

    /// Second granularity while tracking (h:mm:ss label) or on a break
    /// (m:ss countdown). When idle nothing counts up, so sleep until just
    /// past the next midnight — the moment the label must reset to 0:00:00.
    private func nextTickDelay(now: Date) -> TimeInterval {
        if isOnBreak { return 1 }
        if isTracking {
            let intoSecond = todayTotal(now: now).truncatingRemainder(dividingBy: 1)
            return max(0.05, 1 - intoSecond + 0.02)
        }
        let nextMidnight = Stats.todayInterval(now: now, calendar: Stats.isoCalendar()).end
        return max(1, nextMidnight.timeIntervalSince(now) + 0.1)
    }

    func tick(now: Date = Date()) {
        if scheduler.poll(now: now) != nil {
            // .remindBreak and .breakOver both surface the panel; its content
            // follows scheduler.phase.
            breakPanel.show(BreakPanelView(model: self))
        }
        checkMidnightWrap(now: now)
        refresh(now: now)
    }

    // MARK: - Manual editing

    struct DayGroup: Identifiable {
        let day: Date
        let title: String
        let entries: [TimeEntry]
        /// Set when this day starts a week (Monday): the group then carries
        /// that week's carryover row, below its entries — the list is
        /// newest-first, and the carryover comes before anything tracked.
        let carryoverWeekStart: Date?
        var id: Date { day }
    }

    /// Entries grouped by calendar day, newest first. Every week that appears
    /// gets its Monday group — the current week always, and past weeks even
    /// when nothing was tracked that Monday — so the carryover between weeks
    /// stays visible and editable.
    var entriesByDay: [DayGroup] {
        let calendar = Stats.isoCalendar()
        var groups = Dictionary(grouping: tracker.entries) { calendar.startOfDay(for: $0.start) }
        var weekStarts = Set(groups.keys.map { Stats.weekInterval(now: $0, calendar: calendar).start })
        weekStarts.insert(Stats.weekInterval(now: Date(), calendar: calendar).start)
        for weekStart in weekStarts where groups[weekStart] == nil {
            groups[weekStart] = []
        }
        return groups.keys.sorted(by: >).map { day in
            let title = if calendar.isDateInToday(day) {
                tr("Today")
            } else if calendar.isDateInYesterday(day) {
                tr("Yesterday")
            } else {
                day.formatted(date: .abbreviated, time: .omitted)
            }
            return DayGroup(
                day: day,
                title: title,
                entries: groups[day]!.sorted { $0.start > $1.start },
                carryoverWeekStart: weekStarts.contains(day) ? day : nil
            )
        }
    }

    /// Adds a closed one-hour entry ending now and returns it for editing.
    @discardableResult
    func addManualEntry(now: Date = Date()) -> TimeEntry? {
        let entry = TimeEntry(start: now.addingTimeInterval(-3600), end: now)
        guard (try? tracker.add(entry)) != nil else { return nil }
        syncAfterMutation(now: now)
        return entry
    }

    @discardableResult
    func updateEntry(_ entry: TimeEntry) -> Bool {
        guard (try? tracker.update(entry)) != nil else { return false }
        syncAfterMutation()
        return true
    }

    func deleteEntry(id: UUID) {
        tracker.delete(id: id)
        syncAfterMutation()
    }

    /// Editing can start or stop the running entry out from under the
    /// scheduler and ticker; bring both back in line with the tracker.
    private func syncAfterMutation(now: Date = Date()) {
        switch (tracker.isTracking, scheduler.phase) {
        case (false, .working), (false, .breakPending):
            scheduler.trackingStopped(at: now)
        case (true, .idle), (true, .onBreak), (true, .breakOver):
            scheduler.trackingStarted(at: now)
        default:
            break
        }
        persist()
        refresh(now: now)
        restartTicker()
    }

    // MARK: - Persistence

    private func persist() {
        do {
            try entryStore.save(tracker.entries)
        } catch {
            FileHandle.standardError.write(Data("Tomato: failed to save entries: \(error)\n".utf8))
        }
    }
}
