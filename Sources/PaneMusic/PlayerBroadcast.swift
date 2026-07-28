import AppKit
import Foundation

/// One playback change as broadcast by a player, already reduced to `Sendable` values.
///
/// Spotify and Music both post a distributed notification on every state change carrying
/// most of what the pane needs. Reading them costs nothing, needs no Automation grant and
/// arrives instantly, so they do the work that a poll loop would otherwise do.
struct PlayerBroadcast: Sendable {
    var kind: PlayerKind
    var status: PlaybackStatus
    var title: String?
    var artist: String?
    var album: String?
    var trackID: String?
    var duration: TimeInterval?
    /// Spotify includes the position. Music does not, and has to be asked.
    var position: TimeInterval?

    init?(kind: PlayerKind, userInfo: [AnyHashable: Any]?) {
        guard let userInfo else { return nil }
        self.kind = kind

        let state = (userInfo["Player State"] as? String)?.lowercased() ?? ""
        switch state {
        case "playing": status = .playing
        case "paused": status = .paused
        default: status = .stopped
        }

        title = userInfo["Name"] as? String
        artist = userInfo["Artist"] as? String
        album = userInfo["Album"] as? String

        // Spotify uses a track URI, Music a persistent or store identifier. Either is
        // stable for the life of the track, which is all the artwork cache needs.
        if let uri = userInfo["Track ID"] as? String {
            trackID = uri
        } else if let persistent = userInfo["PersistentID"] {
            trackID = String(describing: persistent)
        } else if let store = userInfo["Store URL"] as? String {
            trackID = store
        }

        let rawDuration = (userInfo["Duration"] as? NSNumber) ?? (userInfo["Total Time"] as? NSNumber)
        if let rawDuration {
            let value = rawDuration.doubleValue
            // Music reports Total Time in milliseconds too, so both need the divide.
            duration = value > 0 ? value / 1000 : nil
        }

        if let raw = userInfo["Playback Position"] as? NSNumber {
            position = raw.doubleValue
        }
    }
}

/// Anything the bridge can report. Funnelled through one stream so the bridge never
/// holds a reference back into the source.
enum PlayerEvent: Sendable {
    case broadcast(PlayerBroadcast)
    /// A player launched or quit. Everything has to be re-read.
    case lifecycle
}

/// Subscribes to both players' distributed notifications.
///
/// A plain `NSObject` because only the selector-based API takes a suspension behaviour,
/// and coalescing playback changes would make the notch lag behind the music.
///
/// Main actor on purpose. Registering with `distnoted` needs a live run loop, and doing
/// it from an actor's executor deadlocks rather than failing. Delivery then arrives on
/// the main thread and hops straight back into the source's actor.
@MainActor
final class PlayerBroadcastBridge: NSObject {
    private let handler: @Sendable (PlayerBroadcast) -> Void
    private let lifecycle: @Sendable () -> Void
    private var subscribed = false

    init(
        onBroadcast: @escaping @Sendable (PlayerBroadcast) -> Void,
        onLifecycleChange: @escaping @Sendable () -> Void
    ) {
        self.handler = onBroadcast
        self.lifecycle = onLifecycleChange
        super.init()
    }

    func subscribe() {
        guard !subscribed else { return }
        subscribed = true
        let center = DistributedNotificationCenter.default()
        for kind in PlayerKind.allCases {
            center.addObserver(
                self,
                selector: #selector(received(_:)),
                name: Notification.Name(kind.changeNotification),
                object: nil,
                suspensionBehavior: .deliverImmediately
            )
        }
        // A player quitting is silent on the distributed channel, so watch the workspace
        // as well or a stale track would sit in the notch forever.
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(
            self,
            selector: #selector(appsChanged(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
        workspace.addObserver(
            self,
            selector: #selector(appsChanged(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
    }

    func unsubscribe() {
        guard subscribed else { return }
        subscribed = false
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func received(_ note: Notification) {
        guard let kind = PlayerKind.allCases.first(where: { $0.changeNotification == note.name.rawValue }),
              let broadcast = PlayerBroadcast(kind: kind, userInfo: note.userInfo)
        else { return }
        handler(broadcast)
    }

    @objc private func appsChanged(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let id = app.bundleIdentifier,
              PlayerCatalog.kind(forBundleID: id) != nil
        else { return }
        lifecycle()
    }
}
