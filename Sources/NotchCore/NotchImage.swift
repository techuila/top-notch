import AppKit
import SwiftUI

/// A `Sendable` image wrapper so artwork can cross actor boundaries and sit inside
/// `Equatable` state without dragging `NSImage` into every signal comparison.
///
/// Equality is by `identity`, not pixels, so a repeating now-playing poll that hands back
/// the same track does not retrigger the whole idle bar.
public struct NotchImage: Equatable, Sendable, Identifiable {
    /// Stable key for this image, typically a track or file identifier.
    public let id: String
    private let bytes: Data

    public init?(id: String, data: Data?) {
        guard let data, !data.isEmpty else { return nil }
        self.id = id
        self.bytes = data
    }

    public static func == (lhs: NotchImage, rhs: NotchImage) -> Bool { lhs.id == rhs.id }

    /// Decoded on demand. Callers should hold the result rather than calling this per frame.
    public func makeNSImage() -> NSImage? { NSImage(data: bytes) }

    public var data: Data { bytes }
}

/// A tiny bounded cache so the same artwork is decoded once per track, not once per redraw.
@MainActor
public final class ArtworkCache {
    public static let shared = ArtworkCache()

    private var store: [String: NSImage] = [:]
    private var order: [String] = []
    private let limit = 8

    private init() {}

    public func image(for art: NotchImage) -> NSImage? {
        if let hit = store[art.id] { return hit }
        guard let made = art.makeNSImage() else { return nil }
        store[art.id] = made
        order.append(art.id)
        if order.count > limit, let evicted = order.first {
            order.removeFirst()
            store[evicted] = nil
        }
        return made
    }

    public func clear() {
        store.removeAll()
        order.removeAll()
    }
}
