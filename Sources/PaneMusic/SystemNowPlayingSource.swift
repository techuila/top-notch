import AppKit
import Foundation
import NotchCore

/// System-wide Now Playing, via the vendored `mediaremote-adapter` perl shim.
///
/// This satisfies the LOCKED decision in DECISIONS.md: Apple Music, a browser tab, a
/// podcast app and VLC all report through the same path and get identical controls.
///
/// Why a perl shim rather than MediaRemote directly: on macOS 26.5 an unentitled process
/// still resolves every MediaRemote symbol and still gets its callbacks invoked, but the
/// payload comes back nil. The failure is indistinguishable from "nothing is playing",
/// which is precisely why it must not be built on. `/usr/bin/perl` is signed as
/// `com.apple.perl` with no library validation, so it passes `mediaremoted`'s
/// `com.apple.` prefix check and can load the adapter framework.
///
/// The gate is load-bearing. macOS 26.6 hardened path handling inside MediaRemote under
/// CVE-2026-43723, and that has not been tested. `probe()` runs the adapter's own `test`
/// command and checks its exit code, so a version that breaks the shim routes to
/// `AppleScriptSource` automatically instead of showing an empty notch.
public actor SystemNowPlayingSource: NowPlayingSource {
    public nonisolated let sourceID = "system"

    private var location: AdapterLocation?
    private var stream: AdapterStream?
    private var current: NowPlayingState = .idle
    private var continuation: AsyncStream<NowPlayingState>.Continuation?
    private var artworkTrackID: String?
    private var artworkTask: Task<Void, Never>?
    private var running = false

    /// Set when the helper has died repeatedly. Makes `probe()` refuse, so the coordinator
    /// stops choosing this source after it has proven unreliable.
    private var disabled = false
    private var helperFailures = 0
    private static let failureLimit = 3

    public init() {}

    // MARK: Lifecycle

    /// Discovers the bundled adapter and asks it whether MediaRemote will still talk to
    /// it. Anything other than exit code 0, or a missing artifact, means no.
    ///
    /// Deliberately never returns true on the strength of the framework merely being
    /// present. A handle that returns empty payloads is worse than no handle at all,
    /// because it would stop the coordinator falling back.
    public func probe() async -> Bool {
        guard !disabled else { return false }
        guard let location = AdapterLocation.discover() else { return false }
        guard let testClient = location.testClient else {
            // Without the test client there is no health gate, and an ungated adapter is
            // exactly the thing the CVE makes unsafe to assume.
            return false
        }
        self.location = location
        let result = await AdapterProcess.run(
            location, [testClient.path, "test"], timeout: 15
        )
        return result.status == 0
    }

    public func start() async {
        guard !running else { return }
        guard let location = location ?? AdapterLocation.discover() else { return }
        self.location = location
        running = true
        helperFailures = 0
        startHelper()
    }

    public func stop() async {
        running = false
        stream?.stop()
        stream = nil
        artworkTask?.cancel()
        artworkTask = nil
        artworkTrackID = nil
        continuation?.finish()
        continuation = nil
        current = .idle
    }

    /// The adapter pushes. There is no poll here to slow down, at any cadence.
    public func setCadence(_ cadence: NowPlayingCadence) async {}

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
        guard let location else { return }
        switch command {
        case .play: AdapterProcess.detached(location, ["send", String(MRCommand.play.rawValue)])
        case .pause: AdapterProcess.detached(location, ["send", String(MRCommand.pause.rawValue)])
        case .toggle:
            AdapterProcess.detached(location, ["send", String(MRCommand.togglePlayPause.rawValue)])
        case .next:
            AdapterProcess.detached(location, ["send", String(MRCommand.nextTrack.rawValue)])
        case .previous:
            AdapterProcess.detached(location, ["send", String(MRCommand.previousTrack.rawValue)])
        case .seek(let seconds):
            // The adapter takes microseconds here, and only here.
            let micros = Int(max(seconds, 0) * 1_000_000)
            AdapterProcess.detached(location, ["seek", String(micros)])
        }
    }

    // MARK: Helper

    private func startHelper() {
        guard running, let location else { return }
        let helper = AdapterStream()
        // Artwork is pulled separately, once per track. Left switched on here it would
        // add roughly 170KB of base64 to every single event, including the ones that
        // only move the elapsed time.
        let started = helper.start(
            location,
            includeArtwork: false,
            onPayload: { [weak self] payload in
                Task { await self?.ingest(payload) }
            },
            onExit: { [weak self] in
                Task { await self?.helperDied() }
            }
        )
        guard started else {
            Task { await helperDied() }
            return
        }
        stream = helper
    }

    private func helperDied() async {
        guard running else { return }
        stream?.stop()
        stream = nil
        helperFailures += 1

        guard helperFailures < Self.failureLimit else {
            // Give up and hand back to the coordinator. Finishing the stream is the
            // signal that this source has failed; the coordinator re-evaluates and lands
            // on Apple Events.
            disabled = true
            running = false
            current = .idle
            continuation?.finish()
            continuation = nil
            return
        }

        try? await Task.sleep(for: .seconds(Double(helperFailures)), tolerance: .milliseconds(500))
        startHelper()
    }

    // MARK: Ingest

    private func ingest(_ payload: AdapterPayload) async {
        guard running else { return }
        // The adapter opens every stream with an empty payload. It means "nothing yet",
        // not "playback stopped".
        guard !payload.isEmpty else {
            emit(.idle)
            return
        }
        // A live helper stays alive, so any earlier restarts are water under the bridge.
        helperFailures = 0

        guard let title = payload.title, !title.isEmpty else {
            emit(.idle)
            return
        }

        let identifier = Self.trackID(for: payload)
        let previousArtwork = current.track?.id == identifier ? current.track?.artwork : nil

        let track = NowPlayingTrack(
            id: identifier,
            title: title,
            artist: payload.artist ?? "",
            album: payload.album ?? "",
            duration: payload.duration ?? 0,
            artwork: previousArtwork
        )
        // `playing` is authoritative when present. `playbackRate` is the fallback, and it
        // is simply absent while paused rather than being reported as zero.
        let isPlaying = payload.playing ?? ((payload.playbackRate ?? 0) > 0)

        let status: PlaybackStatus = isPlaying ? .playing : .paused
        // `elapsedTime` is the position at `timestamp`, not at read time. Anchoring to the
        // payload's own timestamp is both more accurate than the receive time and stable
        // across the duplicate events the adapter emits.
        var elapsed = payload.elapsedTime ?? 0
        var capturedAt = payload.timestamp ?? .now

        // Across a play or pause edge MediaRemote briefly reports a stale elapsed time,
        // observed jumping to a position from minutes earlier before correcting itself one
        // event later. Playback position cannot legitimately move at the instant playback
        // is halted or resumed, so our own projection is the better answer and the next
        // event supplies the authoritative one.
        if current.track?.id == identifier, current.status != status, current.isLive {
            elapsed = current.position(at: .now)
            capturedAt = .now
        }

        var state = NowPlayingState(
            track: track,
            status: status,
            elapsed: elapsed,
            capturedAt: capturedAt
        )
        if let bundleID = payload.bundleIdentifier {
            state.player = PlayerIdentity(id: bundleID, name: await Self.appName(for: bundleID))
        }

        emit(state)
        await fetchArtworkIfNeeded()
    }

    private func emit(_ state: NowPlayingState) {
        guard state != current else { return }
        current = state
        continuation?.yield(state)
    }

    /// Track identity, composed rather than taken from the payload.
    ///
    /// `contentItemIdentifier` looks like the obvious key and is not usable: playing one
    /// Spotify track through the adapter produced five different values inside ten
    /// seconds. Keying artwork or `NotchImage` equality off it would refetch and
    /// re-decode on nearly every event. Title, artist, album and duration are stable for
    /// as long as the track is.
    private static func trackID(for payload: AdapterPayload) -> String {
        let duration = payload.duration.map { String(format: "%.0f", $0) } ?? ""
        return [
            payload.bundleIdentifier ?? "",
            payload.title ?? "",
            payload.artist ?? "",
            payload.album ?? "",
            duration,
        ].joined(separator: "\u{1F}")
    }

    // MARK: Artwork

    /// One `get` per track, never per event.
    private func fetchArtworkIfNeeded() async {
        guard let location, let track = current.track,
              track.artwork == nil, track.id != artworkTrackID
        else { return }

        artworkTrackID = track.id
        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            let result = await AdapterProcess.run(location, ["get"], timeout: 10)
            guard result.status == 0,
                  let payload = try? AdapterStream.makeDecoder()
                      .decode(AdapterPayload.self, from: result.data),
                  let data = payload.artworkData, !data.isEmpty
            else { return }
            await self?.attachArtwork(data, to: track.id)
        }
    }

    private func attachArtwork(_ data: Data, to trackID: String) {
        guard current.track?.id == trackID,
              let image = NotchImage(id: trackID, data: data)
        else { return }
        var state = current
        state.track?.artwork = image
        current = state
        continuation?.yield(state)
    }

    /// Display name for the app that owns playback. Cached, because resolving it hits
    /// LaunchServices and the answer never changes for a bundle identifier.
    private static let nameCache = NameCache()

    private static func appName(for bundleID: String) async -> String {
        await nameCache.name(for: bundleID)
    }

    private actor NameCache {
        private var cache: [String: String] = [:]

        func name(for bundleID: String) async -> String {
            if let hit = cache[bundleID] { return hit }
            let resolved = await MainActor.run { () -> String in
                guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                else { return bundleID }
                return FileManager.default.displayName(atPath: url.path(percentEncoded: false))
                    .replacingOccurrences(of: ".app", with: "")
            }
            cache[bundleID] = resolved
            return resolved
        }
    }
}
