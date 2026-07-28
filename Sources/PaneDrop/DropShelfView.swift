import AppKit
import Foundation
import NotchCore
import SwiftUI

/// Sizes that only exist inside this pane. Anything a second pane would want belongs in
/// `Metrics` instead, so these stay deliberately private to the drop shelf.
enum DropLayout {
    static let headerHeight: CGFloat = 22
    static let headerGap: CGFloat = 6
    static let shelfHeight: CGFloat = 74

    static let chipWidth: CGFloat = 152
    static let chipHeight: CGFloat = 50
    static let chipSpacing: CGFloat = 8
    static let chipLift: CGFloat = 4
    static let thumbnailSide: CGFloat = 30
    /// Style has no radius small enough for a 30pt thumbnail; the smallest is 10.
    static let thumbnailRadius: CGFloat = 3

    static let dashPattern: [CGFloat] = [5, 4]
    static let dashWidth: CGFloat = 1.2
}

/// The expanded pane: a header, then the drop target with the parked files inside it.
///
/// The dashed target is always present rather than appearing when the shelf empties, so
/// nothing swaps in or out as the last file leaves. It brightens and the panel lifts the
/// instant a drag is over it.
struct DropShelfView: View {
    let shelf: DropShelf

    var body: some View {
        VStack(alignment: .leading, spacing: DropLayout.headerGap) {
            header
            target
        }
        .padding(.horizontal, Metrics.paneInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            NotchLabel("Shelf")
            Text(summary)
                .font(Style.numeric)
                .foregroundStyle(Style.inkFaint)
                .contentTransition(.numericText())
            Spacer(minLength: 8)
            if !shelf.items.isEmpty {
                DragAllHandle(shelf: shelf)
                NotchButton("trash", size: 10) { shelf.clear() }
                    .accessibilityLabel("Clear the shelf")
            }
        }
        .frame(height: DropLayout.headerHeight)
        .notchAnimation(Motion.tap, value: shelf.items.count)
    }

    private var summary: String {
        guard !shelf.items.isEmpty else { return "Empty" }
        let count = shelf.items.count
        let noun = count == 1 ? "item" : "items"
        return "\(count) \(noun) · \(shelf.totalBytes.formatted(.byteCount(style: .file)))"
    }

    // MARK: Drop target

    private var target: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Style.cardRadius, style: .continuous)
                .strokeBorder(
                    shelf.isTargeted ? Style.dropAccent : Style.dashed,
                    style: StrokeStyle(
                        lineWidth: DropLayout.dashWidth,
                        dash: DropLayout.dashPattern
                    )
                )
                .background(
                    RoundedRectangle(cornerRadius: Style.cardRadius, style: .continuous)
                        .fill(Style.dropAccent.opacity(shelf.isTargeted ? 0.10 : 0))
                )

            prompt.opacity(shelf.items.isEmpty ? 1 : 0)
            chips.opacity(shelf.items.isEmpty ? 0 : 1)
        }
        .frame(height: DropLayout.shelfHeight)
        .scaleEffect(shelf.isTargeted ? 1.02 : 1)
        .shadow(
            color: Style.dropAccent.opacity(shelf.isTargeted ? 0.28 : 0),
            radius: shelf.isTargeted ? 14 : 0,
            y: shelf.isTargeted ? 4 : 0
        )
        .notchAnimation(Motion.tap, value: shelf.isTargeted)
        .notchAnimation(Motion.content, value: shelf.items.isEmpty)
    }

    private var prompt: some View {
        VStack(spacing: 3) {
            Image(systemName: PaneID.drop.glyph)
                .font(Style.title)
                .foregroundStyle(shelf.isTargeted ? Style.dropAccent : Style.inkFaint)
            Text(shelf.isTargeted ? "Release to park" : "Drop files here")
                .font(Style.subtitle)
                .foregroundStyle(Style.inkMuted)
            Text("Kept for 24 hours")
                .font(Style.label)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Style.inkFaint)
        }
        .accessibilityElement(children: .combine)
    }

    /// Scrolls sideways once the chips outrun the panel. No indicator ever shows.
    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: DropLayout.chipSpacing) {
                ForEach(shelf.items) { item in
                    FileChip(item: item) { shelf.remove(item) }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: DropLayout.shelfHeight)
        }
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
}

