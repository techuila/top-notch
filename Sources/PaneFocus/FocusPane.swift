import AppKit
import Foundation
import NotchCore
import SwiftUI

/// One phase boundary worth acknowledging on screen.
public struct FocusFlourish: Equatable, Sendable {
    public let finished: FocusPhase
    public let next: FocusPhase
}

/// The pomodoro.
///
/// Nothing here counts. The state holds the `Date` a running phase ends at and every
/// number on screen is derived from it, which is what makes sleep, wake, a changed clock
/// and a relaunch all behave the same way: read the clock, roll forward, redraw.
///
/// While a session runs there is exactly one sleeping task waiting on the deadline and one
/// pending system notification. There is no polling and no repeating timer, and the 1Hz
/// redraw belongs to the view, which only exists while the notch is open.
@MainActor
@Observable
public final class FocusPane: NotchPane {
    public let id: PaneID = .focus
    public var contentHeight: CGFloat { 132 }

    public private(set) var state: PomodoroState
    /// The most recent boundary worth acknowledging, cleared once the flourish is over.
    public private(set) var flourish: FocusFlourish?
    /// Only ever increases. Used as the animation trigger so clearing the flourish does
    /// not fire it a second time.
    public private(set) var flourishToken: Int = 0
    /// True between `activate()` and `deactivate()`, which is exactly when the pane is on
    /// screen. The countdown ticks only while this is true.
    public private(set) var isVisible = false

    private let store: any FocusStore
    private let notifier: FocusNotifier
    private let now: @Sendable () -> Date
    private let monotonic: @Sendable () -> TimeInterval

    private var clockWatch: ClockWatch
    private var deadlineTask: Task<Void, Never>?
    private var flourishTask: Task<Void, Never>?
    private let observers = ObserverBox()

    /// A completion older than this was recovered rather than witnessed. Waking a laptop
    /// to a flourish for something that finished during lunch is noise.
    private static let witnessWindow: TimeInterval = 5

    public convenience init() {
        self.init(store: UserDefaultsFocusStore())
    }

    /// The seam. The clock is injected rather than read, so the sleep, wake and boundary
    /// behaviour can be exercised without waiting twenty five minutes for it.
    public init(
        store: any FocusStore,
        now: @escaping @Sendable () -> Date = { Date() },
        monotonic: @escaping @Sendable () -> TimeInterval = ContinuousTime.seconds
    ) {
        self.store = store
        self.notifier = FocusNotifier()
        self.now = now
        self.monotonic = monotonic

        let start = now()
        let (restored, _) = PomodoroState.restored(from: store, at: start)
        self.state = restored
        self.clockWatch = ClockWatch(wall: start, monotonic: monotonic())

        store.save(state)
        observeSystem()
        scheduleDeadline()
    }

    // MARK: Idle notch

    /// Recomputed from the clock every time it is read, so it is never stale when asked.
    ///
    /// This pane still runs no timer while the notch is closed. A running session hands the
    /// shell its `span` instead, and the shell advances the arc and the digits from the
    /// clock on its own; a paused one carries no span and the published label stands, which
    /// is correct because a held countdown has nothing to advance.
    public var idle: IdleSignal {
        let instant = now()

        guard state.isActive else {
            return IdleSignal(
                isLive: false,
                priority: Self.priority,
                pinnedLeading: nil,
                // No session, so the ring is not the identity and the glyph has to be.
                identity: .glyph(id.glyph),
                rotating: flourish == nil ? nil : .badge(symbol: "checkmark", text: "Done"),
                progress: nil,
                pulse: flourishToken
            )
        }

        let label = notchTime(state.remaining(at: instant))
        return IdleSignal(
            isLive: true,
            priority: Self.priority,
            // The permanent outer-left slot. Only a live pomodoro may claim it.
            pinnedLeading: .ring(
                progress: state.progress(at: instant),
                label: label,
                span: state.span
            ),
            // The ring above is already this pane's identity. A second marker would say
            // the same thing twice.
            identity: nil,
            rotating: state.isRunning ? .badge(symbol: id.glyph, text: label) : nil,
            // The bottom edge line belongs to music. The ring carries our progress.
            progress: nil,
            // The boundary is worth acknowledging even with the notch closed, which is
            // most of the time a pomodoro actually ends.
            pulse: flourishToken
        )
    }

    /// Below music, above everything with no live value.
    private static let priority = 90

    // MARK: Pane lifecycle

