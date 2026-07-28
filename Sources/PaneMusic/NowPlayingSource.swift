import Foundation
import NotchCore

/// Whether audio is moving, held, or absent.
public enum PlaybackStatus: String, Equatable, Sendable {
    case stopped, paused, playing

    /// True when a track is loaded, whether or not it is currently moving.
    public var isLoaded: Bool { self != .stopped }
}

/// The app the state came from. Kept out of `NowPlayingTrack` so a track that moves
/// between players still compares equal on identity.
public struct PlayerIdentity: Equatable, Sendable, Identifiable {
    /// Bundle identifier, e.g. `com.spotify.client`.
    public let id: String
    /// Display name for the UI, e.g. `Spotify`.
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// One loaded track.
///
/// `id` must be stable for the lifetime of the track so `NotchImage` and `IdleSignal`
/// equality do not thrash on every refresh. Prefer the player's own identifier and only
/// fall back to a composed key when it has none.
public struct NowPlayingTrack: Equatable, Sendable, Identifiable {
    public let id: String
    public var title: String
    public var artist: String
    public var album: String
    public var duration: TimeInterval
    public var artwork: NotchImage?

    public init(
        id: String,
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        artwork: NotchImage? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.artwork = artwork
    }
}

/// Something the user can act on that is stopping this source from working properly.
public enum NowPlayingIssue: Equatable, Sendable {
    /// The user has not granted, or has revoked, Automation access for this player.
    case automationDenied(player: String)
}

/// A single observation of what is playing.
///
/// `elapsed` is the position at `capturedAt`, not at read time. Sources emit only when
/// something meaningful changes and consumers interpolate forward with `position(at:)`,
/// which is what keeps the poll rate off the frame rate.
public struct NowPlayingState: Equatable, Sendable {
    public var track: NowPlayingTrack?
    public var status: PlaybackStatus
    public var elapsed: TimeInterval
    public var capturedAt: Date
    public var player: PlayerIdentity?
    public var issue: NowPlayingIssue?

    public init(
        track: NowPlayingTrack? = nil,
        status: PlaybackStatus = .stopped,
        elapsed: TimeInterval = 0,
        capturedAt: Date = .distantPast,
        player: PlayerIdentity? = nil,
        issue: NowPlayingIssue? = nil
    ) {
        self.track = track
        self.status = status
        self.elapsed = elapsed
        self.capturedAt = capturedAt
        self.player = player
        self.issue = issue
    }

    /// Nothing loaded anywhere.
    public static let idle = NowPlayingState()

    /// True when there is a track loaded, playing or paused.
    public var isLive: Bool { track != nil && status.isLoaded }

    /// Position projected forward from the capture instant. Only playback advances it.
    public func position(at now: Date) -> TimeInterval {
        guard let track else { return 0 }
        let drift = status == .playing ? max(0, now.timeIntervalSince(capturedAt)) : 0
        return min(max(elapsed + drift, 0), max(track.duration, 0))
    }

    /// 0...1 playback fraction, projected the same way.
    public func fraction(at now: Date) -> Double {
        guard let track, track.duration > 0 else { return 0 }
        return min(max(position(at: now) / track.duration, 0), 1)
    }
}

/// A transport action. Sources dispatch these best effort and never report success,
/// because every backing mechanism is fire and forget.
public enum TransportCommand: Equatable, Sendable {
    case play
    case pause
    case toggle
    case next
    case previous
    /// Absolute position in seconds.
    case seek(TimeInterval)
}

/// How closely the UI is watching.
///
/// This governs polling only. Change notifications stay subscribed at every cadence,
/// including `.suspended`, otherwise the idle signal would never learn that playback
/// started while the notch was closed.
public enum NowPlayingCadence: Equatable, Sendable {
    /// Notch open and the music pane on screen. Position must look continuous.
    case foreground
    /// Notch closed but something is loaded. The idle bar still needs to be right.
    case background
    /// Nothing loaded. Notifications only, zero timers.
    case suspended

    /// Seconds between drift-correcting position reads, or `nil` for no polling.
    /// Never faster than 1Hz, per the cheap-when-idle rule.
    var pollInterval: Double? {
        switch self {
        case .foreground: 1.0
        case .background: 6.0
        case .suspended: nil
        }
    }
}

/// Where Now Playing state comes from.
///
/// Two conformers exist: `SystemNowPlayingSource`, which reads the system-wide route and
/// covers every player, and `AppleScriptSource`, which drives Spotify and Apple Music over
/// Apple Events. `NowPlayingCoordinator` picks between them at runtime with `probe()`.
///
/// Conformers are expected to be actors. Every requirement is async apart from `sourceID`,
/// which must be witnessed by a `nonisolated let`.
public protocol NowPlayingSource: Sendable {
    /// Stable short name, used for diagnostics and to spot a source switch.
    var sourceID: String { get }

    /// Whether this source can actually observe playback on this machine right now.
    /// Cheap, called before `start()`, and safe to call again later to re-evaluate.
    func probe() async -> Bool

    /// Begin observing. Idempotent.
    func start() async

    /// Stop observing and release everything. Idempotent.
    func stop() async

    /// Adjust polling effort. Has no effect on change notifications.
    func setCadence(_ cadence: NowPlayingCadence) async

    /// Meaningful state changes. One consumer at a time: calling this again finishes
    /// the previous stream. The current state is replayed as the first element.
    ///
    /// Finishing the stream on its own means this source has failed and should not be
    /// used again. The coordinator re-runs `probe()` on every source and moves on, so a
    /// source that gives up must also start answering `probe()` with `false`.
    func events() async -> AsyncStream<NowPlayingState>

    /// Latest known state without waiting on the stream.
    func snapshot() async -> NowPlayingState

    /// Dispatch a transport command. Best effort, no result.
    func send(_ command: TransportCommand) async
}
