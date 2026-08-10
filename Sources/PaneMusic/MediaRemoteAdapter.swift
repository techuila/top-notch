import AppKit
import Foundation

/// Where the vendored `mediaremote-adapter` artifacts live and how to run them.
///
/// The adapter is a perl script plus a framework. `/usr/bin/perl` is signed as
/// `com.apple.perl` with no library validation, which is the only reason any of this
/// works: `mediaremoted` allows `com.apple.` prefixed clients through, and an unhardened
/// perl can `dlopen` a third-party framework. Nothing here links MediaRemote.
///
/// Both artifacts must sit inside the app bundle. A helper outside the bundle fails
/// outright under App Sandbox because the spawned perl inherits our container.
struct AdapterLocation: Sendable {
    var perl = URL(fileURLWithPath: "/usr/bin/perl")
    var script: URL
    var framework: URL
    /// Only used by the health check. Without it there is no gate, and without a gate
    /// this source must not be used at all.
    var testClient: URL?

    /// Bundle layout the app is expected to ship:
    ///
    ///     TopNotch.app/Contents/Resources/mediaremote-adapter.pl
    ///     TopNotch.app/Contents/Frameworks/MediaRemoteAdapter.framework
    ///     TopNotch.app/Contents/MacOS/MediaRemoteAdapterTestClient
    ///
    /// `TOPNOTCH_ADAPTER_DIR` points at a directory holding all three, for testing a
    /// build of the adapter before it is vendored.
    static func discover(bundle: Bundle = .main) -> AdapterLocation? {
        if let override = ProcessInfo.processInfo.environment["TOPNOTCH_ADAPTER_DIR"],
           let location = fromDirectory(URL(fileURLWithPath: override)) {
            return location
        }
        guard let script = bundle.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let frameworks = bundle.privateFrameworksURL
        else { return nil }
        let framework = frameworks.appendingPathComponent("MediaRemoteAdapter.framework")
        guard FileManager.default.fileExists(atPath: framework.path) else { return nil }
        return AdapterLocation(
            script: script,
            framework: framework,
            testClient: bundle.url(forAuxiliaryExecutable: "MediaRemoteAdapterTestClient")
        )
    }

    private static func fromDirectory(_ directory: URL) -> AdapterLocation? {
        let manager = FileManager.default
        // A CMake build tree keeps the script in bin/ and the products at the top level.
        let scriptCandidates = [
            directory.appendingPathComponent("mediaremote-adapter.pl"),
            directory.appendingPathComponent("bin/mediaremote-adapter.pl"),
        ]
        let frameworkCandidates = [
            directory.appendingPathComponent("MediaRemoteAdapter.framework"),
            directory.appendingPathComponent("build/MediaRemoteAdapter.framework"),
        ]
        let clientCandidates = [
            directory.appendingPathComponent("MediaRemoteAdapterTestClient"),
            directory.appendingPathComponent("build/MediaRemoteAdapterTestClient"),
        ]
        guard let script = scriptCandidates.first(where: { manager.fileExists(atPath: $0.path) }),
              let framework = frameworkCandidates.first(where: { manager.fileExists(atPath: $0.path) })
        else { return nil }
        return AdapterLocation(
            script: script,
            framework: framework,
            testClient: clientCandidates.first { manager.fileExists(atPath: $0.path) }
        )
    }

    func arguments(_ tail: [String]) -> [String] {
        [script.path, framework.path] + tail
    }
}

/// MediaRemote command identifiers, as the adapter's `send` subcommand takes them.
enum MRCommand: Int, Sendable {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    case stop = 3
    case nextTrack = 4
    case previousTrack = 5
}

/// Shuffle modes, as the adapter's `shuffle` subcommand takes them and as the payload's
/// `shuffleMode` reports them.
enum MRShuffleMode: Int, Sendable {
    case disabled = 1
    case albums = 2
    case tracks = 3
}

/// Repeat modes, as the adapter's `repeat` subcommand takes them and as the payload's
/// `repeatMode` reports them.
enum MRRepeatMode: Int, Sendable {
    case disabled = 1
    case track = 2
    case playlist = 3
}

/// One decoded now-playing payload from the adapter.
///
/// Field names match the adapter's JSON exactly. `duration` and `elapsedTime` are
/// seconds; `seek` is the only place microseconds appear, and that is on the way out.
struct AdapterPayload: Decodable, Sendable, Equatable {
    var title: String?
    var artist: String?
    var album: String?
    var duration: Double?
    var elapsedTime: Double?
    var timestamp: Date?
    var playing: Bool?
    var playbackRate: Double?
    var bundleIdentifier: String?
    var contentItemIdentifier: String?
    var artworkData: Data?
    var artworkMimeType: String?
    /// `MRShuffleMode` raw value. Absent when the playing app does not report shuffle,
    /// which is the signal to hide the control.
    var shuffleMode: Int?
    /// `MRRepeatMode` raw value, same contract as `shuffleMode`.
    var repeatMode: Int?

