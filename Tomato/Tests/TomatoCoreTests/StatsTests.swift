import Foundation
import Testing
@testable import TomatoCore

private let berlin = TimeZone(identifier: "Europe/Berlin")!
private let calendar = Stats.isoCalendar(timeZone: berlin)

/// Builds a Date in Europe/Berlin local time.
private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
    calendar.date(from: DateComponents(
        year: year, month: month, day: day, hour: hour, minute: minute, second: second
    ))!
}

@Suite struct StatsTests {
    @Test func simpleEntryWithinDay() {
        let now = date(2026, 7, 10, 18)
        let entries = [TimeEntry(start: date(2026, 7, 10, 9), end: date(2026, 7, 10, 11, 30))]
        let total = Stats.totalTracked(entries: entries, in: Stats.todayInterval(now: now, calendar: calendar), now: now)
        #expect(total == 2.5 * 3600)
    }

    @Test func runningEntryCountsUpToNow() {
        let now = date(2026, 7, 10, 10)
        let entries = [TimeEntry(start: date(2026, 7, 10, 9))]
        let total = Stats.totalTracked(entries: entries, in: Stats.todayInterval(now: now, calendar: calendar), now: now)
        #expect(total == 3600)
    }

    @Test func midnightSpanningEntryIsClippedPerDay() {
        // Forgot to stop: 22:00 on the 9th until 02:00 on the 10th.
        let entry = TimeEntry(start: date(2026, 7, 9, 22), end: date(2026, 7, 10, 2))
        let onThe9th = Stats.totalTracked(
            entries: [entry],
            in: Stats.todayInterval(now: date(2026, 7, 9, 23), calendar: calendar),
            now: date(2026, 7, 10, 12)
        )
        let onThe10th = Stats.totalTracked(
            entries: [entry],
            in: Stats.todayInterval(now: date(2026, 7, 10, 12), calendar: calendar),
            now: date(2026, 7, 10, 12)
        )
        #expect(onThe9th == 2 * 3600)
        #expect(onThe10th == 2 * 3600)
    }

    @Test func entryOutsideWindowContributesNothing() {
        let now = date(2026, 7, 10, 12)
        let entries = [TimeEntry(start: date(2026, 7, 8, 9), end: date(2026, 7, 8, 17))]
        let total = Stats.totalTracked(entries: entries, in: Stats.todayInterval(now: now, calendar: calendar), now: now)
        #expect(total == 0)
    }

    @Test func invalidEntryEndBeforeStartIsIgnored() {
        let now = date(2026, 7, 10, 12)
        let entries = [TimeEntry(start: date(2026, 7, 10, 10), end: date(2026, 7, 10, 9))]
        let total = Stats.totalTracked(entries: entries, in: Stats.todayInterval(now: now, calendar: calendar), now: now)
        #expect(total == 0)
    }

    @Test func isoWeekStartsMonday() {
        // 2026-07-10 is a Friday; its ISO week is Mon 2026-07-06 .. Mon 2026-07-13.
        let week = Stats.weekInterval(now: date(2026, 7, 10, 12), calendar: calendar)
        #expect(week.start == date(2026, 7, 6))
        #expect(week.end == date(2026, 7, 13))
    }

    @Test func sundayBelongsToSameWeekAsPrecedingMonday() {
        // Sunday 2026-07-12 23:00 is still in the week of Mon 2026-07-06.
        let week = Stats.weekInterval(now: date(2026, 7, 12, 23), calendar: calendar)
        #expect(week.start == date(2026, 7, 6))
        // An entry worked the previous Friday counts toward this week.
        let entries = [TimeEntry(start: date(2026, 7, 10, 9), end: date(2026, 7, 10, 17))]
        let total = Stats.totalTracked(entries: entries, in: week, now: date(2026, 7, 12, 23))
        #expect(total == 8 * 3600)
    }

    @Test func weekTotalSumsMultipleDaysAndClipsAtBoundary() {
        let now = date(2026, 7, 8, 12)  // Wednesday
        let week = Stats.weekInterval(now: now, calendar: calendar)
        let entries = [
            // Sunday 23:00 → Monday 01:00 spans the week boundary: 1h counts.
            TimeEntry(start: date(2026, 7, 5, 23), end: date(2026, 7, 6, 1)),
            TimeEntry(start: date(2026, 7, 7, 9), end: date(2026, 7, 7, 17)),
            TimeEntry(start: date(2026, 7, 8, 9)),  // running, 3h so far
        ]
        let total = Stats.totalTracked(entries: entries, in: week, now: now)
        #expect(total == (1 + 8 + 3) * 3600)
    }

