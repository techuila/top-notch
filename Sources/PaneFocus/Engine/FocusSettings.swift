import Foundation

/// The two phases. Focus, then a break, then focus again.
///
/// There is no long break and no cycle of four (owner decision, 2026-08-27): both were
/// controls that needed explaining on a pane with no room to explain them.
public enum FocusPhase: String, Codable, Sendable, CaseIterable {
    case work
    case rest = "break"

    public var title: String {
        switch self {
        case .work: "Focus"
        case .rest: "Break"
        }
    }

    public var isBreak: Bool { self == .work ? false : true }

    /// State saved by the cycle-era build named its breaks "shortBreak" and "longBreak".
    /// Either is a break now.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FocusPhase(rawValue: raw) ?? .rest
    }
}

/// User-tunable pomodoro configuration.
///
/// Durations are held in whole minutes because that is the only granularity the notch
/// offers to edit them at, and it keeps persisted state readable.
public struct FocusSettings: Codable, Equatable, Sendable {
    public var workMinutes: Int
    public var breakMinutes: Int

    /// Whether a finished phase starts the next one on its own.
    ///
    /// Off by default. A timer the user did not start is hostile, so the classic
    /// auto-chaining behaviour is opt in.
    public var autoAdvance: Bool

    public static let `default` = FocusSettings()

    public init(
        workMinutes: Int = 25,
        breakMinutes: Int = 5,
        autoAdvance: Bool = false
    ) {
        self.workMinutes = Self.clamp(workMinutes, to: Self.range(for: .work))
        self.breakMinutes = Self.clamp(breakMinutes, to: Self.range(for: .rest))
        self.autoAdvance = autoAdvance
    }

    // MARK: Durations

    public static func range(for phase: FocusPhase) -> ClosedRange<Int> {
        phase == .work ? 1...90 : 1...60
    }

    public func minutes(for phase: FocusPhase) -> Int {
        switch phase {
        case .work: workMinutes
        case .rest: breakMinutes
        }
    }

    public func duration(for phase: FocusPhase) -> TimeInterval {
        TimeInterval(minutes(for: phase) * 60)
    }

    public mutating func setMinutes(_ value: Int, for phase: FocusPhase) {
        let clamped = Self.clamp(value, to: Self.range(for: phase))
        switch phase {
        case .work: workMinutes = clamped
        case .rest: breakMinutes = clamped
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
    // The cycle-era build wrote `shortBreakMinutes`; that becomes the break.
    private enum CodingKeys: String, CodingKey {
        case workMinutes, breakMinutes, shortBreakMinutes, autoAdvance
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            workMinutes: try box.decodeIfPresent(Int.self, forKey: .workMinutes) ?? 25,
            breakMinutes: try box.decodeIfPresent(Int.self, forKey: .breakMinutes)
                ?? box.decodeIfPresent(Int.self, forKey: .shortBreakMinutes) ?? 5,
            autoAdvance: try box.decodeIfPresent(Bool.self, forKey: .autoAdvance) ?? false
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(workMinutes, forKey: .workMinutes)
        try box.encode(breakMinutes, forKey: .breakMinutes)
        try box.encode(autoAdvance, forKey: .autoAdvance)
    }
}
