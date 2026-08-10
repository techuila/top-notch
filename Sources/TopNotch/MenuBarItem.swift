import AppKit
import NotchCore
import Sparkle

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

    private let versionItem = NSMenuItem()
    private let openItem = NSMenuItem()
    private let launchItem = NSMenuItem()
    private let appearanceItem = NSMenuItem()
    private let appearanceMenu = NSMenu()
    private let updateItem = NSMenuItem()
    private let quitItem = NSMenuItem()

    init(updater: SPUStandardUpdaterController, onOpen: @escaping () -> Void) {
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

        // No target and no action keeps it permanently disabled: a label, not a control.
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String
        versionItem.title = "Version \(version ?? "dev")"

        openItem.title = "Open TopNotch"
        openItem.target = self
        openItem.action = #selector(open)

        updateItem.title = "Check for Updates…"
        updateItem.target = updater
        updateItem.action = #selector(SPUStandardUpdaterController.checkForUpdates(_:))

        appearanceItem.title = "Appearance"
        for mode in MaterialMode.allCases {
            let item = NSMenuItem(
                title: mode.title, action: #selector(pickAppearance(_:)), keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            appearanceMenu.addItem(item)
        }
        appearanceItem.submenu = appearanceMenu

        launchItem.target = self
        launchItem.action = #selector(toggleLaunchAtLogin)

        quitItem.title = "Quit TopNotch"
        quitItem.keyEquivalent = "q"
        quitItem.target = self
        quitItem.action = #selector(quit)

        menu.delegate = self
        menu.addItem(versionItem)
        menu.addItem(.separator())
        menu.addItem(openItem)
        menu.addItem(.separator())
        menu.addItem(launchItem)
        menu.addItem(appearanceItem)
        menu.addItem(updateItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        item.menu = menu
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in appearanceMenu.items {
            item.state =
                (item.representedObject as? String) == Appearance.shared.material.rawValue
                ? .on : .off
        }
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

    @objc private func pickAppearance(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = MaterialMode(rawValue: raw) else { return }
        Appearance.shared.material = mode
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