/// One parked file. Hovering lifts it and reveals the remove control; dragging it out
/// hands the receiving app a real file URL with the thumbnail as the drag image.
struct FileChip: View {
    let item: ShelfItem
    let onRemove: () -> Void

    @State private var thumbnail: NSImage?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            thumbnailView
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(Style.subtitle)
                    .foregroundStyle(Style.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.sizeText)
                    .font(Style.numeric)
                    .foregroundStyle(Style.inkFaint)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(width: DropLayout.chipWidth, height: DropLayout.chipHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Style.tileRadius, style: .continuous)
                .fill(hovering ? Style.fillHover : Style.fill)
        )
        .overlay(alignment: .topTrailing) {
            NotchButton("xmark", size: 8, action: onRemove)
                .accessibilityLabel("Remove \(item.name)")
                .opacity(hovering ? 1 : 0)
                .scaleEffect(hovering ? 1 : 0.7)
                .offset(x: 6, y: -6)
                .allowsHitTesting(hovering)
        }
        .offset(y: hovering ? -DropLayout.chipLift : 0)
        .shadow(color: .black.opacity(hovering ? 0.4 : 0), radius: hovering ? 10 : 0, y: 4)
        .onHover { hovering = $0 }
        .notchAnimation(Motion.tap, value: hovering)
        .task(id: item.id) { thumbnail = await ThumbnailCache.shared.image(for: item) }
        .onDrag(provider) { dragPreview }
        .accessibilityLabel("\(item.name), \(item.sizeText)")
    }

    /// A real file URL. The receiving app sees a genuine file drag and copies it out of
    /// the scratch directory, so Finder, Mail and a browser upload field all behave.
    private func provider() -> NSItemProvider {
        let provider = NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        provider.suggestedName = item.name
        return provider
    }

    private var dragPreview: some View {
        thumbnailImage
            .frame(width: ShelfDragSourceView.dragImageSide, height: ShelfDragSourceView.dragImageSide)
    }

    private var thumbnailView: some View {
        thumbnailImage
            .frame(width: DropLayout.thumbnailSide, height: DropLayout.thumbnailSide)
    }

    @ViewBuilder
    private var thumbnailImage: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: DropLayout.thumbnailRadius, style: .continuous))
        } else {
            Image(systemName: item.isDirectory ? "folder" : "doc")
                .font(Style.title)
                .foregroundStyle(Style.inkFaint)
        }
    }
}

/// Takes the whole shelf out in one drag.
struct DragAllHandle: View {
    let shelf: DropShelf

    @State private var hovering = false

    var body: some View {
        ShelfDragSource(payload: payload, onHover: { hovering = $0 }) {
            HStack(spacing: 4) {
                Image(systemName: "square.and.arrow.up")
                    .font(Style.label)
                Text("Drag all")
                    .font(Style.label)
                    .tracking(1.2)
                    .textCase(.uppercase)
            }
            .foregroundStyle(hovering ? Style.ink : Style.inkFaint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Capsule().fill(hovering ? Style.fillHover : Style.fill)
            )
            .notchAnimation(Motion.tap, value: hovering)
        }
        .frame(width: 74, height: DropLayout.headerHeight)
        .accessibilityLabel("Drag every item off the shelf")
    }

    /// Built on the main actor at drag time from whatever thumbnails are already cached,
    /// so starting a drag never waits on a render.
    private func payload() -> [(url: URL, image: NSImage?)] {
        shelf.items.map { ($0.url, ThumbnailCache.shared.cached($0.id)) }
    }
}
