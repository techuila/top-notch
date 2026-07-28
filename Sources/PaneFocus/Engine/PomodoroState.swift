import Foundation

/// Whether the current phase is stopped, counting down, or held.
///
/// A running phase stores the `Date` it ends at, never a tick count. Everything shown to
/// the user is derived from that date against the current time, so the timer cannot drift,
/// and sleep, wake and relaunch all fall out of the same arithmetic for free.
public enum FocusRunState: Equatable, Sendable, Codable {
    /// Stopped at the start of the phase, showing its full duration.
    case idle
    /// Counting down to `deadline`.
    case running(deadline: Date)
    /// Held part way through with `remaining` seconds left.
    case paused(remaining: TimeInterval)
}

/// One phase boundary that has been crossed.
public struct FocusCompletion: Equatable, Sendable {
    /// The phase that ended.
    public let finished: FocusPhase
    /// The instant it ended, which is the deadline it was counting down to, not the
    /// instant we noticed. After a long sleep the two are hours apart.
    public let finishedAt: Date
    /// The phase that came next.
    public let next: FocusPhase
    /// Work sessions completed in the cycle after this boundary.
    public let completedInCycle: Int
    /// Whether the next phase started by itself.
    public let autoStarted: Bool
}

/// The whole pomodoro, as a value.
///
/// Deliberately free of AppKit, SwiftUI and NotchCore so the time logic can be tested
/// as pure arithmetic with an injected `now`.
public struct PomodoroState: Equatable, Sendable, Codable {
    public var settings: FocusSettings
    public var phase: FocusPhase
    /// Work sessions completed so far in the current cycle, `0 ..< settings.sessionsPerCycle`.
    public var completedInCycle: Int
    public var run: FocusRunState

    public init(
        settings: FocusSettings = .default,
        phase: FocusPhase = .work,
        completedInCycle: Int = 0,
        run: FocusRunState = .idle
    ) {
        self.settings = settings
        self.phase = phase
        self.completedInCycle = completedInCycle
        self.run = run
    }

    // MARK: Derived

    public var phaseDuration: TimeInterval { settings.duration(for: phase) }

    public var isRunning: Bool {
        if case .running = run { return true }
        return false
    }

    public var isPaused: Bool {
        if case .paused = run { return true }
        return false
    }

    /// A session is under way: counting down, or held part way through.
    /// This is what claims the permanent pomodoro slot in the idle notch.
    public var isActive: Bool { isRunning || isPaused }

    /// Seconds left in the current phase, derived rather than accumulated.
    public func remaining(at now: Date) -> TimeInterval {
        switch run {
        case .idle:                   phaseDuration
        case .running(let deadline):  max(0, deadline.timeIntervalSince(now))
        case .paused(let remaining):  min(max(0, remaining), phaseDuration)
        }
    }

    public func elapsed(at now: Date) -> TimeInterval {
        max(0, phaseDuration - remaining(at: now))
    }

    /// How far through the phase we are, 0 at the start and 1 at the boundary.
    public func progress(at now: Date) -> Double {
        guard phaseDuration > 0 else { return 0 }
        return min(max(elapsed(at: now) / phaseDuration, 0), 1)
    }

    /// True once the deadline has passed but the boundary has not been applied yet.
    public func hasElapsed(at now: Date) -> Bool {
        if case .running(let deadline) = run { return deadline <= now }
        return false
    }

    /// 1-based index of the work session this phase belongs to. A break reports the
    /// session it follows, so "Session 2 of 4" keeps meaning the same session either side
    /// of the boundary.
    public var sessionIndex: Int {
        let raw = phase == .work ? completedInCycle + 1 : completedInCycle
        return min(max(raw, 1), settings.sessionsPerCycle)
    }

    // MARK: Transport

    public mutating func start(at now: Date) {
        switch run {
        case .idle:
            run = .running(deadline: now.addingTimeInterval(phaseDuration))
        case .paused(let remaining):
            run = .running(deadline: now.addingTimeInterval(max(0, remaining)))
        case .running:
            break
        }
    }

    public mutating func pause(at now: Date) {
        guard case .running = run else { return }
        run = .paused(remaining: remaining(at: now))
    }

    public mutating func toggle(at now: Date) {
        isRunning ? pause(at: now) : start(at: now)
    }

    /// Puts the current phase back to its full duration and stops it.
    /// The cycle count is untouched: restarting a session does not erase the ones before it.
    public mutating func reset() {
        run = .idle
    }

    /// Abandons the current phase and moves to the next one.
    ///
    /// A skipped work session earns no credit toward the long break, because it was not
    /// worked. The next phase starts by itself only if the skipped one was running and
    /// auto-advance is on, so skipping never surprises a stopped timer into running.
    public mutating func skip(at now: Date) {
        let wasRunning = isRunning
        advancePhase(creditWork: false)
        if wasRunning && settings.autoAdvance {
            run = .running(deadline: now.addingTimeInterval(phaseDuration))
        } else {
            run = .idle
        }
    }

    // MARK: Boundaries

    /// Rolls the state forward to `now`, applying every phase boundary that has passed,
    /// and returns them oldest first.
    ///
    /// This is the whole of the sleep, wake, clock and relaunch story. Coming back to a
    /// 25 minute timer after two hours asleep applies the boundary and reports it, rather
    /// than pretending there are 23 minutes left.
    @discardableResult
    public mutating func catchUp(at now: Date, limit: Int = 64) -> [FocusCompletion] {
        var events: [FocusCompletion] = []

        while case .running(let deadline) = run, deadline <= now, events.count < limit {
            let finished = phase
            advancePhase(creditWork: true)

            if settings.autoAdvance {
                // Chained from the deadline, not from `now`, so a chain of auto-advanced
                // phases lands exactly where it would have with the app awake throughout.
                run = .running(deadline: deadline.addingTimeInterval(phaseDuration))
            } else {
                run = .idle
            }

            events.append(
                FocusCompletion(
                    finished: finished,
                    finishedAt: deadline,
                    next: phase,
                    completedInCycle: completedInCycle,
                    autoStarted: settings.autoAdvance
                )
            )
        }

        // Only reachable with a pathological duration or an absurd gap. Leave the user
        // stopped rather than holding a deadline that is already in the past.
        if hasElapsed(at: now) { run = .idle }

        return events
    }

    /// Moves the deadline by `delta` seconds.
    ///
    /// Used when the wall clock itself jumps, for instance the user changing the date or a
    /// large NTP correction. The countdown is about a duration the user asked for, so it
    /// follows the clock instead of being cut short by it.
    public mutating func shiftDeadline(by delta: TimeInterval) {
        guard case .running(let deadline) = run, delta != 0 else { return }
        run = .running(deadline: deadline.addingTimeInterval(delta))
    }

    /// The phase that follows `phase`, without mutating anything.
    public func nextPhase(creditWork: Bool = true) -> FocusPhase {
        switch phase {
        case .work:
            let credited = creditWork ? completedInCycle + 1 : completedInCycle
            return credited >= settings.sessionsPerCycle ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            return .work
        }
    }

    private mutating func advancePhase(creditWork: Bool) {
        switch phase {
        case .work:
            if creditWork {
                completedInCycle = min(completedInCycle + 1, settings.sessionsPerCycle)
            }
            phase = completedInCycle >= settings.sessionsPerCycle ? .longBreak : .shortBreak
        case .shortBreak:
            phase = .work
        case .longBreak:
            completedInCycle = 0
            phase = .work
        }
    }
}
