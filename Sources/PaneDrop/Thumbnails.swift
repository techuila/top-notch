import AppKit
import CoreGraphics
import Foundation
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Renders a chip thumbnail without reading the file.
///
/// QuickLook is asked only for the kinds of file that have something worth previewing, and
/// it is asked for a 34pt representation, so it decodes a downsampled image rather than the
/// original. Everything else gets the document icon, which the system already has cached.
/// The result crosses back as PNG data because neither `NSImage` nor `CGImage` is `Sendable`.
enum ThumbnailRenderer {
    static let pointSize: CGFloat = 34
    static let scale: CGFloat = 2

    /// Runs off the main actor: this is `nonisolated async`, so awaiting it from the pane
    /// hops to the concurrent executor rather than inheriting the main actor.
    static func render(url: URL, isDirectory: Bool) async -> Data? {
        if !isDirectory, wantsPreview(url) {
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: pointSize, height: pointSize),
                scale: scale,
                representationTypes: .thumbnail
            )
            if let preview = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                if let data = png(from: preview.cgImage) { return data }
            }
        }
        return png(from: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
    }

    /// A stat, not a read. Files that are only ever going to render as their document icon
    /// never reach QuickLook, which keeps the XPC round trip off the common case.
    private static func wantsPreview(_ url: URL) -> Bool {
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        else { return false }
        return type.conforms(to: .image)
            || type.conforms(to: .pdf)
            || type.conforms(to: .movie)
            || type.conforms(to: .audiovisualContent)
    }

    private static func png(from image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    private static func png(from image: NSImage) -> Data? {
        let side = pointSize * scale
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(side),
            pixelsHigh: Int(side),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        let context = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}

/// A bounded main-actor cache of decoded chip thumbnails.
///
/// Requests for the same item coalesce onto one task, so a chip redrawing during a hover
/// never starts a second render. Eviction is least recently used against two ceilings:
/// an entry count, and the decoded bytes those entries hold. The byte ceiling is the one
/// that matters, because a shelf full of large images is exactly the case where a count
/// alone would let the cache grow without bound.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    /// Most thumbnails are 68x68 or smaller, so this is roughly 100 of them.
    static let byteLimit = 2 * 1024 * 1024
    static let entryLimit = 48

    private var images: [UUID: NSImage] = [:]
    private var costs: [UUID: Int] = [:]
    private var order: [UUID] = []
    private var inFlight: [UUID: Task<NSImage?, Never>] = [:]
    private var bytes = 0

    private init() {}

    /// Decoded bytes currently held.
    var byteCount: Int { bytes }
    var count: Int { images.count }

    func image(for item: ShelfItem) async -> NSImage? {
        if let hit = images[item.id] {
            touch(item.id)
            return hit
        }
        if let running = inFlight[item.id] { return await running.value }

        let task = Task { @MainActor [url = item.url, isDirectory = item.isDirectory] in
            let data = await ThumbnailRenderer.render(url: url, isDirectory: isDirectory)
            return data.flatMap(NSImage.init(data:))
        }
        inFlight[item.id] = task
        let image = await task.value
        inFlight[item.id] = nil
        if let image { store(image, for: item.id) }
        return image
    }

    /// The cached image if it is already there. Used by the drag out path, which must
    /// build its drag image synchronously.
    func cached(_ id: UUID) -> NSImage? { images[id] }

    func forget(_ id: UUID) {
        drop(id)
        inFlight[id]?.cancel()
        inFlight[id] = nil
    }

    private func store(_ image: NSImage, for id: UUID) {
        drop(id)
        images[id] = image
        costs[id] = Self.cost(of: image)
        bytes += costs[id] ?? 0
        order.append(id)

        while order.count > Self.entryLimit || bytes > Self.byteLimit {
            guard let evicted = order.first, order.count > 1 else { break }
            drop(evicted)
        }
    }

    private func drop(_ id: UUID) {
        if let cost = costs[id] { bytes -= cost }
        costs[id] = nil
        images[id] = nil
        order.removeAll { $0 == id }
    }

    private func touch(_ id: UUID) {
        guard images[id] != nil else { return }
        order.removeAll { $0 == id }
        order.append(id)
    }

    /// What the decoded bitmap actually occupies, not the size of the file it came from.
    private static func cost(of image: NSImage) -> Int {
        let pixels = image.representations.reduce(0) { $0 + $1.pixelsWide * $1.pixelsHigh }
        guard pixels > 0 else {
            return Int(image.size.width * image.size.height * 4)
        }
        return pixels * 4
    }
}
