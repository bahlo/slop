import SwiftUI
import TomatoCore

/// Shown when a running timer looks forgotten: at app launch with an open
/// entry, or when a running timer crosses midnight. Offers to set the end
/// (with a picker clamped to >= start) or to keep the timer running.
struct StaleTimerView: View {
    let model: AppModel
    let entry: TimeEntry
    @ViewState private var end: Date

    init(model: AppModel, entry: TimeEntry) {
        self.model = model
        self.entry = entry
        _end = State(initialValue: max(Date(), entry.start))
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 32))
                .foregroundStyle(.tint)
            Text(tr("Still tracking?"))
                .font(.title3.bold())
            Text(tr("This timer has been running since %@. If you forgot to stop it, set an end time.", startedText))
                .foregroundStyle(.secondary)
                .frame(maxWidth: 300)
                .multilineTextAlignment(.center)

            DatePicker(
                tr("End"),
                selection: $end,
                in: entry.start...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .fixedSize()

            HStack {
                Button(tr("Keep Running")) {
                    model.keepStaleTimerRunning()
                }
                Button(tr("Stop at This Time")) {
                    model.stopStaleTimer(entryID: entry.id, end: end)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 340)
    }

    private var startedText: String {
        entry.start.formatted(date: .abbreviated, time: .shortened)
    }
}