    var isEmpty: Bool { self == AdapterPayload() }
}

/// The adapter wraps every stream line in an envelope.
struct AdapterEnvelope: Decodable, Sendable {
    let type: String
    let payload: AdapterPayload?
}

/// Runs adapter subprocesses off the cooperative pool.
///
/// `Process` plus `readDataToEndOfFile` blocks, and blocking a cooperative thread starves
/// the whole concurrency runtime, so short-lived calls get a dedicated queue exactly like
/// the Apple Event path does.
enum AdapterProcess {
    private static let queue = DispatchQueue(
        label: "com.aliteo.topnotch.music.adapter",
        qos: .utility
    )

    struct Output: Sendable {
        var status: Int32
        var data: Data
    }

    /// Runs to completion and collects stdout. `timeout` terminates a wedged helper
    /// rather than leaking it.
    static func run(
        _ location: AdapterLocation,
        _ arguments: [String],
        timeout: TimeInterval = 10
    ) async -> Output {
        await withCheckedContinuation { continuation in
            queue.async {
                let process = Process()
                process.executableURL = location.perl
                process.arguments = location.arguments(arguments)
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: Output(status: -1, data: Data()))
                    return
                }

                let watchdog = DispatchWorkItem {
                    if process.isRunning { process.terminate() }
                }
                DispatchQueue.global(qos: .utility).asyncAfter(
                    deadline: .now() + timeout, execute: watchdog
                )

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                watchdog.cancel()
                continuation.resume(returning: Output(status: process.terminationStatus, data: data))
            }
        }
    }

    /// Fire and forget, for transport commands whose only reply is the music changing.
    static func detached(_ location: AdapterLocation, _ arguments: [String]) {
        queue.async {
            let process = Process()
            process.executableURL = location.perl
            process.arguments = location.arguments(arguments)
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
        }
    }
}

/// The long-lived `stream` helper, turned into an `AsyncStream` of decoded payloads.
///
/// Newline-delimited JSON pushed from MediaRemote change notifications, so there is no
/// poll anywhere in this path. The stream finishing means the helper died, which the
/// source treats as a failure worth falling back from.
final class AdapterStream: @unchecked Sendable {
    private let process = Process()
    private let pipe = Pipe()
    /// Only ever touched from the pipe's readability handler, which Foundation
    /// serialises on one queue.
    private var buffer = Data()
    private var terminationObserver: (any NSObjectProtocol)?

    private static let newline = UInt8(0x0A)

    func start(
        _ location: AdapterLocation,
        includeArtwork: Bool,
        onPayload: @escaping @Sendable (AdapterPayload) -> Void,
        onExit: @escaping @Sendable () -> Void
    ) -> Bool {
        // `--no-diff` makes every event a complete payload, which removes a whole class of
        // merge bugs. Artwork is excluded here and fetched once per track instead: with it
        // switched on, every single event carries roughly 170KB of base64.
        //
        // The debounce matters for more than noise. A play or pause produces a short burst
        // in which the adapter has the new state but not yet the new elapsed time, and an
        // undebounced consumer sees the scrubber snap to zero and back. Coalescing costs
        // about a tenth of a second on top of the adapter's own 68-239ms and removes it.
        var arguments = ["stream", "--no-diff", "--debounce=120"]
        if !includeArtwork { arguments.append("--no-artwork") }

        process.executableURL = location.perl
        process.arguments = location.arguments(arguments)
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        let decoder = Self.makeDecoder()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            self.buffer.append(chunk)
            while let index = self.buffer.firstIndex(of: Self.newline) {
                let line = Data(self.buffer[self.buffer.startIndex..<index])
                self.buffer.removeSubrange(self.buffer.startIndex...index)
                guard !line.isEmpty,
                      let envelope = try? decoder.decode(AdapterEnvelope.self, from: line),
                      envelope.type == "data",
                      let payload = envelope.payload
                else { continue }
                onPayload(payload)
            }
        }
        process.terminationHandler = { _ in onExit() }

        do {
            try process.run()
        } catch {
            return false
        }

        // A child is reparented rather than killed when we exit, and this one only
        // notices its broken pipe the next time something plays. Quitting cleanly should
        // not leave a 25MB perl process sitting around until then.
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stop()
        }
        return true
    }

    func stop() {
        pipe.fileHandleForReading.readabilityHandler = nil
        process.terminationHandler = nil
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
            self.terminationObserver = nil
        }
        if process.isRunning { process.terminate() }
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dataDecodingStrategy = .base64
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
