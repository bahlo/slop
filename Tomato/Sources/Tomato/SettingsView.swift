import SwiftUI
import TomatoCore

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Toggle(tr("Break reminders"), isOn: $model.settings.breakRemindersEnabled)
            Group {
                Stepper(value: minutes(\.workInterval), in: 5...180, step: 5) {
                    LabeledContent(tr("Remind after"), value: tr("%d min of work", Int(model.settings.workInterval / 60)))
                }
                Stepper(value: minutes(\.breakDuration), in: 1...60, step: 1) {
                    LabeledContent(tr("Break length"), value: tr("%d min", Int(model.settings.breakDuration / 60)))
                }
                Stepper(value: minutes(\.snoozeInterval), in: 1...30, step: 1) {
                    LabeledContent(tr("Snooze"), value: tr("%d min", Int(model.settings.snoozeInterval / 60)))
                }
            }
            .disabled(!model.settings.breakRemindersEnabled)
        }
        .padding(20)
        .frame(width: 360)
    }

    private func minutes(_ keyPath: WritableKeyPath<AppSettings, TimeInterval>) -> Binding<Int> {
        Binding(
            get: { Int(model.settings[keyPath: keyPath] / 60) },
            set: { model.settings[keyPath: keyPath] = TimeInterval($0 * 60) }
        )
    }
}
