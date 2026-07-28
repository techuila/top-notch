import AppKit
import Foundation
import NotchCore

/// Now Playing over Apple Events, for Spotify and Apple Music.
///
/// This is the route that is known to work today, so the pane is built on it and the
/// system source is an upgrade rather than a dependency.
///
/// Shape of the work:
/// - Distributed notifications carry every state change for free. They need no Automation
///   grant, arrive instantly, and include title, artist, album, duration and, from
///   Spotify, position. This is the primary input.
/// - Apple Events fill three gaps: the first read when a player was already running before
///   TopNotch launched, Music's missing position, and artwork.
/// - Position is projected locally between reads, so the poll exists only to correct
///   drift and can run as slowly as once every six seconds with the notch closed.
///
/// An Apple Event to an app that is not running would launch it, so every script is gated
/// on `PlayerKind.isRunning` first. That is also what makes "app not running" free.
public actor AppleScriptSource: NowPlayingSource {
    public nonisolated let sourceID = "applescript"

    private var snapshots: [PlayerKind: PlayerSnapshot] = [:]
    private var current: NowPlayingState = .idle
    private var continuation: AsyncStream<NowPlayingState>.Continuation?
    private var bridge: PlayerBroadcastBridge?
    private var eventTask: Task<Void, Never>?
    private var eventContinuation: AsyncStream<PlayerEvent>.Continuation?
    private var cadence: NowPlayingCadence = .background
    private var pollTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var artworkTrackID: String?
    private var running = false

    public init() {}

    // MARK: Lifecycle

    /// Always true when at least one supported player is installed. Apple Events may still
    /// be refused later, which surfaces as `NowPlayingIssue.automationDenied` rather than
    /// as unavailability, because notifications keep working even when scripting does not.
    public func probe() async -> Bool {
        !PlayerCatalog.installed().isEmpty
    }

    public func start() async {
        guard !running else { return }
        running = true

        // The bridge feeds a stream rather than calling back into this actor, so it holds
        // no reference to the source and the two can be torn down independently.
        let (events, continuation) = AsyncStream<PlayerEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(16)
        )
        self.eventContinuation = continuation
        self.bridge = await MainActor.run {
            let bridge = PlayerBroadcastBridge(
                onBroadcast: { continuation.yield(.broadcast($0)) },
                onLifecycleChange: { continuation.yield(.lifecycle) }
            )
            bridge.subscribe()
            return bridge
        }

        eventTask = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                switch event {
                case .broadcast(let broadcast): await self.ingest(broadcast)
                case .lifecycle: await self.refreshAll()
                }
            }
        }

        await refreshAll()
    }

    public func stop() async {
        running = false
        if let bridge {
            await MainActor.run { bridge.unsubscribe() }
        }
        bridge = nil
        eventContinuation?.finish()
        eventContinuation = nil
        eventTask?.cancel()
        eventTask = nil
        pollTask?.cancel()
        pollTask = nil
        artworkTask?.cancel()
        artworkTask = nil
        continuation?.finish()
        continuation = nil
        snapshots.removeAll()
        current = .idle
    }

    public func setCadence(_ cadence: NowPlayingCadence) async {
        guard cadence != self.cadence else { return }
        self.cadence = cadence
        reschedulePoll()
        // The notch just opened. Re-read everything rather than trusting accumulated
        // state: it costs one Apple Event, it happens only on a user action, and it is
        // the guarantee that an open notch is never showing something stale.
        if cadence == .foreground {
            await refreshAll()
        }
    }

    public func events() async -> AsyncStream<NowPlayingState> {
        continuation?.finish()
        let (stream, continuation) = AsyncStream<NowPlayingState>.makeStream(
            bufferingPolicy: .bufferingNewest(4)
        )
        self.continuation = continuation
        continuation.yield(current)
        return stream
    }

    public func snapshot() async -> NowPlayingState { current }

    // MARK: Commands

    public func send(_ command: TransportCommand) async {
        guard let kind = commandTarget else { return }
        let body: String
        switch command {
        case .play: body = "play"
        case .pause: body = "pause"
        case .toggle: body = "playpause"
        case .next: body = "next track"
        case .previous: body = "previous track"
        case .seek(let seconds):
            body = "set player position to \(String(format: "%.3f", max(seconds, 0)))"
        }

        let reuse: Bool
        if case .seek = command { reuse = false } else { reuse = true }
        let result = await AppleEventRunner.shared.runVoid(
            Self.wrap(body, for: kind), reuse: reuse
        )
        note(failure: result, for: kind)

        // Read the result back, because seeking does not always broadcast and the
        // scrubber would otherwise sit on a stale anchor.
        //
        // The delay is not cosmetic. A player accepts the command and updates its own
        // scripting properties a moment later, so an immediate read returns the state
        // from before the command and, being newer than the broadcast that followed it,
        // would win and stick. Settle first, then read, and let `refresh` discard the
        // result anyway if a broadcast beat it.
        try? await Task.sleep(for: .milliseconds(350))
        await refresh(kind)
    }

    /// The player a command should go to: whatever the state came from, else the only
    /// running one. Commands never wake an app that is asleep.
    private var commandTarget: PlayerKind? {
        if let id = current.player?.id, let kind = PlayerCatalog.kind(forBundleID: id), kind.isRunning {
            return kind
        }
        return PlayerKind.allCases.first { $0.isRunning }
    }

    // MARK: Ingest

    private func ingest(_ broadcast: PlayerBroadcast) async {
        guard running else { return }
        var snapshot = snapshots[broadcast.kind] ?? PlayerSnapshot(kind: broadcast.kind)
        snapshot.status = broadcast.status
        snapshot.updatedAt = .now

        if broadcast.status == .stopped {
            snapshot.track = nil
            snapshot.elapsed = 0
            snapshot.capturedAt = .now
        } else {
            let id = broadcast.trackID
                ?? Self.composedID(broadcast.title, broadcast.artist, broadcast.album)
            let previous = snapshot.track
            snapshot.track = NowPlayingTrack(
                id: id,
                title: broadcast.title ?? "",
                artist: broadcast.artist ?? "",
                album: broadcast.album ?? "",
                duration: broadcast.duration ?? previous?.duration ?? 0,
                artwork: previous?.id == id ? previous?.artwork : nil
            )
            if let position = broadcast.position {
                snapshot.elapsed = position
                snapshot.capturedAt = .now
            } else if previous?.id != id {
                // Music sends no position. A track change is always the start of it.
                snapshot.elapsed = 0
                snapshot.capturedAt = .now
            }
        }

        snapshots[broadcast.kind] = snapshot
        publish()

        // Music withholds position; ask for it once per change rather than per second.
        if broadcast.position == nil, broadcast.status.isLoaded {
            await reconcile(broadcast.kind)
        }
        await fetchArtworkIfNeeded()
    }

    /// Full read of every running player. Used at start, when a player launches or quits,
    /// and never on a timer.
    private func refreshAll() async {
        guard running else { return }
        for kind in PlayerKind.allCases {
            await refresh(kind)
        }
        publish()
        await fetchArtworkIfNeeded()
    }

    private func refresh(_ kind: PlayerKind) async {
        guard kind.isRunning else {
            if snapshots.removeValue(forKey: kind) != nil { publish() }
            return
        }
        let startedAt = Date.now
        let result = await AppleEventRunner.shared.run(Self.stateScript(for: kind)) {
            $0.stringValue ?? ""
        }
        note(failure: result, for: kind)

        // A broadcast that landed while this read was in flight is both newer and more
        // trustworthy, so the read is dropped rather than allowed to overwrite it.
        // Without this, any poll racing a play or pause pins the wrong status.
        guard (snapshots[kind]?.updatedAt ?? .distantPast) <= startedAt else { return }

        switch result {
        case .success(let payload):
            snapshots[kind] = Self.parse(payload, kind: kind, previous: snapshots[kind])
        case .failure(.noTrack):
            snapshots[kind] = PlayerSnapshot(kind: kind)
        case .failure:
            // Denied or unreachable. Keep whatever notifications gave us.
            break
        }
        publish()
    }

    /// One tiny Apple Event that reads state and position together. This is the entire poll.
    ///
    /// It carries the player state as well as the position so a missed broadcast cannot
    /// leave the notch permanently convinced that a paused track is still playing.
    private func reconcile(_ kind: PlayerKind? = nil) async {
        guard running,
              let target = kind ?? current.player.flatMap({ PlayerCatalog.kind(forBundleID: $0.id) }),
              target.isRunning,
              snapshots[target]?.status.isLoaded == true
        else { return }

        let startedAt = Date.now
        let result = await AppleEventRunner.shared.run(Self.tickScript(for: target)) {
            $0.stringValue ?? ""
        }
        note(failure: result, for: target)
        guard case .success(let payload) = result else { return }
        guard (snapshots[target]?.updatedAt ?? .distantPast) <= startedAt else { return }

        let fields = payload.components(separatedBy: Self.separator)
        guard let first = fields.first else { return }
        guard first == "playing" || first == "paused" else {
            // Playback ended while we were not looking.
            snapshots[target] = PlayerSnapshot(kind: target)
            publish()
            return
        }
        guard fields.count >= 2, let position = Double(fields[1]), position.isFinite, position >= 0
        else { return }

        var snapshot = snapshots[target] ?? PlayerSnapshot(kind: target)
        let status: PlaybackStatus = first == "playing" ? .playing : .paused
        let projected = snapshot.projectedElapsed(at: .now)
        let statusChanged = snapshot.status != status
        snapshot.status = status
        snapshot.elapsed = position
        snapshot.capturedAt = .now
        snapshots[target] = snapshot
        // Only disturb the UI when the status moved or the projection actually drifted.
        if statusChanged || abs(projected - position) > Self.driftTolerance {
            publish()
        }
    }

    // MARK: Winner and publication

    /// The player the notch should show: the one that is playing, else the one that
    /// changed most recently while holding a track.
    private func winner() -> PlayerSnapshot? {
        let loaded = snapshots.values.filter { $0.status.isLoaded && $0.track != nil }
        if let playing = loaded.filter({ $0.status == .playing }).max(by: { $0.updatedAt < $1.updatedAt }) {
            return playing
        }
        return loaded.max(by: { $0.updatedAt < $1.updatedAt })
    }

    private func publish() {
        var state: NowPlayingState
        if let snapshot = winner() {
            state = NowPlayingState(
                track: snapshot.track,
                status: snapshot.status,
                elapsed: snapshot.elapsed,
                capturedAt: snapshot.capturedAt,
                player: snapshot.kind.identity
            )
        } else {
            state = .idle
        }
        state.issue = deniedPlayer.map { .automationDenied(player: $0.displayName) }

        guard state != current else { return }
        let statusChanged = state.status != current.status
        current = state
        continuation?.yield(state)
        if statusChanged { reschedulePoll() }
    }

    // MARK: Polling

    private func reschedulePoll() {
        pollTask?.cancel()
        pollTask = nil
        // A paused track's position does not move, so there is nothing to correct.
        guard running, current.status == .playing, let interval = cadence.pollInterval else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval), tolerance: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await self?.reconcile()
            }
        }
    }

    // MARK: Artwork

    /// Artwork is fetched once per track id and never again, which is what keeps the
    /// decode count in `ArtworkCache` at one per track.
    private func fetchArtworkIfNeeded() async {
        guard let track = current.track, track.artwork == nil, track.id != artworkTrackID,
              let kind = current.player.flatMap({ PlayerCatalog.kind(forBundleID: $0.id) })
        else { return }

        artworkTrackID = track.id
        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            guard let data = await Self.loadArtwork(kind: kind, trackID: track.id) else { return }
            await self?.attachArtwork(data, to: track.id)
        }
    }

    private func attachArtwork(_ data: Data, to trackID: String) {
        guard let image = NotchImage(id: trackID, data: data) else { return }
        var changed = false
        for (kind, snapshot) in snapshots where snapshot.track?.id == trackID {
            var updated = snapshot
            updated.track?.artwork = image
            snapshots[kind] = updated
            changed = true
        }
        if changed { publish() }
    }

    private static func loadArtwork(kind: PlayerKind, trackID: String) async -> Data? {
        switch kind {
        case .appleMusic:
            let result = await AppleEventRunner.shared.run(artworkScript(for: kind)) { $0.data }
            if case .success(let data) = result, !data.isEmpty { return data }
            return nil
        case .spotify:
            // Spotify hands back a URL rather than bytes, so this is one network fetch
            // per track. Cached by track id like every other artwork path.
            let result = await AppleEventRunner.shared.run(artworkScript(for: kind)) {
                $0.stringValue ?? ""
            }
            guard case .success(let text) = result,
                  let url = URL(string: text), url.scheme?.hasPrefix("http") == true
            else { return nil }
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty
            else { return nil }
            return data
        }
    }

    // MARK: Diagnostics

    private var deniedPlayers: Set<PlayerKind> = []

    private var deniedPlayer: PlayerKind? {
        PlayerKind.allCases.first { deniedPlayers.contains($0) && $0.isRunning }
    }

    private func note<T>(failure: Result<T, AppleEventFailure>, for kind: PlayerKind) {
        switch failure {
        case .failure(.denied):
            deniedPlayers.insert(kind)
        case .success:
            deniedPlayers.remove(kind)
        default:
            break
        }
    }

    // MARK: Script text

    private static let driftTolerance: TimeInterval = 0.6
    /// Unit separator. Cannot occur in a track title, unlike a tab or a pipe.
    private static let separator = "\u{1F}"

    private static func wrap(_ body: String, for kind: PlayerKind) -> String {
        """
        with timeout of 8 seconds
        tell application id "\(kind.bundleID)"
        \(body)
        end tell
        end timeout
        """
    }

    /// One round trip for everything the pane needs except artwork.
    private static func stateScript(for kind: PlayerKind) -> String {
        let extra = kind == .spotify
            ? "\n\ttry\n\t\tset extraField to artwork url of theTrack\n\tend try"
            : ""
        let identifier = kind == .spotify
            ? "(id of theTrack) as text"
            : "(persistent ID of theTrack) as text"
        return wrap(
            """
            set sep to (character id 31)
            set extraField to ""
            set theState to player state as text
            if theState is not "playing" and theState is not "paused" then return "stopped"
            set thePosition to 0
            try
            \tset thePosition to player position
            end try
            set theTrack to current track
            set theID to ""
            try
            \tset theID to \(identifier)
            end try\(extra)
            return theState & sep & theID & sep & (name of theTrack) & sep & \
            (artist of theTrack) & sep & (album of theTrack) & sep & \
            ((duration of theTrack) as text) & sep & (thePosition as text) & sep & extraField
            """,
            for: kind
        )
    }

    /// State and position in one round trip. Two fields is no more expensive than one.
    private static func tickScript(for kind: PlayerKind) -> String {
        wrap(
            """
            set theState to player state as text
            if theState is not "playing" and theState is not "paused" then return "stopped"
            return theState & (character id 31) & (player position as text)
            """,
            for: kind
        )
    }

    private static func artworkScript(for kind: PlayerKind) -> String {
        switch kind {
        case .spotify: wrap("return artwork url of current track", for: kind)
        case .appleMusic: wrap("return raw data of artwork 1 of current track", for: kind)
        }
    }

    private static func composedID(_ title: String?, _ artist: String?, _ album: String?) -> String {
        [title, artist, album].compactMap { $0 }.joined(separator: "\u{1F}")
    }

    private static func parse(
        _ payload: String,
        kind: PlayerKind,
        previous: PlayerSnapshot?
    ) -> PlayerSnapshot {
        var snapshot = PlayerSnapshot(kind: kind)
        snapshot.updatedAt = .now
        snapshot.capturedAt = .now

        let fields = payload.components(separatedBy: separator)
        guard fields.count >= 7, fields[0] != "stopped" else { return snapshot }

        snapshot.status = fields[0] == "playing" ? .playing : .paused
        let title = fields[2]
        let artist = fields[3]
        let album = fields[4]
        let rawDuration = Double(fields[5]) ?? 0
        let duration = kind.durationIsMilliseconds ? rawDuration / 1000 : rawDuration
        let id = fields[1].isEmpty ? composedID(title, artist, album) : fields[1]

        snapshot.elapsed = Double(fields[6]) ?? 0
        snapshot.track = NowPlayingTrack(
            id: id,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            artwork: previous?.track?.id == id ? previous?.track?.artwork : nil
        )
        return snapshot
    }
}

/// Last known state of one player. The source keeps one per app and picks a winner,
/// so switching between Spotify and Music does not lose either side's position.
private struct PlayerSnapshot: Sendable {
    let kind: PlayerKind
    var status: PlaybackStatus = .stopped
    var track: NowPlayingTrack?
    var elapsed: TimeInterval = 0
    var capturedAt: Date = .distantPast
    var updatedAt: Date = .distantPast

    init(kind: PlayerKind) { self.kind = kind }

    func projectedElapsed(at now: Date) -> TimeInterval {
        guard status == .playing else { return elapsed }
        return elapsed + max(0, now.timeIntervalSince(capturedAt))
    }
}
