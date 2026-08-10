import AppKit
import Foundation
import NotchCore
import SwiftUI

/// Sizes that only exist inside this pane. Anything a second pane would want belongs in
/// `Metrics` instead, so these stay deliberately private to the drop shelf.
enum DropLayout {
    static let headerHeight: CGFloat = 22
    static let headerGap: CGFloat = 6

    static let chipHeight: CGFloat = 30
    /// Gap between two chips in the same row.
    static let columnSpacing: CGFloat = 8
    static let rowSpacing: CGFloat = 6
    /// Breathing room inside the dashed target, and the headroom a hovered chip lifts into.
    static let shelfPadding: CGFloat = 4
    static let shelfInset: CGFloat = 8
    static let chipLift: CGFloat = 3
    static let removeSlot: CGFloat = 22

    static let thumbnailSide: CGFloat = 22
    /// Style has no radius small enough for a 22pt thumbnail; the smallest is 10.
    static let thumbnailRadius: CGFloat = 3

    static let dashPattern: [CGFloat] = [5, 4]
    static let dashWidth: CGFloat = 1.2

    /// Chips wrap into this many columns. Fixed rather than adaptive so the row count,
    /// and therefore the panel height, is known without measuring anything.
    static let columns = 2
    /// Rows shown before the shelf starts scrolling.
    static let visibleRows = 2

    static func rows(for count: Int) -> Int {
        max(1, Int((Double(count) / Double(columns)).rounded(.up)))
    }

    /// Height of the shelf itself, which stops growing at `visibleRows`.
    static func shelfHeight(rows: Int) -> CGFloat {
        gridHeight(rows: min(max(rows, 1), visibleRows))
    }

    /// Height of every row there is. Anything over `shelfHeight` scrolls.
    static func gridHeight(rows: Int) -> CGFloat {
        let count = CGFloat(max(rows, 1))
        return shelfPadding * 2 + count * chipHeight + (count - 1) * rowSpacing
    }

    /// What the pane asks the panel for. Two values only, 66 for one row and 102 for two,
    /// so the panel grows once when the third file lands and never breathes after that.
    static func contentHeight(for count: Int) -> CGFloat {
        headerHeight + headerGap + shelfHeight(rows: rows(for: count))
    }
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
        .frame(height: DropLayout.shelfHeight(rows: rows))
        .scaleEffect(shelf.isTargeted ? 1.02 : 1)
        .shadow(
            color: Style.dropAccent.opacity(shelf.isTargeted ? 0.28 : 0),
            radius: shelf.isTargeted ? 14 : 0,
            y: shelf.isTargeted ? 4 : 0
        )
        .notchAnimation(Motion.tap, value: shelf.isTargeted)
        .notchAnimation(Motion.morph, value: rows)
        .notchAnimation(Motion.content, value: shelf.items.isEmpty)
    }

    private var rows: Int { DropLayout.rows(for: shelf.items.count) }

    /// One line, because an empty shelf is one row tall. The panel grows into two rows on
    /// the third file rather than starting tall and shrinking.
    private var prompt: some View {
        HStack(spacing: 7) {
            Image(systemName: PaneID.drop.glyph)
                .font(Style.subtitle)
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

    /// Chips wrap into rows and scroll vertically once they outrun two of them.
    ///
    /// Vertical on purpose, and enforced by `ShelfScrollView` rather than assumed:
    /// horizontal scroll and swipe belong to the shell for moving between panes.
    ///
    /// Rows are laid out explicitly instead of with a grid, because the pane has to know
    /// the exact height of the whole thing to tell the scroll view what overflows and to
    /// tell the panel how tall to be.
    private var chips: some View {
        ChipScroller(documentHeight: DropLayout.gridHeight(rows: rows)) {
            VStack(spacing: DropLayout.rowSpacing) {
                ForEach(ChipRow.rows(for: shelf.items)) { row in
                    HStack(spacing: DropLayout.columnSpacing) {
                        ForEach(row.items) { item in
                            FileChip(item: item) { shelf.remove(item) }
                        }
                        // Keeps a lone chip on the last row the same width as the ones
                        // above it rather than letting it stretch across.
                        ForEach(0..<row.padding, id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                        }
                    }
                }
            }
            .padding(.horizontal, DropLayout.shelfInset)
            .padding(.vertical, DropLayout.shelfPadding)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}

/// One row of the wrapped chip grid.
struct ChipRow: Identifiable {
    let id: UUID
    let items: [ShelfItem]

    /// Empty columns needed to fill the row out.
    var padding: Int { DropLayout.columns - items.count }

    static func rows(for items: [ShelfItem]) -> [ChipRow] {
        stride(from: 0, to: items.count, by: DropLayout.columns).map { start in
            let slice = Array(items[start..<min(start + DropLayout.columns, items.count)])
            return ChipRow(id: slice[0].id, items: slice)
        }
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
        HStack(spacing: 7) {
            thumbnailView
            Text(item.name)
                .font(Style.subtitle)
                .foregroundStyle(Style.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Text(item.sizeText)
                .font(Style.numeric)
                .foregroundStyle(Style.inkFaint)
                .layoutPriority(1)
            // The slot is always here, empty until the chip is hovered, so revealing the
            // control never reflows the row or overlaps the size.
            NotchButton("xmark", size: 8, action: onRemove)
                .accessibilityLabel("Remove \(item.name)")
                .frame(width: DropLayout.removeSlot)
                .opacity(hovering ? 1 : 0)
                .scaleEffect(hovering ? 1 : 0.7)
                .allowsHitTesting(hovering)
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(height: DropLayout.chipHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Style.tileRadius, style: .continuous)
                .fill(hovering ? Style.fillHover : Style.fill)
        )
        .offset(y: hovering ? -DropLayout.chipLift : 0)
        .shadow(color: .black.opacity(hovering ? 0.4 : 0), radius: hovering ? 10 : 0, y: 3)
        .onHover { hovering = $0 }
        // The full name, because long names truncate in the middle. On every chip rather
        // than only truncated ones: whether a name fits is layout state SwiftUI does not
        // expose, and a tooltip on a short name costs nothing.
        .help(item.name)
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
