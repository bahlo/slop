import AppKit
import Observation
import SwiftUI
import TomatoCore

/// Owns the NSStatusItem and its NSMenu directly. SwiftUI's MenuBarExtra
/// rebuilds the whole menu whenever any content changes, which resets the
/// hover highlight every ticker second; updating NSMenuItem titles in place
/// leaves tracking state (and the highlight) alone.
final class MenuBarController: NSObject {
    private let model: AppModel
    private let statusItem: NSStatusItem

    private let toggleItem = NSMenuItem(title: tr("Start Tracking"), action: nil, keyEquivalent: "t")
    private let todayItem = NSMenuItem(title: tr("Today: %@", "0:00:00"), action: nil, keyEquivalent: "")
    private let weekItem = NSMenuItem(title: tr("This week: %@", "0:00:00"), action: nil, keyEquivalent: "")
    private let lastWeekItem = NSMenuItem(title: tr("Last week: %@", "0:00:00"), action: nil, keyEquivalent: "")

    private var entriesWindow: NSWindow?
    private var settingsWindow: NSWindow?

    init(model: AppModel) {
        self.model = model
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let menu = NSMenu()
        menu.autoenablesItems = false

        toggleItem.target = self
        toggleItem.action = #selector(toggleTracking)
        menu.addItem(toggleItem)

        menu.addItem(.separator())
        todayItem.isEnabled = false
        weekItem.isEnabled = false
        lastWeekItem.isEnabled = false
        menu.addItem(todayItem)
        menu.addItem(weekItem)
        menu.addItem(lastWeekItem)

        menu.addItem(.separator())
        let entriesItem = NSMenuItem(title: tr("Edit Entries…"), action: #selector(openEntries), keyEquivalent: "e")
        entriesItem.target = self
        // Settings/Quit get system icons; match them.
        entriesItem.image = NSImage(
            systemSymbolName: "pencil.and.list.clipboard",
            accessibilityDescription: nil
        )
        menu.addItem(entriesItem)
        let settingsItem = NSMenuItem(title: tr("Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: tr("Quit Tomato"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.toolTip = "Tomato"
        observeModel()
    }

    /// Re-render on every model change, re-registering observation each time
    /// (withObservationTracking is one-shot).
    private func observeModel() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeModel()
            }
        }
    }

    private func render() {
        statusItem.button?.image = model.labelImage
        statusItem.button?.setAccessibilityLabel(tr("Tomato: %@ tracked today", model.labelText))
        toggleItem.title = model.isTracking ? tr("Stop Tracking") : tr("Start Tracking")
        todayItem.title = tr("Today: %@", model.todayText)
        weekItem.title = tr("This week: %@", model.weekText)
        lastWeekItem.title = tr("Last week: %@", model.lastWeekText)
    }

    // MARK: - Actions

    @objc private func toggleTracking() {
        model.toggleTracking()
    }

    @objc private func openEntries() {
        if entriesWindow == nil {
            entriesWindow = makeWindow(title: tr("Tomato Entries"), content: EntriesView(model: model))
        }
        present(entriesWindow)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = makeWindow(title: tr("Tomato Settings"), content: SettingsView(model: model))
            window.styleMask.remove(.resizable)
            settingsWindow = window
        }
        present(settingsWindow)
    }

    private func makeWindow(title: String, content: some View) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = title
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        // Activate before ordering front: for an accessory app the plain
        // activate() request can be declined under cooperative activation
        // (macOS 14+), leaving the window behind the frontmost app.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
