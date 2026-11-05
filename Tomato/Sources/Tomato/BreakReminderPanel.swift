import AppKit
import SwiftUI
import TomatoCore

/// Floating, non-activating panel for reminders and prompts. Needs no
/// permissions (unlike UserNotifications, which also crashes in unbundled
/// binaries), and can't be lost behind other windows.
final class FloatingPanelController {
    private var panel: NSPanel?

    func show<Content: View>(_ content: Content) {
        if panel == nil {
            let panel = NSPanel(
                contentRect: .zero,
                styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = true
            self.panel = panel
        }
        guard let panel else { return }
        let hosting = NSHostingView(rootView: content)
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
        panel.center()
        panel.orderFrontRegardless()
        NSSound(named: "Glass")?.play()
    }

    func hide() {
        panel?.orderOut(nil)
    }
}

struct BreakPanelView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            switch model.scheduler.phase {
            case .breakPending:
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.tint)
                Text(tr("Time for a break"))
                    .font(.title3.bold())
                Text(tr("You've been working for %d minutes.", minutes(model.settings.workInterval)))
                    .foregroundStyle(.secondary)
                HStack {
                    Button(tr("Snooze %d min", minutes(model.settings.snoozeInterval))) {
                        model.snoozeBreak()
                    }
                    Button(tr("Skip")) {
                        model.skipBreak()
                    }
                    Button(tr("Start Break (%d min)", minutes(model.settings.breakDuration))) {
                        model.beginBreak()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            case .breakOver:
                Image(systemName: "figure.walk.arrival")
                    .font(.system(size: 32))
                    .foregroundStyle(.tint)
                Text(tr("Break's over"))
                    .font(.title3.bold())
                Text(tr("Ready to get back to it?"))
                    .foregroundStyle(.secondary)
                HStack {
                    Button(tr("Dismiss")) {
                        model.dismissBreakOver()
                    }
                    Button(tr("Resume Tracking")) {
                        model.resumeFromBreak()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            default:
                // Panel is hidden in these phases; keep a stable size anyway.
                EmptyView()
            }
        }
        .padding(24)
        .frame(minWidth: 340)
    }

    private func minutes(_ seconds: TimeInterval) -> Int {
        Int(seconds / 60)
    }
}
