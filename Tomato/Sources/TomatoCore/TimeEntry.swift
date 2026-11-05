import Foundation

/// A single tracked interval. `end == nil` means the entry is currently running.
public struct TimeEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var start: Date
    public var end: Date?

    public init(id: UUID = UUID(), start: Date, end: Date? = nil) {
        self.id = id
        self.start = start
        self.end = end
    }

    public var isRunning: Bool { end == nil }

    /// Elapsed duration, using `now` as the open end for a running entry.
    public func duration(now: Date) -> TimeInterval {
        max(0, (end ?? now).timeIntervalSince(start))
    }
}
