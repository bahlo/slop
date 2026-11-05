import Foundation

/// A manually entered adjustment (e.g. overtime or vacation from the week
/// before) added to one specific week's total, keyed to that week's start.
public struct WeekCarryover: Codable, Sendable, Equatable {
    public var weekStart: Date
    /// Seconds; negative means hours owed.
    public var amount: TimeInterval

    public init(weekStart: Date, amount: TimeInterval) {
        self.weekStart = weekStart
        self.amount = amount
    }
}

/// User-configurable durations, all in seconds, plus the per-week carryovers.
public struct AppSettings: Codable, Sendable, Equatable {
    /// Off turns the app into a plain time tracker: no break reminders.
    public var breakRemindersEnabled: Bool
    public var workInterval: TimeInterval
    public var breakDuration: TimeInterval
    public var snoozeInterval: TimeInterval
    public var carryovers: [WeekCarryover]

    public init(
        breakRemindersEnabled: Bool = true,
        workInterval: TimeInterval = 45 * 60,
        breakDuration: TimeInterval = 15 * 60,
        snoozeInterval: TimeInterval = 5 * 60,
        carryovers: [WeekCarryover] = []
    ) {
        self.breakRemindersEnabled = breakRemindersEnabled
        self.workInterval = workInterval
        self.breakDuration = breakDuration
        self.snoozeInterval = snoozeInterval
        self.carryovers = carryovers
    }

    /// A week with no stored carryover reads as 0:00.
    public func carryover(forWeekStarting weekStart: Date) -> TimeInterval {
        carryovers.first { $0.weekStart == weekStart }?.amount ?? 0
    }

    /// Setting 0 removes the entry — 0:00 is the default, so storing it
    /// would only clutter the settings file.
    public mutating func setCarryover(_ amount: TimeInterval, forWeekStarting weekStart: Date) {
        carryovers.removeAll { $0.weekStart == weekStart }
        if amount != 0 {
            carryovers.append(WeekCarryover(weekStart: weekStart, amount: amount))
        }
    }

    private enum CodingKeys: String, CodingKey {
        case breakRemindersEnabled, workInterval, breakDuration, snoozeInterval, carryovers
        /// Pre-per-week format: a single carryover for one week.
        case carryover
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Absent in files written before the setting existed.
        breakRemindersEnabled = try container.decodeIfPresent(Bool.self, forKey: .breakRemindersEnabled) ?? true
        workInterval = try container.decode(TimeInterval.self, forKey: .workInterval)
        breakDuration = try container.decode(TimeInterval.self, forKey: .breakDuration)
        snoozeInterval = try container.decode(TimeInterval.self, forKey: .snoozeInterval)
        if let list = try container.decodeIfPresent([WeekCarryover].self, forKey: .carryovers) {
            carryovers = list
        } else if let legacy = try container.decodeIfPresent(WeekCarryover.self, forKey: .carryover) {
            carryovers = [legacy]
        } else {
            carryovers = []
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(breakRemindersEnabled, forKey: .breakRemindersEnabled)
        try container.encode(workInterval, forKey: .workInterval)
        try container.encode(breakDuration, forKey: .breakDuration)
        try container.encode(snoozeInterval, forKey: .snoozeInterval)
        try container.encode(carryovers, forKey: .carryovers)
    }
}

/// JSON-file persistence for settings, next to the entries store.
/// Deliberately not UserDefaults: an unbundled `swift run` binary has no
/// bundle identifier, so its defaults domain would differ from the bundled app.
public final class SettingsStore {
    public let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("settings.json")
    }

    /// Returns defaults if the file is missing or unreadable.
    public func load() -> AppSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONCoding.makeDecoder().decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return settings
    }

    public func save(_ settings: AppSettings) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONCoding.makeEncoder().encode(settings)
        try data.write(to: fileURL, options: [.atomic])
    }
}
