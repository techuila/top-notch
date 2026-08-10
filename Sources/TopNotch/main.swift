import AppKit
import NotchCore
import NotchShell
import PaneDrop
import PaneFocus
import PaneMusic
import PaneNotes
import Sparkle

/// TopNotch has no dock icon and no main window. It is the notch, plus one status item
/// holding the handful of settings that have to live somewhere a user can find them.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?
    private var menuBar: MenuBarItem?
    // Checks the appcast on a schedule and installs updates in the background.
    // Configuration lives in Info.plist under the SU* keys.
    private var updater: SPUStandardUpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let drop = DropPane()
        // Order matters: it is the order panes appear when scrolling sideways.
        let panes: [any NotchPane] = [
            MusicPane(),
            drop,
            NotesPane(),
            FocusPane(),
        ]
        let controller = NotchController(panes: panes)

        // A file drag has no hover to work with, so the shelf tells the shell to open and
        // the shell holds the panel there for as long as the drag is over it.
        drop.onDragRequestsExpand = { [weak controller] in controller?.present(.drop) }
        controller.setDragCatcher(drop.dragWell()) { drop.isDragTargeted }

        controller.start()
        self.controller = controller

        // On by default, applied once. See `LoginItem`.
        LoginItem.applyDefaultOnFirstLaunch()

        let updater = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
        )
        self.updater = updater
        menuBar = MenuBarItem(updater: updater) { [weak controller] in controller?.present() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
