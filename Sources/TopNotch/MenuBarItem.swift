import AppKit

/// The status item, and the only chrome TopNotch has outside the notch itself.
///
/// It exists because settings need somewhere to live: the app has no dock icon and no
/// window, so without this there is nowhere to turn launch-at-login off, and an app that
/// starts itself with no visible way to stop it is the kind people delete.
///
/// The menu is rebuilt from the real state every time it opens rather than kept in sync,
/// because the login-item registration can change behind our back in System Settings.
@MainActor
final class MenuBarItem: NSObject, NSMenuDelegate {

    private let item: NSStatusItem
    private let menu = NSMenu()
    private let onOpen: () -> Void

    private let openItem = NSMenuItem()
    private let launchItem = NSMenuItem()
    private let quitItem = NSMenuItem()

    init(onOpen: @escaping () -> Void) {
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.onOpen = onOpen
        super.init()

        item.button?.image = NSImage(
            systemSymbolName: "rectangle.topthird.inset.filled",
            accessibilityDescription: "TopNotch"
        )
        // A template image is the only thing that reads correctly against a light menu
        // bar, a dark one, and whatever wallpaper is behind a translucent one.
        item.button?.image?.isTemplate = true

        openItem.title = "Open TopNotch"
        openItem.target = self
        openItem.action = #selector(open)

        launchItem.target = self
        launchItem.action = #selector(toggleLaunchAtLogin)

        quitItem.title = "Quit TopNotch"
        quitItem.keyEquivalent = "q"
        quitItem.target = self
        quitItem.action = #selector(quit)

        menu.delegate = self
        menu.addItem(openItem)
        menu.addItem(.separator())
        menu.addItem(launchItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        item.menu = menu
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        if LoginItem.needsApproval {
            // Registered, but macOS is holding it until the user says yes. Saying "on"
            // here would be a lie, and an unchecked box would invite a click that does
            // nothing, so the item says what is actually needed instead.
            launchItem.title = "Approve Launch at Login…"
            launchItem.state = .off
        } else {
            launchItem.title = "Launch at Login"
            launchItem.state = LoginItem.isEnabled ? .on : .off
        }
    }

    // MARK: Actions

    @objc private func open() {
        onOpen()
    }

    @objc private func toggleLaunchAtLogin() {
        if LoginItem.needsApproval {
            LoginItem.openSystemSettings()
        } else {
            LoginItem.toggle()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
