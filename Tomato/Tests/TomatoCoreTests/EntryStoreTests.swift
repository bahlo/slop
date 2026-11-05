import Foundation
import Testing
@testable import TomatoCore

private func makeTempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("TomatoTests-\(UUID().uuidString)", isDirectory: true)
    return url
}

@Suite struct EntryStoreTests {
    @Test func loadFromMissingFileReturnsEmpty() {
        let store = EntryStore(directory: makeTempDirectory())
        #expect(store.load() == [])
    }

    @Test func roundTrip() throws {
        let store = EntryStore(directory: makeTempDirectory())
        let entries = [
            TimeEntry(start: Date(timeIntervalSince1970: 1_000), end: Date(timeIntervalSince1970: 2_000)),
            TimeEntry(start: Date(timeIntervalSince1970: 3_000.5)),
        ]
        try store.save(entries)
        let loaded = store.load()
        #expect(loaded == entries)
        #expect(loaded[1].isRunning)
    }

    @Test func saveOverwritesAtomically() throws {
        let store = EntryStore(directory: makeTempDirectory())
        try store.save([TimeEntry(start: Date(timeIntervalSince1970: 1))])
        let second = [TimeEntry(start: Date(timeIntervalSince1970: 2), end: Date(timeIntervalSince1970: 3))]
        try store.save(second)
        #expect(store.load() == second)
    }

    @Test func corruptFileIsQuarantinedAndTreatedAsEmpty() throws {
        let directory = makeTempDirectory()
        let store = EntryStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json {{{".utf8).write(to: store.fileURL)

        #expect(store.load() == [])
        // Original file was moved aside, not deleted.
        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(!contents.contains("entries.json"))
        #expect(contents.contains { $0.hasPrefix("entries.json.corrupt-") })
        // Store is usable again after quarantine.
        try store.save([TimeEntry(start: Date(timeIntervalSince1970: 5))])
        #expect(store.load().count == 1)
    }

    @Test func decodesWholeSecondDates() throws {
        let directory = makeTempDirectory()
        let store = EntryStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = """
        {"version":1,"entries":[{"id":"3B62BF20-0000-0000-0000-000000000000","start":"2026-07-10T08:00:00Z"}]}
        """
        try Data(json.utf8).write(to: store.fileURL)
        let loaded = store.load()
        #expect(loaded.count == 1)
        #expect(loaded[0].isRunning)
    }

    @Test func sanitizeClosesAllButLatestRunningEntry() {
        let entries = [
            TimeEntry(start: Date(timeIntervalSince1970: 100)),
            TimeEntry(start: Date(timeIntervalSince1970: 300)),
            TimeEntry(start: Date(timeIntervalSince1970: 200)),
        ]
        let now = Date(timeIntervalSince1970: 1_000)
        let (repaired, closed) = EntryStore.sanitize(entries, now: now)
        #expect(closed == 2)
        // Latest-started entry keeps running; the others are closed at now.
        #expect(repaired.filter(\.isRunning).map(\.start) == [Date(timeIntervalSince1970: 300)])
        #expect(repaired[0].end == now)
        #expect(repaired[2].end == now)
    }

    @Test func sanitizeLeavesValidEntriesUntouched() {
        let entries = [
            TimeEntry(start: Date(timeIntervalSince1970: 100), end: Date(timeIntervalSince1970: 200)),
            TimeEntry(start: Date(timeIntervalSince1970: 300)),
        ]
        let (repaired, closed) = EntryStore.sanitize(entries, now: Date(timeIntervalSince1970: 999))
        #expect(closed == 0)
        #expect(repaired == entries)
    }

    @Test func loadRepairsConflictingFile() throws {
        let directory = makeTempDirectory()
        let store = EntryStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Hand-crafted illegal file: two running entries.
        let json = """
        {"version":1,"entries":[
          {"id":"AAAAAAAA-0000-0000-0000-000000000000","start":"2026-07-10T08:00:00Z"},
          {"id":"BBBBBBBB-0000-0000-0000-000000000000","start":"2026-07-10T09:00:00Z"}
        ]}
        """
        try Data(json.utf8).write(to: store.fileURL)
        let loaded = store.load()
        #expect(loaded.filter(\.isRunning).count == 1)
        #expect(loaded.first { $0.isRunning }?.start == ISO8601DateFormatter().date(from: "2026-07-10T09:00:00Z"))
    }

    @Test func openEntrySurvivesReload() throws {
        let directory = makeTempDirectory()
        var tracker = Tracker(entries: EntryStore(directory: directory).load())
        let start = Date(timeIntervalSince1970: 10_000)
        tracker.start(at: start)
        try EntryStore(directory: directory).save(tracker.entries)

        // Simulate an app restart: fresh store + tracker from disk.
        let reloaded = Tracker(entries: EntryStore(directory: directory).load())
        #expect(reloaded.isTracking)
        #expect(reloaded.runningEntry?.start == start)
    }
}

@Suite struct TrackerTests {
    @Test func startCreatesRunningEntry() {
        var tracker = Tracker()
        let now = Date(timeIntervalSince1970: 100)
        let started = tracker.start(at: now)
        #expect(started)
        #expect(tracker.isTracking)
        #expect(tracker.runningEntry?.start == now)
    }

    @Test func doubleStartIsNoOp() {
        var tracker = Tracker()
        tracker.start(at: Date(timeIntervalSince1970: 100))
        let startedAgain = tracker.start(at: Date(timeIntervalSince1970: 200))
        #expect(!startedAgain)
        #expect(tracker.entries.count == 1)
    }

    @Test func stopClosesRunningEntry() {
        var tracker = Tracker()
        tracker.start(at: Date(timeIntervalSince1970: 100))
        let stopped = tracker.stop(at: Date(timeIntervalSince1970: 400))
        #expect(stopped)
        #expect(!tracker.isTracking)
        #expect(tracker.entries[0].end == Date(timeIntervalSince1970: 400))
        #expect(tracker.entries[0].duration(now: Date(timeIntervalSince1970: 999)) == 300)
    }

    @Test func stopWithoutRunningEntryIsNoOp() {
        var tracker = Tracker()
        let stopped = tracker.stop(at: Date(timeIntervalSince1970: 100))
        #expect(!stopped)
    }

    @Test func stopClampsEndToStart() {
        // A clock that went backwards must not produce a negative entry.
        var tracker = Tracker()
        tracker.start(at: Date(timeIntervalSince1970: 500))
        tracker.stop(at: Date(timeIntervalSince1970: 400))
        #expect(tracker.entries[0].end == Date(timeIntervalSince1970: 500))
    }
}

@Suite struct SettingsStoreTests {
    @Test func defaults() {
        let settings = SettingsStore(directory: makeTempDirectory()).load()
        #expect(settings.workInterval == 45 * 60)
        #expect(settings.breakDuration == 15 * 60)
        #expect(settings.snoozeInterval == 5 * 60)
    }

    @Test func roundTrip() throws {
        let store = SettingsStore(directory: makeTempDirectory())
        let custom = AppSettings(workInterval: 50 * 60, breakDuration: 10 * 60, snoozeInterval: 3 * 60)
        try store.save(custom)
        #expect(store.load() == custom)
    }

    @Test func corruptFileFallsBackToDefaults() throws {
        let directory = makeTempDirectory()
        let store = SettingsStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: store.fileURL)
        #expect(store.load() == AppSettings())
    }
}