    @Test func springDSTTransitionDayIs23Hours() {
        // Sun 2026-03-29: clocks jump 02:00 → 03:00 in Berlin.
        let day = Stats.todayInterval(now: date(2026, 3, 29, 12), calendar: calendar)
        #expect(day.duration == 23 * 3600)
        // Tracking "all day" yields 23h, not 24h.
        let entries = [TimeEntry(start: day.start, end: day.end)]
        #expect(Stats.totalTracked(entries: entries, in: day, now: day.end) == 23 * 3600)
    }

    @Test func autumnDSTTransitionDayIs25Hours() {
        // Sun 2026-10-25: clocks fall back 03:00 → 02:00 in Berlin.
        let day = Stats.todayInterval(now: date(2026, 10, 25, 12), calendar: calendar)
        #expect(day.duration == 25 * 3600)
    }
}

@Suite struct WeekCarryoverTests {
    private let thisWeekStart = Stats.weekInterval(now: date(2026, 7, 10, 12), calendar: calendar).start
    private let nextWeekStart = Stats.weekInterval(now: date(2026, 7, 13, 9), calendar: calendar).start

    @Test func eachWeekReadsItsOwnAmountDefaultingToZero() {
        var settings = AppSettings()
        settings.setCarryover(2 * 3600, forWeekStarting: thisWeekStart)
        settings.setCarryover(-30 * 60, forWeekStarting: nextWeekStart)
        #expect(settings.carryover(forWeekStarting: thisWeekStart) == TimeInterval(2 * 3600))
        #expect(settings.carryover(forWeekStarting: nextWeekStart) == TimeInterval(-30 * 60))
        let earlierWeek = thisWeekStart.addingTimeInterval(-7 * 86_400)
        #expect(settings.carryover(forWeekStarting: earlierWeek) == 0)
    }

    @Test func settingZeroRemovesTheStoredEntry() {
        var settings = AppSettings()
        settings.setCarryover(3600, forWeekStarting: thisWeekStart)
        settings.setCarryover(0, forWeekStarting: thisWeekStart)
        #expect(settings.carryovers.isEmpty)
    }

    @Test func weekStartSurvivesJSONRoundTrip() throws {
        var settings = AppSettings()
        settings.setCarryover(-30 * 60, forWeekStarting: thisWeekStart)
        let data = try JSONCoding.makeEncoder().encode(settings)
        let decoded = try JSONCoding.makeDecoder().decode(AppSettings.self, from: data)
        #expect(decoded.carryover(forWeekStarting: thisWeekStart) == TimeInterval(-30 * 60))
    }

    @Test func settingsWithoutCarryoverKeyStillDecode() throws {
        let data = Data(#"{"workInterval": 2700, "breakDuration": 900, "snoozeInterval": 300}"#.utf8)
        let decoded = try JSONCoding.makeDecoder().decode(AppSettings.self, from: data)
        #expect(decoded.carryovers.isEmpty)
        #expect(decoded.breakRemindersEnabled)
    }

    @Test func disabledBreakRemindersSurviveJSONRoundTrip() throws {
        let settings = AppSettings(breakRemindersEnabled: false)
        let data = try JSONCoding.makeEncoder().encode(settings)
        let decoded = try JSONCoding.makeDecoder().decode(AppSettings.self, from: data)
        #expect(decoded == settings)
    }

    @Test func legacySingleCarryoverKeyIsMigrated() throws {
        let json = """
        {
            "workInterval": 2700, "breakDuration": 900, "snoozeInterval": 300,
            "carryover": {"weekStart": "2026-07-05T22:00:00.000Z", "amount": 5400}
        }
        """
        let decoded = try JSONCoding.makeDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(decoded.carryover(forWeekStarting: thisWeekStart) == 5400)
    }
}

@Suite struct DurationFormatterTests {
    // Formatting follows the locale; tests pin it so they pass on any machine.
    private let en = Locale(identifier: "en_US")
    private let da = Locale(identifier: "da_DK")

    @Test func hoursMinutesEdgeCases() {
        #expect(DurationFormatter.hoursMinutes(0, locale: en) == "0:00")
        #expect(DurationFormatter.hoursMinutes(59, locale: en) == "0:00")
        #expect(DurationFormatter.hoursMinutes(60, locale: en) == "0:01")
        #expect(DurationFormatter.hoursMinutes(3599, locale: en) == "0:59")
        #expect(DurationFormatter.hoursMinutes(3600, locale: en) == "1:00")
        #expect(DurationFormatter.hoursMinutes(4980, locale: en) == "1:23")
        #expect(DurationFormatter.hoursMinutes(36_000, locale: en) == "10:00")
        #expect(DurationFormatter.hoursMinutes(-5, locale: en) == "0:00")
    }

