import Foundation

/// The three phases of a classic pomodoro cycle.
public enum FocusPhase: String, Codable, Sendable, CaseIterable {
    case work
    case shortBreak
    case longBreak

    public var title: String {
        switch self {
        case .work:       "Focus"
        case .shortBreak: "Short break"
        case .longBreak:  "Long break"
        }
    }

    /// Short form used where the full title will not fit, such as the duration steppers.
    public var shortTitle: String {
        switch self {
        case .work:       "Focus"
        case .shortBreak: "Short"
        case .longBreak:  "Long"
        }
    }

    public var symbol: String {
        switch self {
        case .work:       "brain.head.profile"
        case .shortBreak: "cup.and.saucer"
        case .longBreak:  "moon.zzz"
        }
    }

    public var isBreak: Bool { self != .work }
}

/// User-tunable pomodoro configuration.
///
/// Durations are held in whole minutes because that is the only granularity the notch
/// offers to edit them at, and it keeps persisted state readable.
public struct FocusSettings: Codable, Equatable, Sendable {
    public var workMinutes: Int
    public var shortBreakMinutes: Int
    public var longBreakMinutes: Int

    /// Work sessions completed before a long break is offered.
    public var sessionsPerCycle: Int

    /// Whether a finished phase starts the next one on its own.
    ///
    /// Off by default. A timer the user did not start is hostile, so the classic
    /// auto-chaining behaviour is opt in.
    public var autoAdvance: Bool

    public static let `default` = FocusSettings()

    public init(
        workMinutes: Int = 25,
        shortBreakMinutes: Int = 5,
        longBreakMinutes: Int = 15,
        sessionsPerCycle: Int = 4,
        autoAdvance: Bool = false
    ) {
        self.workMinutes = Self.clamp(workMinutes, to: Self.range(for: .work))
        self.shortBreakMinutes = Self.clamp(shortBreakMinutes, to: Self.range(for: .shortBreak))
        self.longBreakMinutes = Self.clamp(longBreakMinutes, to: Self.range(for: .longBreak))
        self.sessionsPerCycle = max(1, sessionsPerCycle)
        self.autoAdvance = autoAdvance
    }

    // MARK: Durations

    public static func range(for phase: FocusPhase) -> ClosedRange<Int> {
        phase == .work ? 1...90 : 1...60
    }

    public func minutes(for phase: FocusPhase) -> Int {
        switch phase {
        case .work:       workMinutes
        case .shortBreak: shortBreakMinutes
        case .longBreak:  longBreakMinutes
        }
    }

    public func duration(for phase: FocusPhase) -> TimeInterval {
        TimeInterval(minutes(for: phase) * 60)
    }

    public mutating func setMinutes(_ value: Int, for phase: FocusPhase) {
        let clamped = Self.clamp(value, to: Self.range(for: phase))
        switch phase {
        case .work:       workMinutes = clamped
        case .shortBreak: shortBreakMinutes = clamped
        case .longBreak:  longBreakMinutes = clamped
        }
    }

    /// Nudges one duration by whole minutes, staying inside its allowed range.
    public mutating func adjust(_ phase: FocusPhase, by delta: Int) {
        setMinutes(minutes(for: phase) + delta, for: phase)
    }

    public func canAdjust(_ phase: FocusPhase, by delta: Int) -> Bool {
        Self.range(for: phase).contains(minutes(for: phase) + delta)
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    // MARK: Codable

    // Decoded field by field so that state written by an older build, or state that has
    // been hand-edited into nonsense, still restores instead of throwing the session away.
    private enum CodingKeys: String, CodingKey {
        case workMinutes, shortBreakMinutes, longBreakMinutes, sessionsPerCycle, autoAdvance
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            workMinutes: try box.decodeIfPresent(Int.self, forKey: .workMinutes) ?? 25,
            shortBreakMinutes: try box.decodeIfPresent(Int.self, forKey: .shortBreakMinutes) ?? 5,
            longBreakMinutes: try box.decodeIfPresent(Int.self, forKey: .longBreakMinutes) ?? 15,
            sessionsPerCycle: try box.decodeIfPresent(Int.self, forKey: .sessionsPerCycle) ?? 4,
            autoAdvance: try box.decodeIfPresent(Bool.self, forKey: .autoAdvance) ?? false
        )
    }
}
