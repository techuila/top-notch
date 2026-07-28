import AppKit
import NotchCore
import NotchShell
import PaneDrop
import PaneFocus
import PaneMusic
import PaneNotes

/// TopNotch has no dock icon, no main window and no menu bar item by default.
/// It is the notch, and nothing else.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Order matters: it is the order panes appear when scrolling sideways.
        let panes: [any NotchPane] = [
            MusicPane(),
            DropPane(),
            NotesPane(),
            FocusPane(),
        ]
        let controller = NotchController(panes: panes)
        controller.start()
        self.controller = controller
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