    @Test func hoursMinutesSecondsEdgeCases() {
        #expect(DurationFormatter.hoursMinutesSeconds(0, locale: en) == "0:00:00")
        #expect(DurationFormatter.hoursMinutesSeconds(59, locale: en) == "0:00:59")
        #expect(DurationFormatter.hoursMinutesSeconds(60, locale: en) == "0:01:00")
        #expect(DurationFormatter.hoursMinutesSeconds(3599, locale: en) == "0:59:59")
        #expect(DurationFormatter.hoursMinutesSeconds(3600, locale: en) == "1:00:00")
        #expect(DurationFormatter.hoursMinutesSeconds(5025, locale: en) == "1:23:45")
        #expect(DurationFormatter.hoursMinutesSeconds(36_000, locale: en) == "10:00:00")
        #expect(DurationFormatter.hoursMinutesSeconds(-5, locale: en) == "0:00:00")
    }

    @Test func danishUsesPeriodSeparators() {
        #expect(DurationFormatter.hoursMinutes(4980, locale: da) == "1.23")
        // Floors like the English form — the raw format style would round
        // 3599s up to "1.00".
        #expect(DurationFormatter.hoursMinutes(3599, locale: da) == "0.59")
        #expect(DurationFormatter.hoursMinutesSeconds(5025, locale: da) == "1.23.45")
        #expect(DurationFormatter.hoursMinutesSeconds(0, locale: da) == "0.00.00")
        #expect(DurationFormatter.minutesSeconds(750, locale: da) == "12.30")
        #expect(DurationFormatter.signedHoursMinutes(-5400, locale: da) == "-1.30")
        #expect(DurationFormatter.signedHoursMinutesSeconds(-5025, locale: da) == "-1.23.45")
    }

    @Test func signedFormattingKeepsTheMinus() {
        #expect(DurationFormatter.signedHoursMinutes(5400, locale: en) == "1:30")
        #expect(DurationFormatter.signedHoursMinutes(-5400, locale: en) == "-1:30")
        #expect(DurationFormatter.signedHoursMinutes(0, locale: en) == "0:00")
        #expect(DurationFormatter.signedHoursMinutesSeconds(-5025, locale: en) == "-1:23:45")
        #expect(DurationFormatter.signedHoursMinutesSeconds(5025, locale: en) == "1:23:45")
    }

    @Test func parseHoursMinutesAcceptsSignedHoursAndMinutes() {
        #expect(DurationFormatter.parseHoursMinutes("1:30") == 5400)
        #expect(DurationFormatter.parseHoursMinutes("-0:45") == -2700)
        #expect(DurationFormatter.parseHoursMinutes("2") == 7200)
        #expect(DurationFormatter.parseHoursMinutes("-2") == -7200)
        #expect(DurationFormatter.parseHoursMinutes(" 0:05 ") == 300)
        #expect(DurationFormatter.parseHoursMinutes("10:00") == 36_000)
    }

    @Test func parseHoursMinutesAcceptsLocaleSeparators() {
        #expect(DurationFormatter.parseHoursMinutes("1.30") == 5400)
        #expect(DurationFormatter.parseHoursMinutes("-0.45") == -2700)
        #expect(DurationFormatter.parseHoursMinutes("1,30") == 5400)
        // Decimal hours are rejected, not misread as minutes.
        #expect(DurationFormatter.parseHoursMinutes("1,5") == nil)
        #expect(DurationFormatter.parseHoursMinutes("1.5") == nil)
    }

    @Test func parseHoursMinutesRejectsMalformedInput() {
        #expect(DurationFormatter.parseHoursMinutes("") == nil)
        #expect(DurationFormatter.parseHoursMinutes("-") == nil)
        #expect(DurationFormatter.parseHoursMinutes(":30") == nil)
        #expect(DurationFormatter.parseHoursMinutes("1:3") == nil)
        #expect(DurationFormatter.parseHoursMinutes("1:75") == nil)
        #expect(DurationFormatter.parseHoursMinutes("1:30:00") == nil)
        #expect(DurationFormatter.parseHoursMinutes("1h") == nil)
        #expect(DurationFormatter.parseHoursMinutes("--1:30") == nil)
    }

    @Test func minutesSecondsEdgeCases() {
        #expect(DurationFormatter.minutesSeconds(0, locale: en) == "0:00")
        #expect(DurationFormatter.minutesSeconds(59, locale: en) == "0:59")
        #expect(DurationFormatter.minutesSeconds(750, locale: en) == "12:30")
        #expect(DurationFormatter.minutesSeconds(15 * 60, locale: en) == "15:00")
        #expect(DurationFormatter.minutesSeconds(-1, locale: en) == "0:00")
    }
}
