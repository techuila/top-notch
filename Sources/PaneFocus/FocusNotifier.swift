import Foundation
import UserNotifications

/// Announces phase boundaries.
///
/// The alert is scheduled ahead of time against the phase deadline rather than posted when
/// the app notices the boundary, so it arrives on the second even if the app is busy, the
/// notch is closed or the machine has just woken up.
///
/// Authorisation is requested the first time a session is actually started, never at
/// launch. Asking for permission before the user has used the feature is how you get told
/// no forever.
@MainActor
final class FocusNotifier {
    private static let requestID = "com.aliteo.topnotch.focus.phase"

    private let center: UNUserNotificationCenter?
    private var authorization: Bool?
    /// Bumped on every schedule and cancel so an in-flight authorisation request cannot
    /// post an alert for a session the user has since paused.
    private var generation = 0

    init() {
        // `UNUserNotificationCenter.current()` requires a real bundle. A command line
        // build of the executable has none, and would trap rather than fail politely.
        let bundled = Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
        center = bundled ? .current() : nil
    }

    /// Places a single pending alert at `deadline`, replacing any earlier one.
    func schedule(finished: FocusPhase, next: FocusPhase, at deadline: Date, now: Date) {
        generation += 1
        let token = generation

        guard let center else { return }
        let interval = deadline.timeIntervalSince(now)
        guard interval > 0.5 else {
            center.removePendingNotificationRequests(withIdentifiers: [Self.requestID])
            return
        }

        let content = Self.content(finished: finished, next: next)
        Task { [weak self] in
            guard let self, await self.authorize() else { return }
            guard token == self.generation else { return }

            let request = UNNotificationRequest(
                identifier: Self.requestID,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(interval, 1), repeats: false)
            )
            center.removePendingNotificationRequests(withIdentifiers: [Self.requestID])
            try? await center.add(request)
        }
    }

    func cancel() {
        generation += 1
        center?.removePendingNotificationRequests(withIdentifiers: [Self.requestID])
    }

    private func authorize() async -> Bool {
        if let authorization { return authorization }
        guard let center else { return false }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        authorization = granted
        return granted
    }

    private static func content(finished: FocusPhase, next: FocusPhase) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        switch finished {
        case .work:
            content.title = "Session complete"
            content.body = next == .longBreak ? "Take a long break." : "Take a short break."
        case .shortBreak, .longBreak:
            content.title = "Break over"
            content.body = "Back to focus."
        }
        // The system sound, delivered through the notification, is the only way to make a
        // noise that Do Not Disturb and Focus can silence. Playing it ourselves would talk
        // over a meeting.
        content.sound = .default
        content.interruptionLevel = .active
        return content
    }
}
