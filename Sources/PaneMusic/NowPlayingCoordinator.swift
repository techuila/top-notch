import AppKit
import Foundation
import NotchCore

/// Chooses a `NowPlayingSource` at runtime and owns the one that wins.
///
/// The rule is one line: use the system source when it says it is available, otherwise
/// Apple Events. Everything above this type reads `state` and calls `send(_:)` and never
/// learns which route answered, so dropping a working `SystemNowPlayingSource` in later
/// changes nothing else.
@MainActor
@Observable
public final class NowPlayingCoordinator {
    /// Latest observation. Interpolate position with `state.position(at:)` rather than
    /// expecting this to change every second.
    public private(set) var state: NowPlayingState = .idle

    /// Which source answered. Exposed for diagnostics, not for behaviour.
    public private(set) var activeSourceID: String?

    /// Installed players the empty state can offer to launch.
    public private(set) var installedPlayers: [MusicPlayerOption] = []

    /// A cold launch in progress, so the empty state can show it is working.
    public private(set) var launchingPlayer: String?

    private let system: any NowPlayingSource
    private let fallback: any NowPlayingSource
    private var active: (any NowPlayingSource)?
    private var pump: Task<Void, Never>?
    private var cadence: NowPlayingCadence = .background
    private var started = false

    public init(
        system: any NowPlayingSource = SystemNowPlayingSource(),
        fallback: any NowPlayingSource = AppleScriptSource()
    ) {
        self.system = system
        self.fallback = fallback
    }

    // MARK: Lifecycle

    public func start() {
        guard !started else { return }
        started = true
        installedPlayers = PlayerCatalog.installed()
        Task { await selectSource() }
    }

    public func stop() {
        started = false
        pump?.cancel()
        pump = nil
        let leaving = active
        active = nil
        activeSourceID = nil
        state = .idle
        Task { await leaving?.stop() }
    }

    /// Re-runs the preference check. Worth calling after the system route is implemented,
    /// or if it ever becomes conditionally available.
    public func reevaluateSource() {
        guard started else { return }
        Task { await selectSource() }
    }

    private func selectSource() async {
        // The system route is preferred when it reports itself available. Apple Events are
        // the floor: they still start with nothing installed, and simply report idle,
        // which is the correct answer rather than an error state.
        let preferred: any NowPlayingSource = await system.probe() ? system : fallback
        guard preferred.sourceID != activeSourceID else { return }

        pump?.cancel()
        if let active { await active.stop() }
        state = .idle

        active = preferred
        activeSourceID = preferred.sourceID
        await preferred.start()
        await preferred.setCadence(cadence)

        let stream = await preferred.events()
        pump = Task { [weak self] in
            for await next in stream {
                guard !Task.isCancelled else { return }
                self?.state = next
            }
            // The source ended the stream itself, which means it failed. Re-running the
            // preference check is what turns "the adapter died" into "use Apple Events"
            // without anything above this type noticing.
            guard !Task.isCancelled else { return }
            self?.activeSourceID = nil
            self?.reevaluateSource()
        }
    }

    // MARK: Control

    public func setCadence(_ cadence: NowPlayingCadence) {
        guard cadence != self.cadence else { return }
        self.cadence = cadence
        guard let active else { return }
        Task { await active.setCadence(cadence) }
    }

    public func send(_ command: TransportCommand) {
        guard let active else { return }
        Task { await active.send(command) }
    }

    /// Seek by fraction of the loaded track, which is what a scrubber actually produces.
    public func seek(fraction: Double) {
        guard let duration = state.track?.duration, duration > 0 else { return }
        send(.seek(min(max(fraction, 0), 1) * duration))
    }

    // MARK: Cold launch

    /// Opens a player that is not running and starts playback.
    ///
    /// This is the whole point of the empty state: with Spotify closed the user can still
    /// press play from the notch. The app is opened without stealing focus, then a single
    /// `play` event resumes whatever it had last. The event has to wait for the app to
    /// finish launching, which is why it is bounded by a timeout inside the script.
    public func launch(_ option: MusicPlayerOption) {
        guard launchingPlayer == nil, let kind = PlayerCatalog.kind(forBundleID: option.id) else { return }
        launchingPlayer = option.id

        Task { [weak self] in
            await MusicLauncher.launchAndPlay(kind)
            self?.launchingPlayer = nil
        }
    }

    /// Opens the Automation pane so a denied permission is one click from fixed.
    public func openAutomationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

enum MusicLauncher {
    /// Launch without activating, then resume once the player can actually hear us.
    ///
    /// Both halves are needed and the order matters. Opening the app alone leaves it
    /// paused. Scripting it alone launches it invisibly and blocks. And a `play` sent the
    /// moment the process exists is simply dropped: Spotify is Electron and takes several
    /// seconds to answer Apple Events, during which it accepts nothing.
    ///
    /// So this waits for the scripting interface to answer, not for the process to exist,
    /// and confirms the player actually started rather than assuming the command landed.
    static func launchAndPlay(_ kind: PlayerKind) async {
        if !kind.isRunning {
            guard let url = await appURL(for: kind) else { return }
            let configuration = NSWorkspace.OpenConfiguration()
            // Never steal focus. The user pressed a button in the notch, not in Spotify.
            configuration.activates = false
            configuration.addsToRecentItems = false
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }

        for attempt in 0..<Self.readyAttempts {
            try? await Task.sleep(for: .milliseconds(attempt == 0 ? 200 : 600))
            guard kind.isRunning else { continue }

            let probe = await AppleEventRunner.shared.run(Self.stateProbe(kind)) {
                $0.stringValue ?? ""
            }
            // Still launching: a short script timeout keeps a cold player from wedging
            // the Apple Event queue while we wait.
            guard case .success(let state) = probe, !state.isEmpty else { continue }
            if state == "playing" { return }

            await AppleEventRunner.shared.runVoid(Self.playScript(kind))
        }
    }

    /// Roughly 18 seconds, which covers a cold Electron launch on a slow disk without
    /// leaving a spinner up forever if the player never becomes ready.
    private static let readyAttempts = 30

    private static func stateProbe(_ kind: PlayerKind) -> String {
        """
        with timeout of 3 seconds
        tell application id "\(kind.bundleID)"
        return player state as text
        end tell
        end timeout
        """
    }

    private static func playScript(_ kind: PlayerKind) -> String {
        """
        with timeout of 5 seconds
        tell application id "\(kind.bundleID)"
        play
        end tell
        end timeout
        """
    }

    @MainActor
    private static func appURL(for kind: PlayerKind) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: kind.bundleID)
    }
}
