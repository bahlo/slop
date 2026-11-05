import Foundation

/// Durations rendered via `Duration.TimeFormatStyle`, so separators follow
/// the locale ("1:23:45" in English, "1.23.45" in Danish). Values are floored
/// to the displayed granularity first — the style itself would round up.
public enum DurationFormatter {
    /// "1:23" — whole hours and minutes, minutes floor-rounded. Used for the
    /// stats rows and the carryover row.
    public static func hoursMinutes(_ seconds: TimeInterval, locale: Locale = .current) -> String {
        let totalMinutes = Int(max(0, seconds) / 60)
        return Duration.seconds(totalMinutes * 60)
            .formatted(.time(pattern: .hourMinute).locale(locale))
    }

    /// "1:23:45" — hours, minutes, seconds. Used for the menubar label.
    public static func hoursMinutesSeconds(_ seconds: TimeInterval, locale: Locale = .current) -> String {
        Duration.seconds(Int(max(0, seconds).rounded(.down)))
            .formatted(.time(pattern: .hourMinuteSecond).locale(locale))
    }

    /// "12:30" — minutes and seconds. Used for the break countdown.
    public static func minutesSeconds(_ seconds: TimeInterval, locale: Locale = .current) -> String {
        Duration.seconds(Int(max(0, seconds).rounded(.down)))
            .formatted(.time(pattern: .minuteSecond).locale(locale))
    }

    /// "1:30" or "-1:30" — like `hoursMinutes` but keeps the sign. Used for
    /// the carryover field, where hours owed are negative.
    public static func signedHoursMinutes(_ seconds: TimeInterval, locale: Locale = .current) -> String {
        (seconds < 0 ? "-" : "") + hoursMinutes(abs(seconds), locale: locale)
    }

    /// Like `hoursMinutesSeconds` but keeps the sign, for totals that a
    /// negative carryover can push below zero.
    public static func signedHoursMinutesSeconds(_ seconds: TimeInterval, locale: Locale = .current) -> String {
        (seconds < 0 ? "-" : "") + hoursMinutesSeconds(abs(seconds), locale: locale)
    }

    /// Parses user input in the `signedHoursMinutes` shape: "H:MM" or plain
    /// hours ("2"), optionally negative. The separator may be ":", ".", or
    /// "," so input matches whatever the user's locale displays. Requiring
    /// two-digit minutes keeps "1,5" (decimal hours) an error rather than a
    /// misread. Returns nil for anything else.
    public static func parseHoursMinutes(_ string: String) -> TimeInterval? {
        var input = string.trimmingCharacters(in: .whitespaces)
        var sign: TimeInterval = 1
        if input.hasPrefix("-") {
            sign = -1
            input.removeFirst()
        }
        let parts = input.split(
            omittingEmptySubsequences: false,
            whereSeparator: { ":.,".contains($0) }
        )
        guard let hours = Int(parts[0]), hours >= 0 else { return nil }
        switch parts.count {
        case 1:
            return sign * TimeInterval(hours) * 3600
        case 2:
            guard let minutes = Int(parts[1]), (0...59).contains(minutes), parts[1].count == 2
            else { return nil }
            return sign * (TimeInterval(hours) * 3600 + TimeInterval(minutes) * 60)
        default:
            return nil
        }
    }
}