    public func content() -> AnyView {
        AnyView(FocusPaneContent(pane: self))
    }

    public func activate() {
        isVisible = true
        sync()
    }

    public func deactivate() {
        isVisible = false
    }

    // MARK: Transport

    public func toggle() {
        let instant = now()
        state.catchUp(at: instant)
        let wasRunning = state.isRunning
        state.toggle(at: instant)
        if !wasRunning, state.isRunning {
            FocusSounds.play(starting: state.phase)
        } else if wasRunning, state.isPaused {
            FocusSounds.play(.pause)
        }
        commit()
    }

    public func skip() {
        let instant = now()
        state.catchUp(at: instant)
        state.skip(at: instant)
        commit()
    }

    public func reset() {
        state.catchUp(at: now())
        state.reset()
        commit()
    }

    public func adjust(_ phase: FocusPhase, by delta: Int) {
        state.settings.adjust(phase, by: delta)
        commit()
    }

    public func setAutoAdvance(_ enabled: Bool) {
        state.settings.autoAdvance = enabled
        commit()
    }

    // MARK: Time

    /// Rolls the state forward to the current instant and reacts to anything that changed.
    private func sync() {
        let instant = now()

        // A wall clock that has moved further than real time drags the deadline with it,
        // so setting the date does not cut a running session short or extend it.
        if let jump = clockWatch.sample(wall: instant, monotonic: monotonic()) {
            state.shiftDeadline(by: jump)
        }

        let crossed = state.catchUp(at: instant)
        if let last = crossed.last {
            if instant.timeIntervalSince(last.finishedAt) <= Self.witnessWindow {
                show(FocusFlourish(finished: last.finished, next: last.next))
                // The notification carries the sound when it can. Without permission
                // there is no alert, so the pane says it instead.
                if !notifier.deliversSound {
                    FocusSounds.play(starting: last.next)
                }
            }
            store.save(state)
        }
        scheduleDeadline()
    }

    /// Persist and re-arm after any deliberate change.
    private func commit() {
        store.save(state)
        scheduleDeadline()
    }

    /// Arms exactly one sleeping task and one pending notification for the next boundary,
    /// or tears both down when nothing is running.
    private func scheduleDeadline() {
        deadlineTask?.cancel()
        deadlineTask = nil

        guard case .running(let deadline) = state.run else {
            notifier.cancel()
            return
        }

        let instant = now()
        notifier.schedule(
            finished: state.phase,
            next: state.nextPhase(),
            at: deadline,
            now: instant
        )

        let interval = deadline.timeIntervalSince(instant)
        deadlineTask = Task { [weak self] in
            if interval > 0 {
                // The continuous clock keeps counting while the machine is asleep, so this
                // resumes the moment the deadline passes rather than the moment the app
                // gets time again.
                try? await Task.sleep(for: .seconds(interval), tolerance: .milliseconds(50), clock: .continuous)
            }
            guard !Task.isCancelled else { return }
            self?.sync()
        }
    }

    private func show(_ next: FocusFlourish) {
        flourish = next
        flourishToken &+= 1
        flourishTask?.cancel()
        flourishTask = Task { [weak self] in
            try? await Task.sleep(for: Motion.rotationDwell)
            guard !Task.isCancelled else { return }
            self?.flourish = nil
        }
    }

    // MARK: System

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.add(workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.sync() }
            })
        }

        let center = NotificationCenter.default
        observers.add(center, center.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sync() }
        })
    }

}

/// Seconds on a clock that only moves forward and, unlike system uptime, does not stop
/// while the machine is asleep. Sleeping for two hours has to look like two hours passing,
/// otherwise it would be indistinguishable from somebody setting the date forward.
public enum ContinuousTime {
    private static let origin = ContinuousClock.now

    public static let seconds: @Sendable () -> TimeInterval = {
        let elapsed = ContinuousClock.now - origin
        return TimeInterval(elapsed.components.seconds)
            + TimeInterval(elapsed.components.attoseconds) * 1e-18
    }
}

/// Holds notification tokens so they are removed when the pane goes away, without giving
/// a main-actor class a deinit that has to touch isolated state.
private final class ObserverBox: @unchecked Sendable {
    private var tokens: [(NotificationCenter, any NSObjectProtocol)] = []

    func add(_ center: NotificationCenter, _ token: any NSObjectProtocol) {
        tokens.append((center, token))
    }

    deinit {
        for (center, token) in tokens { center.removeObserver(token) }
    }
}
