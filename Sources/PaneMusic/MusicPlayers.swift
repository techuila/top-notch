import AppKit
import Foundation

/// The players TopNotch can drive over Apple Events.
///
/// Deliberately short. Anything else the user runs is covered by the system source when
/// that route is alive; adding more AppleScript dialects buys very little and each one is
/// a separate permission prompt.
enum PlayerKind: String, CaseIterable, Sendable {
    case spotify
    case appleMusic

    var bundleID: String {
        switch self {
        case .spotify: "com.spotify.client"
        case .appleMusic: "com.apple.Music"
        }
    }

    var displayName: String {
        switch self {
        case .spotify: "Spotify"
        case .appleMusic: "Music"
        }
    }

    var identity: PlayerIdentity {
        PlayerIdentity(id: bundleID, name: displayName)
    }

    /// The distributed notification this player broadcasts on every playback change.
    /// Receiving these needs no entitlement and no Automation grant, which is why they
    /// carry the bulk of the work and Apple Events only fill the gaps.
    var changeNotification: String {
        switch self {
        case .spotify: "com.spotify.client.PlaybackStateChanged"
        case .appleMusic: "com.apple.iTunes.playerInfo"
        }
    }

    /// Track durations arrive in milliseconds from Spotify and seconds from Music.
    var durationIsMilliseconds: Bool {
        switch self {
        case .spotify: true
        case .appleMusic: false
        }
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}

/// An installed player the empty state can offer to launch.
public struct MusicPlayerOption: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let url: URL

    /// The app's own icon, so the empty state looks like the thing it launches.
    @MainActor public var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
    }
}

enum PlayerCatalog {
    /// Installed, launchable players in preference order.
    static func installed() -> [MusicPlayerOption] {
        PlayerKind.allCases.compactMap { kind in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: kind.bundleID)
            else { return nil }
            return MusicPlayerOption(id: kind.bundleID, name: kind.displayName, url: url)
        }
    }

    static func kind(forBundleID id: String) -> PlayerKind? {
        PlayerKind.allCases.first { $0.bundleID == id }
    }
}
