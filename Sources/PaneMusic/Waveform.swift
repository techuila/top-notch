import Foundation

/// Synthesised playback levels.
///
/// There is no audio tap available to an app in this position, so this does not pretend
/// to be one. It is a plausible motion driven entirely by playback position: deterministic,
/// smooth, and identical for the same second of the same track. Paused audio produces a
/// flat line because a flat line is honest about nothing moving.
enum Waveform {
    /// Five bars, the house standard for the idle rotating slot.
    static let barCount = 5

    /// What the bars look like when nothing is moving. Not zero, so the slot keeps its
    /// shape and the bars grow out of a line rather than appearing from nothing.
    static let flat = [Float](repeating: 0.05, count: barCount)

    /// Per-bar oscillation rates. Mutually irrational enough that the group never
    /// visibly repeats over the length of a track.
    private static let rates: [Double] = [1.83, 2.71, 3.37, 2.29, 1.51]
    private static let phases: [Double] = [0.0, 1.13, 2.31, 3.77, 5.19]
    /// Centre bars read as louder, which is what makes it look like a spectrum rather
    /// than five unrelated bars.
    private static let weights: [Float] = [0.72, 0.92, 1.0, 0.88, 0.68]

    /// How fast bars chase their target. Low enough to look damped, high enough that a
    /// 12fps tick still reaches the target inside a beat.
    private static let smoothing: Float = 0.34

    /// Next frame of levels, eased from `previous` toward a position-derived target.
    static func next(from previous: [Float], position: TimeInterval) -> [Float] {
        var levels = previous.count == barCount ? previous : flat
        for index in 0..<barCount {
            let t = position * rates[index] + phases[index]
            // Two detuned oscillators plus value noise. The noise is what stops it
            // reading as a sine wave, the oscillators are what stop it reading as static.
            let primary = sin(t)
            let secondary = sin(t * 0.41 + phases[index] * 1.7)
            let grain = noise(position * 3.1 + Double(index) * 7.3)
            var target = Float(0.34 + 0.26 * primary + 0.16 * secondary + 0.20 * grain)
            target *= weights[index]
            target = min(max(target, 0.05), 1)
            levels[index] += (target - levels[index]) * smoothing
        }
        return quantise(levels)
    }

    /// Value noise: hashed samples at integer steps, eased between. Deterministic, so
    /// scrubbing back to the same second draws the same bars.
    private static func noise(_ x: Double) -> Double {
        let index = floor(x)
        let frac = x - index
        let eased = frac * frac * (3 - 2 * frac)
        return hash(index) * (1 - eased) + hash(index + 1) * eased
    }

    private static func hash(_ value: Double) -> Double {
        let scaled = sin(value * 127.1 + 311.7) * 43758.5453
        return scaled - floor(scaled)
    }

    /// Two decimals is well below what a 16pt idle slot can show, and it keeps
    /// `IdleSignal` equality from tripping on invisible changes.
    private static func quantise(_ levels: [Float]) -> [Float] {
        levels.map { (($0 * 100).rounded() / 100) }
    }
}
