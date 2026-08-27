// Renders the focus sounds (owner decisions, 2026-08-27).
//
// "Glass" for the transport: soft sine notes a fifth apart, rising for Focus starting
// (E5 then B5), falling for Pause (B5 then E5). A break beginning is a soft chime: one
// G5 with a quiet overtone, a gentle attack and a long ring. Deterministic, so the files
// in Resources/Sounds are reproducible from this script alone.
//
//   swift publishing/scripts/render-sounds.swift Resources/Sounds

import AVFoundation
import Foundation

let rate = 44_100.0
// Full scale (owner decision, 2026-08-27): the point is to be heard over music. The two
// notes overlap for a moment, so the sum is normalised after rendering rather than
// trusting per-note levels.
let peak = 0.98

struct Note {
    let at: Double, hz: Double, dur: Double, level: Double
    /// Attack in seconds. Glass is near-instant; the chime blooms.
    var attack: Double = 0.012
    /// Level of an inharmonic partial at 2.76x, which is what makes a sine read as a bell.
    var overtone: Double = 0
}

func render(_ notes: [Note], to url: URL) throws {
    let length = notes.map { $0.at + $0.dur }.max()! + 0.05
    let frames = Int(length * rate)
    var samples = [Float](repeating: 0, count: frames)
    for n in notes {
        let start = Int(n.at * rate)
        let count = Int(n.dur * rate)
        let attack = Int(n.attack * rate)
        for i in 0..<count {
            let t = Double(i) / rate
            // Attack, then exponential decay to -80 dB at the end of the note.
            let env = i < attack ? Double(i) / Double(attack) : pow(10, -4 * (t - n.attack) / (n.dur - n.attack))
            var v = sin(2 * .pi * n.hz * t)
            if n.overtone > 0 {
                // The partial dies faster than the fundamental, as it does on a real bell.
                v += n.overtone * sin(2 * .pi * n.hz * 2.76 * t) * pow(10, -3 * t / n.dur)
            }
            samples[start + i] += Float(v * env * n.level)
        }
    }
    // Normalise so the loudest instant of the mix is exactly `peak`.
    let loudest = samples.map { abs($0) }.max() ?? 1
    if loudest > 0 { samples = samples.map { $0 / loudest * Float(peak) } }
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
    buffer.frameLength = AVAudioFrameCount(frames)
    samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: frames) }
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: true,
    ]
    let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    try file.write(from: buffer)
}

let e5 = 659.25, b5 = 987.77, g5 = 783.99
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/Sounds")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
try render([Note(at: 0, hz: e5, dur: 0.32, level: 1), Note(at: 0.13, hz: b5, dur: 0.36, level: 0.9)], to: out.appendingPathComponent("FocusStart.aiff"))
try render([Note(at: 0, hz: b5, dur: 0.32, level: 0.9), Note(at: 0.13, hz: e5, dur: 0.5, level: 0.8)], to: out.appendingPathComponent("Pause.aiff"))
try render([Note(at: 0, hz: g5, dur: 0.9, level: 1, attack: 0.03, overtone: 0.18)], to: out.appendingPathComponent("BreakStart.aiff"))
print("rendered", out.path)
