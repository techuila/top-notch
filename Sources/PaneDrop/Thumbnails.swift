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
/// never starts a second render, and the cache is capped so a long session cannot grow it.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private var images: [UUID: NSImage] = [:]
    private var order: [UUID] = []
    private var inFlight: [UUID: Task<NSImage?, Never>] = [:]
    private let limit = 48

    private init() {}

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
        images[id] = nil
        order.removeAll { $0 == id }
        inFlight[id]?.cancel()
        inFlight[id] = nil
    }

    private func store(_ image: NSImage, for id: UUID) {
        images[id] = image
        touch(id)
        while order.count > limit, let evicted = order.first {
            order.removeFirst()
            images[evicted] = nil
        }
    }

    private func touch(_ id: UUID) {
        order.removeAll { $0 == id }
        order.append(id)
    }
}
