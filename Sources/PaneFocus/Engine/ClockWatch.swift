import Foundation

/// Tells a wall-clock change apart from time simply passing.
///
/// Two readings are taken together: the wall clock, which the user can set to anything,
/// and a monotonic reference that only ever moves forward and keeps counting while the
/// machine is asleep. If the machine sleeps for two hours both advance by two hours and
/// nothing has happened. If they disagree, the wall clock was moved, and a running
/// deadline expressed in wall time has to move with it.
public struct ClockWatch: Equatable, Sendable {
    public private(set) var wall: Date
    public private(set) var monotonic: TimeInterval

    /// Divergence below this is scheduler jitter and small time-server corrections,
    /// not somebody changing the date.
    public var tolerance: TimeInterval

    public init(wall: Date, monotonic: TimeInterval, tolerance: TimeInterval = 2) {
        self.wall = wall
        self.monotonic = monotonic
        self.tolerance = tolerance
    }

    /// Records a new pair of readings and reports how far the wall clock jumped,
    /// or `nil` if it only moved as much as real time did.
    public mutating func sample(wall newWall: Date, monotonic newMonotonic: TimeInterval) -> TimeInterval? {
        let wallDelta = newWall.timeIntervalSince(wall)
        let realDelta = newMonotonic - monotonic
        let jump = wallDelta - realDelta

        wall = newWall
        monotonic = newMonotonic

        return abs(jump) > tolerance ? jump : nil
    }
}
