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
    /// Focus rounds finished on the day of this boundary, after it.
    public let roundsToday: Int
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
    public var run: FocusRunState

    /// Focus rounds finished on `roundsDay`. A round is finished when its deadline
    /// passes; a skipped one was not worked and does not count. The number only ever
    /// grows within a day, and the day is the only thing that resets it.
    public private(set) var roundsToday: Int
    /// The start of the day `roundsToday` belongs to.
    public private(set) var roundsDay: Date?

    public init(
        settings: FocusSettings = .default,
        phase: FocusPhase = .work,
        run: FocusRunState = .idle,
        roundsToday: Int = 0,
        roundsDay: Date? = nil
    ) {
        self.settings = settings
        self.phase = phase
        self.run = run
        self.roundsToday = max(roundsToday, 0)
        self.roundsDay = roundsDay
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

    /// The window the current phase occupies, start to deadline, or `nil` when nothing is
    /// counting down.
    ///
    /// Only a running phase has one, which is exactly when the countdown can be derived
    /// from the clock alone. The start is recovered from the deadline rather than stored,
    /// so resuming from a pause reports the window the remaining time actually implies.
    public var span: ClosedRange<Date>? {
        guard case .running(let deadline) = run, phaseDuration > 0 else { return nil }
        return deadline.addingTimeInterval(-phaseDuration)...deadline
    }

    /// True once the deadline has passed but the boundary has not been applied yet.
    public func hasElapsed(at now: Date) -> Bool {
        if case .running(let deadline) = run { return deadline <= now }
        return false
    }

    /// Focus rounds finished today, where today is the day `now` falls on. Yesterday's
    /// count is not carried over, so the first look of the morning says zero.
    public func rounds(at now: Date, calendar: Calendar = .current) -> Int {
        guard let roundsDay, calendar.isDate(roundsDay, inSameDayAs: now) else { return 0 }
        return roundsToday
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
    /// The round count is untouched: restarting a round does not erase the ones before it.
    public mutating func reset() {
        run = .idle
    }

    /// Abandons the current phase and moves to the next one.
    ///
    /// A skipped focus round is not counted, because it was not worked. The next phase
    /// starts by itself only if the skipped one was running and auto-advance is on, so
    /// skipping never surprises a stopped timer into running.
    public mutating func skip(at now: Date) {
        let wasRunning = isRunning
        phase = nextPhase()
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
    public mutating func catchUp(at now: Date, limit: Int = 64, calendar: Calendar = .current) -> [FocusCompletion] {
        var events: [FocusCompletion] = []

        while case .running(let deadline) = run, deadline <= now, events.count < limit {
            let finished = phase
            if finished == .work {
                credit(on: deadline, calendar: calendar)
            }
            phase = nextPhase()

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
                    roundsToday: rounds(at: deadline, calendar: calendar),
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
    public func nextPhase() -> FocusPhase {
        phase == .work ? .rest : .work
    }

    /// One more round on the day `instant` falls on. A new day starts the count over.
    private mutating func credit(on instant: Date, calendar: Calendar) {
        let day = calendar.startOfDay(for: instant)
        if roundsDay != day {
            roundsDay = day
            roundsToday = 0
        }
        roundsToday += 1
    }

    // MARK: Codable

    // Field by field, so state saved by the cycle-era build (which had a session count
    // and no rounds) still restores its phase, run and settings instead of being thrown
    // away.
    private enum CodingKeys: String, CodingKey {
        case settings, phase, run, roundsToday, roundsDay
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            settings: try box.decodeIfPresent(FocusSettings.self, forKey: .settings) ?? .default,
            phase: try box.decodeIfPresent(FocusPhase.self, forKey: .phase) ?? .work,
            run: try box.decodeIfPresent(FocusRunState.self, forKey: .run) ?? .idle,
            roundsToday: try box.decodeIfPresent(Int.self, forKey: .roundsToday) ?? 0,
            roundsDay: try box.decodeIfPresent(Date.self, forKey: .roundsDay)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(settings, forKey: .settings)
        try box.encode(phase, forKey: .phase)
        try box.encode(run, forKey: .run)
        try box.encode(roundsToday, forKey: .roundsToday)
        try box.encodeIfPresent(roundsDay, forKey: .roundsDay)
    }
}
