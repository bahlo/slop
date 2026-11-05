import SwiftUI
import TomatoCore

/// Entry list with per-row editing — the place to justify or correct entries
/// (e.g. forgot to stop at the end of the day).
struct EntriesView: View {
    let model: AppModel
    @ViewState private var editingEntry: TimeEntry?
    @ViewState private var editingCarryoverWeek: CarryoverWeek?

    /// Identifiable wrapper so a week start can drive `.sheet(item:)`.
    struct CarryoverWeek: Identifiable {
        let weekStart: Date
        var id: Date { weekStart }
    }

    var body: some View {
        Group {
            if model.tracker.entries.isEmpty {
                ContentUnavailableView(
                    tr("No Entries"),
                    systemImage: "clock",
                    description: Text(tr("Start tracking from the menubar or add an entry manually."))
                )
            } else {
                List {
                    ForEach(model.entriesByDay) { group in
                        Section(group.title) {
                            ForEach(group.entries) { entry in
                                EntryRow(entry: entry)
                                    .contentShape(Rectangle())
                                    .onTapGesture { editingEntry = entry }
                            }
                            // Below the entries: the list is newest-first, so
                            // Monday's carryover comes before anything tracked.
                            if let weekStart = group.carryoverWeekStart {
                                CarryoverRow(amount: model.carryover(forWeekStarting: weekStart))
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        editingCarryoverWeek = CarryoverWeek(weekStart: weekStart)
                                    }
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 440, minHeight: 320)
        .toolbar {
            Button(tr("Add Entry"), systemImage: "plus") {
                editingEntry = model.addManualEntry()
            }
        }
        .sheet(item: $editingEntry) { entry in
            EntryEditSheet(model: model, entry: entry)
        }
        .sheet(item: $editingCarryoverWeek) { week in
            CarryoverSheet(model: model, weekStart: week.weekStart)
        }
    }
}

private struct CarryoverRow: View {
    let amount: TimeInterval

    var body: some View {
        HStack {
            Text(tr("Carryover from last week"))
                .foregroundStyle(.secondary)
            Spacer()
            Text(DurationFormatter.signedHoursMinutes(amount))
                .monospacedDigit()
                .foregroundStyle(amount == 0 ? .tertiary : .secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct EntryRow: View {
    let entry: TimeEntry

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Text(timeRange)
                if entry.isRunning {
                    Text(tr("running"))
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.tint.opacity(0.2), in: Capsule())
                }
            }
            Spacer()
            Text(DurationFormatter.hoursMinutes(entry.duration(now: Date())))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var timeRange: String {
        let start = entry.start.formatted(date: .omitted, time: .shortened)
        guard let end = entry.end else { return tr("%@ – now", start) }
        return "\(start) – \(end.formatted(date: .omitted, time: .shortened))"
    }
}

/// Manual carryover from the week before, added to one week's counter.
/// Manual by design: a week's balance depends on vacation days etc. the app
/// can't know.
private struct CarryoverSheet: View {
    let model: AppModel
    let weekStart: Date
    @Environment(\.dismiss) private var dismiss
    @ViewState private var text: String

    init(model: AppModel, weekStart: Date) {
        self.model = model
        self.weekStart = weekStart
        let amount = model.carryover(forWeekStarting: weekStart)
        _text = State(initialValue: amount == 0 ? "" : DurationFormatter.signedHoursMinutes(amount))
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespaces) }
    private var isValid: Bool { trimmed.isEmpty || DurationFormatter.parseHoursMinutes(trimmed) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Carryover from last week"))
                .font(.headline)
            Text(tr(
                "Added to the counter of the week starting %@. Leave empty for 0:00.",
                weekStart.formatted(date: .abbreviated, time: .omitted)
            ))
            .font(.caption)
            .foregroundStyle(.secondary)

            Form {
                TextField(tr("Hours"), text: $text, prompt: Text(tr("1:30")))
            }

            if !isValid {
                Text(tr("Enter hours as H:MM, e.g. 1:30 or -0:45."))
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button(tr("Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(tr("Save")) {
                    model.setCarryover(
                        DurationFormatter.parseHoursMinutes(trimmed) ?? 0,
                        forWeekStarting: weekStart
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

private struct EntryEditSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    private let entryID: UUID
    @ViewState private var start: Date
    @ViewState private var end: Date?  // nil = running

    init(model: AppModel, entry: TimeEntry) {
        self.model = model
        self.entryID = entry.id
        _start = State(initialValue: entry.start)
        _end = State(initialValue: entry.end)
    }

    private var isValid: Bool { end.map { $0 >= start } ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Edit Entry"))
                .font(.headline)

            Form {
                DatePicker(tr("Start"), selection: $start, displayedComponents: [.date, .hourAndMinute])
                if end != nil {
                    DatePicker(
                        tr("End"),
                        selection: Binding(get: { end ?? Date() }, set: { end = $0 }),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                } else {
                    LabeledContent(tr("End")) {
                        // Entry is running; setting an end stops the timer.
                        Button(tr("Set Time")) { end = max(Date(), start) }
                    }
                }
            }

            if !isValid {
                Text(tr("End must not be before start."))
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button(tr("Delete"), role: .destructive) {
                    model.deleteEntry(id: entryID)
                    dismiss()
                }
                Spacer()
                Button(tr("Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(tr("Save")) {
                    if model.updateEntry(TimeEntry(id: entryID, start: start, end: end)) {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
