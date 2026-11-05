import Foundation

/// Totals are computed by clipping each entry's interval against a window,
/// which handles midnight-spanning entries and the running entry uniformly.
public enum Stats {
    /// An ISO 8601 calendar (weeks start Monday) in the given time zone.
    public static func isoCalendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = timeZone
        return calendar
    }

    public static func todayInterval(now: Date, calendar: Calendar) -> DateInterval {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    public static func weekInterval(now: Date, calendar: Calendar) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: now)
            ?? DateInterval(start: calendar.startOfDay(for: now), duration: 7 * 86_400)
    }

    public static func lastWeekInterval(now: Date, calendar: Calendar) -> DateInterval {
        let thisWeek = weekInterval(now: now, calendar: calendar)
        let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek.start)
            ?? thisWeek.start.addingTimeInterval(-7 * 86_400)
        return DateInterval(start: lastWeekStart, end: thisWeek.start)
    }

    /// Sum of the portions of `entries` that fall inside `window`.
    /// A running entry is treated as ending at `now`.
    public static func totalTracked(entries: [TimeEntry], in window: DateInterval, now: Date) -> TimeInterval {
        entries.reduce(0) { total, entry in
            let end = entry.end ?? now
            guard end > entry.start else { return total }
            let interval = DateInterval(start: entry.start, end: end)
            guard let overlap = interval.intersection(with: window) else { return total }
            return total + overlap.duration
        }
    }
}
