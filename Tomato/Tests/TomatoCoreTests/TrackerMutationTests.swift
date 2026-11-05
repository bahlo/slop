import Foundation
import Testing
@testable import TomatoCore

private func at(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: seconds)
}

@Suite struct TrackerMutationTests {
    @Test func addValidEntry() throws {
        var tracker = Tracker()
        let entry = TimeEntry(start: at(100), end: at(200))
        try tracker.add(entry)
        #expect(tracker.entries.count == 1)
    }

    @Test func addRejectsEndBeforeStart() {
        var tracker = Tracker()
        #expect(throws: Tracker.MutationError.endBeforeStart) {
            try tracker.add(TimeEntry(start: at(200), end: at(100)))
        }
    }

    @Test func addRejectsSecondRunningEntry() {
        var tracker = Tracker()
        tracker.start(at: at(100))
        #expect(throws: Tracker.MutationError.secondRunningEntry) {
            try tracker.add(TimeEntry(start: at(200)))
        }
    }

    @Test func updateEditsTimes() throws {
        var tracker = Tracker()
        let entry = TimeEntry(start: at(100), end: at(200))
        try tracker.add(entry)
        var edited = entry
        edited.start = at(50)
        edited.end = at(300)
        try tracker.update(edited)
        #expect(tracker.entries[0].start == at(50))
        #expect(tracker.entries[0].end == at(300))
    }

    @Test func updateRejectsUnknownID() {
        var tracker = Tracker()
        #expect(throws: Tracker.MutationError.notFound) {
            try tracker.update(TimeEntry(start: at(100)))
        }
    }

    @Test func updateRejectsEndBeforeStart() throws {
        var tracker = Tracker()
        let entry = TimeEntry(start: at(100), end: at(200))
        try tracker.add(entry)
        var edited = entry
        edited.end = at(50)
        #expect(throws: Tracker.MutationError.endBeforeStart) {
            try tracker.update(edited)
        }
    }

    @Test func settingEndOnRunningEntryStopsIt() throws {
        var tracker = Tracker()
        tracker.start(at: at(100))
        var running = tracker.runningEntry!
        running.end = at(500)
        try tracker.update(running)
        #expect(!tracker.isTracking)
        #expect(tracker.entries[0].end == at(500))
    }

    @Test func editingRunningEntryStartKeepsItRunning() throws {
        var tracker = Tracker()
        tracker.start(at: at(100))
        var running = tracker.runningEntry!
        running.start = at(50)
        try tracker.update(running)
        #expect(tracker.isTracking)
        #expect(tracker.runningEntry?.start == at(50))
    }

    @Test func clearingEndRejectedWhenAnotherEntryRuns() throws {
        var tracker = Tracker()
        let closed = TimeEntry(start: at(100), end: at(200))
        try tracker.add(closed)
        tracker.start(at: at(300))
        var reopened = closed
        reopened.end = nil
        #expect(throws: Tracker.MutationError.secondRunningEntry) {
            try tracker.update(reopened)
        }
    }

    @Test func deleteRemovesEntry() throws {
        var tracker = Tracker()
        let entry = TimeEntry(start: at(100), end: at(200))
        try tracker.add(entry)
        tracker.delete(id: entry.id)
        #expect(tracker.entries.isEmpty)
    }

    @Test func deleteRunningEntryStopsTracking() {
        var tracker = Tracker()
        tracker.start(at: at(100))
        tracker.delete(id: tracker.runningEntry!.id)
        #expect(!tracker.isTracking)
    }
}
