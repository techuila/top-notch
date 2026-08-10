import NotchCore
import SwiftUI

/// Now Playing, transport and artwork.
///
/// The pane owns no playback knowledge of its own. It reads `NowPlayingCoordinator`,
/// which reads whichever `NowPlayingSource` won at runtime, and it turns that into an
/// `IdleSignal` and an expanded view.
///
/// Cost when nothing is playing: one distributed notification subscription and no timers.
/// Cost while playing with the notch closed: one 6fps waveform tick and one position read
/// every six seconds.
@MainActor
@Observable
public final class MusicPane: NotchPane {
    public let id: PaneID = .music

    /// Fixed. The panel must not breathe as a track title wraps or artwork arrives.
    public var contentHeight: CGFloat { 114 }

    public let coordinator: NowPlayingCoordinator

    /// Synthesised levels for the trailing waveform and the idle rotating slot.
    private(set) var levels: [Float] = Waveform.flat
    /// Playback fraction, updated only when it moves far enough to be visible.
    private(set) var fraction: Double = 0
    /// Whole seconds elapsed, so the label ticks once a second rather than once a frame.
    private(set) var elapsed: TimeInterval = 0

    private var ticker: Timer?
    private var isActive = false
    private var notchVisible = true

    public init(coordinator: NowPlayingCoordinator = NowPlayingCoordinator()) {
        self.coordinator = coordinator
        coordinator.start()
        observeState()
        applyState()
    }

    // MARK: Idle

    public var idle: IdleSignal {
        let state = coordinator.state
        guard state.isLive else { return .inactive }
        return IdleSignal(
            isLive: true,
            priority: 100,
            // Music is the one pane allowed to take the notch off whatever the user last
            // chose. A track starting is about the machine, not about a pane.
            claimsFocus: true,
            // The outer-left slot belongs to a running pomodoro and nothing else.
            pinnedLeading: nil,
            identity: .artwork(state.track?.artwork),
            rotating: .waveform(levels),
            progress: fraction
        )
    }

    // MARK: Pane lifecycle

    public func activate() {
        isActive = true
        coordinator.setCadence(.foreground)
        applyState()
        syncTicker()
    }

    public func deactivate() {
        isActive = false
        coordinator.setCadence(coordinator.state.isLive ? .background : .suspended)
        syncTicker()
    }

    /// Hook for the shell to say whether the notch is on screen at all.
    ///
    /// `NotchPane` has no visibility callback, so by default this pane assumes the notch
    /// is visible whenever something is playing, which is true in the common case because
    /// the idle bar is showing this pane's waveform. If the shell ever gains a real
    /// visibility signal, calling this stops the waveform entirely when nothing can see it.
    public func setNotchVisible(_ visible: Bool) {
        guard visible != notchVisible else { return }
        notchVisible = visible
        syncTicker()
    }

    // MARK: Transport

    func toggle() { coordinator.send(.toggle) }
    func next() { coordinator.send(.next) }
    func previous() { coordinator.send(.previous) }
    func seek(fraction: Double) { coordinator.seek(fraction: fraction) }

    /// Explicit state, computed here from the last read, so the command cannot race a
    /// second tap the way a blind toggle would.
    func toggleShuffle() {
        coordinator.send(.setShuffle(!(coordinator.state.shuffle ?? false)))
    }

    /// Cycles off, all, one, the order every player's own UI uses. Sources without a
    /// repeat-one clamp the `.one` step, which turns the cycle into a plain toggle.
    func cycleRepeat() {
        coordinator.send(.setRepeat((coordinator.state.repeatMode ?? .off).next))
    }

    // MARK: Observation

    /// Re-arms itself on every change. Cheaper than a timer and it fires exactly when the
    /// source publishes, which with distributed notifications is the instant the user hits
    /// a media key.
    private func observeState() {
        withObservationTracking {
            _ = coordinator.state.status
            _ = coordinator.state.track?.id
            _ = coordinator.state.track?.duration
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.applyState()
                self.syncTicker()
                self.observeState()
            }
        }
    }

    /// Pulls position out of the state immediately, so the scrubber does not wait for the
    /// next tick after a seek or a track change.
    private func applyState() {
        let state = coordinator.state
        guard let track = state.track else {
            fraction = 0
            elapsed = 0
            levels = Waveform.flat
            return
        }
        let position = state.position(at: .now)
        elapsed = position.rounded(.down)
        fraction = track.duration > 0 ? position / track.duration : 0
        if state.status != .playing { levels = Waveform.flat }
        // The pane may have been deactivated while stopped; playing again needs the
        // background cadence back or the position would never be corrected.
        if !isActive {
            coordinator.setCadence(state.isLive ? .background : .suspended)
        }
    }

    // MARK: Ticking

    /// 12fps with the pane on screen, 6fps behind the closed notch where the waveform is
    /// 16pt tall, and nothing at all when paused, stopped, or under Reduce Motion.
    private var tickInterval: TimeInterval? {
        guard coordinator.state.status == .playing, notchVisible, !reduceMotion else { return nil }
        return isActive ? 1.0 / 12.0 : 1.0 / 6.0
    }

    /// `Motion.reduced` is the one sanctioned reading of the system setting. Checked
    /// when the ticker is synced, not per frame, and there is no ticker to check it on
    /// while reduced, so a live settings flip lands on the next state change.
    private var reduceMotion: Bool {
        if case .none = Motion.reduced(Motion.ambient) { return true }
        return false
    }

    private func syncTicker() {
        guard let interval = tickInterval else {
            ticker?.invalidate()
            ticker = nil
            // Under Reduce Motion a playing track holds one static mid-song shape:
            // "audio is moving" said without motion, at the cost of zero timers.
            let resting = coordinator.state.status == .playing && notchVisible && reduceMotion
                ? Waveform.steady
                : Waveform.flat
            if levels != resting { levels = resting }
            return
        }
        if let ticker, abs(ticker.timeInterval - interval) < 0.001 { return }
        ticker?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.tick() }
        }
        // Generous tolerance lets the system coalesce these with other wakeups, which is
        // the difference between a smooth waveform and a warm laptop.
        timer.tolerance = interval * 0.4
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        let state = coordinator.state
        guard let track = state.track, state.status == .playing else {
            syncTicker()
            return
        }
        let position = state.position(at: .now)
        levels = Waveform.next(from: levels, position: position)

        let whole = position.rounded(.down)
        if whole != elapsed { elapsed = whole }

        guard track.duration > 0 else { return }
        let next = min(max(position / track.duration, 0), 1)
        // Roughly half a point of movement on the widest surface this drives. Below that
        // there is nothing to redraw.
        if abs(next - fraction) > 0.0015 { fraction = next }
    }

    // MARK: Content

    public func content() -> AnyView {
        AnyView(MusicPaneView(pane: self))
    }
}
