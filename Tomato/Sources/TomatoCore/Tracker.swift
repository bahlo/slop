import Foundation

/// Pure start/stop rules over a list of entries. At most one entry may be
/// running at a time. Persistence is the caller's job (see `EntryStore`).
public struct Tracker: Sendable, Equatable {
    public private(set) var entries: [TimeEntry]

    public init(entries: [TimeEntry] = []) {
        self.entries = entries
    }

    public var runningEntry: TimeEntry? {
        entries.first { $0.isRunning }
    }

    public var isTracking: Bool { runningEntry != nil }

    /// Starts a new entry. No-op (returns false) if one is already running.
    @discardableResult
    public mutating func start(at now: Date) -> Bool {
        guard runningEntry == nil else { return false }
        entries.append(TimeEntry(start: now))
        return true
    }

    /// Closes the running entry. No-op (returns false) if none is running.
    @discardableResult
    public mutating func stop(at now: Date) -> Bool {
        guard let index = entries.firstIndex(where: { $0.isRunning }) else { return false }
        entries[index].end = max(now, entries[index].start)
        return true
    }

    // MARK: - Manual editing (justify / correct entries)

    public enum MutationError: Error, Equatable {
        case endBeforeStart
        case secondRunningEntry
        case notFound
    }

    /// Adds a manual entry after validation.
    public mutating func add(_ entry: TimeEntry) throws {
        let normalized = try validated(entry, ignoringID: nil)
        entries.append(normalized)
    }

    /// Replaces the entry with the same id. Setting an end on the running
    /// entry stops it; clearing the end restarts it (only one may run).
    public mutating func update(_ entry: TimeEntry) throws {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else {
            throw MutationError.notFound
        }
        entries[index] = try validated(entry, ignoringID: entry.id)
    }

    public mutating func delete(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    private func validated(_ entry: TimeEntry, ignoringID: UUID?) throws -> TimeEntry {
        if let end = entry.end, end < entry.start {
            throw MutationError.endBeforeStart
        }
        if entry.isRunning, entries.contains(where: { $0.isRunning && $0.id != ignoringID }) {
            throw MutationError.secondRunningEntry
        }
        return entry
    }
}
