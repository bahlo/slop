import Foundation

/// JSON-file persistence for time entries. Writes are atomic; a corrupt file
/// is renamed aside and treated as empty rather than crashing the app.
public final class EntryStore {
    struct Envelope: Codable {
        var version: Int
        var entries: [TimeEntry]
    }

    static let currentVersion = 1

    public let fileURL: URL

    /// The store keeps its data in `entries.json` inside `directory`.
    /// The directory is created on first save.
    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("entries.json")
    }

    /// Default location: `~/Library/Application Support/Tomato/`, overridable
    /// via TOMATO_DATA_DIR so smoke tests run against a throwaway directory.
    public static func defaultDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["TOMATO_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tomato", isDirectory: true)
    }

    /// Loads all entries. A missing file yields `[]`. A file that fails to
    /// decode is renamed to `entries.json.corrupt-<uuid>` and `[]` is returned.
    /// A file violating the one-running-timer invariant is repaired (see
    /// `sanitize`) with an error printed to stderr.
    public func load() -> [TimeEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            let envelope = try JSONCoding.makeDecoder().decode(Envelope.self, from: data)
            let (entries, closed) = Self.sanitize(envelope.entries, now: Date())
            if closed > 0 {
                FileHandle.standardError.write(Data(
                    """
                    Tomato: error: \(fileURL.path) contained \(closed + 1) running entries, \
                    but only one timer may run at a time. Closed the \(closed) older one(s).\n
                    """.utf8
                ))
            }
            return entries
        } catch {
            let quarantine = fileURL.appendingPathExtension("corrupt-\(UUID().uuidString)")
            try? FileManager.default.moveItem(at: fileURL, to: quarantine)
            return []
        }
    }

    /// At most one entry may be running. If several are (hand-edited or
    /// conflicting file), keep the latest-started one running and close the
    /// others at `now`. Returns the repaired list and how many were closed.
    static func sanitize(_ entries: [TimeEntry], now: Date) -> (entries: [TimeEntry], closed: Int) {
        let running = entries.filter(\.isRunning)
        guard running.count > 1,
              let keep = running.max(by: { $0.start < $1.start })?.id
        else { return (entries, 0) }
        var repaired = entries
        for index in repaired.indices where repaired[index].isRunning && repaired[index].id != keep {
            repaired[index].end = max(now, repaired[index].start)
        }
        return (repaired, running.count - 1)
    }

    public func save(_ entries: [TimeEntry]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let envelope = Envelope(version: Self.currentVersion, entries: entries)
        let data = try JSONCoding.makeEncoder().encode(envelope)
        try data.write(to: fileURL, options: [.atomic])
    }
}
