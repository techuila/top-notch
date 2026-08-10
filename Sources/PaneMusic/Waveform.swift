import Foundation

/// Synthesised playback levels.
///
/// There is no audio tap available to an app in this position without a system audio
/// capture permission and a hot audio thread, so this does not pretend to be one. It is
/// a plausible spectrum driven entirely by playback position: deterministic, so the same
/// second of the same track always draws the same bars, and shaped like music rather
/// than like noise.
///
/// What makes it read as music rather than as five wobbling capsules:
/// - A beat clock. An onset lands roughly twice a second and every bar takes a kick from
///   it, biggest on the left where a spectrum keeps its bass. The onset itself is an
///   exponential: instant rise, musical fall.
/// - Asymmetric chase. Bars jump up toward a rising target and bleed down from a falling
///   one, which is how a real level meter moves.
/// - Section energy. A slow grid of loud and quiet passages, so the group breathes over
///   tens of seconds instead of boiling uniformly forever.
/// - Per-bar grain. Faster, smaller wander on the right, the treble shimmer.
///
/// Paused audio produces a flat line because a flat line is honest about nothing moving.
enum Waveform {
    /// Five bars, the house standard for the idle rotating slot.
    static let barCount = 5

    /// What the bars look like when nothing is moving. Not zero, so the slot keeps its
    /// shape and the bars grow out of a line rather than appearing from nothing.
    static let flat = [Float](repeating: 0.05, count: barCount)

    /// A static, plausibly mid-song shape, shown while playing under Reduce Motion. It
    /// says "audio is moving" without any motion, and costs zero timers.
    static let steady: [Float] = [0.42, 0.66, 0.5, 0.58, 0.34]

    // Band character. Index 0 is the leftmost bar and reads as bass: strongly coupled to
    // the beat, slow grain. The rightmost reads as treble: light beat coupling, fast
    // shimmer. Centre-out weighting keeps the group reading as one spectrum.
    private static let beatCoupling: [Float] = [0.95, 0.8, 0.55, 0.4, 0.3]
    private static let grainAmount: [Float] = [0.12, 0.16, 0.22, 0.26, 0.3]
    private static let grainRate: [Double] = [1.1, 1.7, 2.6, 3.4, 4.3]
    private static let baseLevel: [Float] = [0.16, 0.2, 0.18, 0.16, 0.13]
    private static let weights: [Float] = [1.0, 0.97, 0.9, 0.8, 0.68]

    /// Attack and decay per tick. Rising targets are caught almost immediately, falling
    /// ones are followed slowly, which is what gives a hit a sharp front and a long tail.
    private static let attack: Float = 0.8
    private static let decay: Float = 0.16

    /// Next frame of levels, chased from `previous` toward a position-derived target.
    static func next(from previous: [Float], position: TimeInterval) -> [Float] {
        var levels = previous.count == barCount ? previous : flat
        let onset = Float(beatEnvelope(at: position))
        let energy = Float(sectionEnergy(at: position))
        for index in 0..<barCount {
            let grain = Float(noise(position * grainRate[index] + Double(index) * 13.7))
            var target = baseLevel[index]
            target += beatCoupling[index] * onset
            target += grainAmount[index] * grain
            target *= weights[index] * energy
            target = min(max(target, 0.05), 1)
            let rate = target > levels[index] ? attack : decay
            levels[index] += (target - levels[index]) * rate
        }
        return quantise(levels)
    }

    /// The beat. A clock at 97 to 130 bpm, retimed every 16 seconds, with per-beat
    /// strength hashed off the beat index so accents land irregularly and roughly one
    /// beat in six drops out entirely. The envelope is exponential from the onset:
    /// everything at the hit, gone before the next one.
    private static func beatEnvelope(at position: TimeInterval) -> Double {
        let segment = floor(position / 16)
        let period = 0.46 + 0.16 * hash(segment * 3.9)
        let clock = position / period
        let index = floor(clock)
        let sinceOnset = (clock - index) * period
        var strength = 0.5 + 0.5 * hash(index * 7.31)
        if hash(index * 1.77) < 0.18 { strength *= 0.25 }
        return strength * exp(-sinceOnset * 6.5)
    }

    /// Macro dynamics: an 8 second grid of energy levels eased between, verses and
    /// choruses in miniature. Never reaches zero, because a playing track is never silent
    /// for eight seconds at a time and neither should its bars be.
    private static func sectionEnergy(at position: TimeInterval) -> Double {
        0.62 + 0.38 * noise(position / 8)
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
