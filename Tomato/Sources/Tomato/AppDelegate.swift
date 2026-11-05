import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menubar-only. Required for the unbundled `swift run` binary, which
        // has no Info.plist to declare LSUIElement.
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = Self.makeMainMenu()

        menuBar = MenuBarController(model: .shared)

        // A timer that survived a relaunch was likely forgotten; ask now.
        AppModel.shared.promptIfRunningAtLaunch()

        // Sleep/wake drive the break scheduler's re-anchoring and keep the
        // menubar label from going stale. NSWorkspace delivers these on main.
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self, selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification, object: nil
        )
        center.addObserver(
            self, selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification, object: nil
        )
    }

    @objc private func systemWillSleep(_ notification: Notification) {
        AppModel.shared.systemWillSleep()
    }

    @objc private func systemDidWake(_ notification: Notification) {
        AppModel.shared.systemDidWake()
    }

    /// Without a SwiftUI App there is no automatic main menu; provide the
    /// minimum so ⌘Q works globally and text fields get cut/copy/paste.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Tomato", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        return main
    }
}
