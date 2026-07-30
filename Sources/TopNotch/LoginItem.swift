import AppKit
import Foundation
import ServiceManagement

/// Launch at login, backed by `SMAppService`.
///
/// On by default. The notch is only worth anything if it is already there, and an app you
/// have to remember to start is one you stop using. That default is applied exactly once,
/// on the first launch: after that whatever the user last chose stands, including a change
/// they made in System Settings rather than in our menu.
///
/// No `LaunchAgent` plist and no helper target. `SMAppService.mainApp` registers the app
/// bundle itself, which is what puts it in System Settings under Login Items where a user
/// expects to find it and be able to turn it off.
@MainActor
enum LoginItem {

    /// Records that the first-launch default has been applied, so turning it off sticks.
    private static let configuredKey = "launchAtLogin.configured"

    private static var service: SMAppService { .mainApp }

    static var isEnabled: Bool { service.status == .enabled }

    /// True when macOS has the registration but the user has not approved it yet. The menu
    /// says so rather than showing an unchecked box that ticks itself back on.
    static var needsApproval: Bool { service.status == .requiresApproval }

    /// Registers on the very first launch and never again.
    static func applyDefaultOnFirstLaunch(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: configuredKey) else { return }
        defaults.set(true, forKey: configuredKey)
        setEnabled(true)
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            switch (enabled, service.status) {
            case (true, .enabled), (false, .notRegistered), (false, .notFound):
                return true
            case (true, _):
                try service.register()
            case (false, _):
                try service.unregister()
            }
            return true
        } catch {
            // Registration fails for a bundle macOS will not vouch for, most often an
            // unsigned build run straight out of a build directory. Nothing to recover
            // here: the menu re-reads the real status and will show it did not take.
            return false
        }
    }

    static func toggle() {
        setEnabled(!isEnabled)
    }

    /// Opens the Login Items pane, for when approval is what is missing rather than
    /// registration. There is no API to approve on the user's behalf, by design.
    static func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
