import NotchCore
import SwiftUI

/// The whole pane: a grid of cards, and the one card that has grown into the editor.
///
/// A note is a card. Pressing it grows that card into the editor; closing the editor
/// shrinks it back into place. The card and the editor share one matched-geometry
/// identity, so what is on screen is one surface changing size, never a list swapped
/// for a form.
///
/// Dragging a card lifts it off the grid, tilted, and carries it; a dashed slot shows
/// where it will land. The lifted card and the card that settles back into the grid are
/// again one matched identity, so the drop is a landing, not a swap.
struct NotesPaneView: View {
    @Bindable var store: NotesStore
    @Namespace private var cardGeometry
    @State private var editor = NoteEditorProxy()

    @State private var drag: CardDrag?
    @State private var frames: [UUID: CGRect] = [:]
    @State private var gridWidth: CGFloat = 0

    nonisolated private static let gridSpace = "notes.grid"

    var body: some View {
        ZStack(alignment: .top) {
            if store.showsEditor {
                editorCard
            } else {
                grid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .paneInsets()
        .overlay(alignment: .bottom) { footer }
        .notchAnimation(Motion.morph, value: store.showsEditor)
        .notchAnimation(Motion.content, value: store.items)
    }

    // MARK: Cards

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: Metrics.listRowSpacing),
            GridItem(.flexible(), spacing: Metrics.listRowSpacing),
        ]
    }

    /// What the grid shows: every card except the one in the air, with the dashed slot
    /// standing where that card will land.
    private var slots: [CardSlot] {
        var items = store.items
        guard let drag, let lifted = items.firstIndex(where: { $0.id == drag.id }) else {
            return items.map(CardSlot.card) + [.new]
        }
        items.remove(at: lifted)
        var slots = items.map(CardSlot.card)
        slots.insert(.placeholder, at: min(max(drag.target, 0), slots.count))
        return slots + [.new]
    }

    private var grid: some View {
        ScrollView(.vertical) {
            LazyVGrid(columns: columns, spacing: Metrics.listRowSpacing) {
                ForEach(slots) { slot in
                    switch slot {
                    case .card(let item):
                        NoteCard(item: item, lifted: false)
                            .contentShape(Rectangle())
                            .onTapGesture { store.open(item.id) }
                            .gesture(liftGesture(for: item))
                            .onGeometryChange(for: CGRect.self) {
                                $0.frame(in: .named(Self.gridSpace))
                            } action: { frames[item.id] = $0 }
                            .matchedGeometryEffect(id: item.id.uuidString, in: cardGeometry)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(item.title)
                            .accessibilityAddTraits(.isButton)
                    case .placeholder:
                        LandingSlot()
                    case .new:
                        newNoteCard
                            .matchedGeometryEffect(id: NotesStore.newCardOrigin, in: cardGeometry)
                    }
                }
            }
            .padding(.bottom, Metrics.slotSpacing)
            .coordinateSpace(name: Self.gridSpace)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
            .overlay(alignment: .topLeading) { liftedCard }
            .notchAnimation(Motion.content, value: drag?.target)
        }
        .scrollIndicators(.never)
        .scrollDisabled(drag != nil)
    }

    /// The card in the air, drawn over the grid at the pointer.
    @ViewBuilder
    private var liftedCard: some View {
        if let drag, let item = store.items.first(where: { $0.id == drag.id }) {
            NoteCard(item: item, lifted: true)
                .frame(width: drag.size.width, height: drag.size.height)
                .rotationEffect(.degrees(NotesLayout.liftTilt))
                .scaleEffect(NotesLayout.liftScale)
                .shadow(color: .black.opacity(0.45), radius: 14, y: 8)
                .offset(x: drag.origin.x, y: drag.origin.y)
                .matchedGeometryEffect(id: item.id.uuidString, in: cardGeometry)
                .allowsHitTesting(false)
                .transition(.identity)
        }
    }

    private var newNoteCard: some View {
        NotchTile {
            VStack(alignment: .leading, spacing: Metrics.spacingTight) {
                Image(systemName: "plus")
                    .font(Style.subtitle.weight(.semibold))
                Text(store.items.isEmpty ? "Write your first note" : "New note")
                    .font(Style.subtitle)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Style.inkMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: NotesLayout.cardBodyHeight)
        }
        .contentShape(Rectangle())
        .onTapGesture { store.newNote() }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("New note")
    }

    // MARK: Lifting and dropping

    /// A drag lifts the card the moment it moves and carries it from there. The few
    /// points of slack are what keep a plain press a tap that opens the note.
    private func liftGesture(for item: NoteItem) -> some Gesture {
        DragGesture(minimumDistance: NotesLayout.liftSlack, coordinateSpace: .named(Self.gridSpace))
            .onChanged { value in
                if drag == nil {
                    lift(item, at: value.startLocation)
                }
                carry(to: value.location)
            }
            .onEnded { _ in drop() }
    }

    private func lift(_ item: NoteItem, at point: CGPoint) {
        guard let frame = frames[item.id] else { return }
        let grab = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
        let index = store.items.firstIndex(where: { $0.id == item.id }) ?? 0
        NotchHaptics.lift()
        withAnimation(Motion.reduced(Motion.tap)) {
            drag = CardDrag(id: item.id, size: frame.size, grab: grab, origin: frame.origin, target: index)
        }
    }

    private func carry(to point: CGPoint) {
        guard var current = drag else { return }
        current.origin = CGPoint(x: point.x - current.grab.x, y: point.y - current.grab.y)
        let target = slotIndex(at: point, cardHeight: current.size.height)
        if target != current.target {
            current.target = target
            NotchHaptics.snap()
        }
        drag = current
    }

    private func drop() {
        guard let current = drag else { return }
        NotchHaptics.drop()
        withAnimation(Motion.reduced(Motion.content)) {
            store.move(current.id, to: current.target)
            drag = nil
        }
    }

    /// Which slot the pointer is over: two columns, rows of one card height.
    private func slotIndex(at point: CGPoint, cardHeight: CGFloat) -> Int {
        let last = max(store.items.count - 1, 0)
        guard gridWidth > 0, cardHeight > 0 else { return 0 }
        let column = point.x < gridWidth / 2 ? 0 : 1
        let row = max(Int((point.y / (cardHeight + Metrics.listRowSpacing)).rounded(.down)), 0)
        return min(row * 2 + column, last)
    }

    // MARK: Editor

    /// The opened card. Header, the markdown view, and the key hint, all on one tile so
    /// the tile is what the card grows into.
    private var editorCard: some View {
        NotchTile(interactive: false) {
            VStack(alignment: .leading, spacing: Metrics.spacingSnug) {
                HStack(spacing: Metrics.spacingTight) {
                    NotchButton("chevron.left", size: NotesLayout.headerControl) { store.closeEditor() }
                        .accessibilityLabel("Back to notes")

                    editorTitleView

                    Spacer(minLength: Metrics.spacingSnug)

                    formattingBar

                    if store.isSaving {
                        Circle()
                            .fill(Style.notesAccent)
                            .frame(width: NotesLayout.savingDot, height: NotesLayout.savingDot)
                            .transition(.opacity)
                            .accessibilityLabel("Saving")
                    }

                    if let item = store.editorItem {
                        NotchButton("trash", size: NotesLayout.headerControl) { store.requestDelete(item.id) }
                            .accessibilityLabel("Delete note")
                    }
                }

                NoteTextEditor(
                    text: $store.draft,
                    proxy: editor,
                    onCancel: { store.closeEditor() },
                    onCommit: { store.closeEditor() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                NotchLabel("markdown. esc closes, command return saves")
            }
        }
        .matchedGeometryEffect(id: store.editorOrigin, in: cardGeometry)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, Metrics.slotSpacing / 2)
    }

    /// The same formatting Apple Notes puts in its toolbar, as markdown.
    private var formattingBar: some View {
        HStack(spacing: 0) {
            NotchButton("bold", size: NotesLayout.formatControl) { editor.bold() }
                .accessibilityLabel("Bold")
            NotchButton("italic", size: NotesLayout.formatControl) { editor.italic() }
                .accessibilityLabel("Italic")
            NotchButton("strikethrough", size: NotesLayout.formatControl) { editor.strikethrough() }
                .accessibilityLabel("Strikethrough")
            NotchButton("list.bullet", size: NotesLayout.formatControl) { editor.bulletList() }
                .accessibilityLabel("Bulleted list")
            NotchButton("list.number", size: NotesLayout.formatControl) { editor.numberedList() }
                .accessibilityLabel("Numbered list")
        }
    }

    private var editorTitleView: some View {
        Text(store.editorItem?.title ?? NotesStore.firstLine(of: store.draft))
            .font(Style.subtitle.weight(.semibold))
            .foregroundStyle(Style.ink)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    // MARK: Footer: confirmations and failures

    @ViewBuilder
    private var footer: some View {
        if let id = store.pendingDeleteID {
            ConfirmStrip(
                confirm: { store.confirmDelete(id) },
                cancel: { store.cancelConfirmation() }
            )
            .paneInsets()
            .padding(.bottom, Metrics.slotSpacing / 2)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if let failure = store.failure {
            FailureStrip(
                failure: failure,
                dismiss: { store.dismissFailure() }
            )
            .paneInsets()
            .padding(.bottom, Metrics.slotSpacing / 2)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Drag state

/// A card in the air.
private struct CardDrag: Equatable {
    let id: UUID
    let size: CGSize
    /// Where inside the card it was grabbed, so it does not jump under the pointer.
    let grab: CGPoint
    /// The card's top-left in grid space.
    var origin: CGPoint
    /// The slot it will drop into.
    var target: Int
}

private enum CardSlot: Identifiable {
    case card(NoteItem)
    case placeholder
    case new

    var id: String {
        switch self {
        case .card(let item): item.id.uuidString
        case .placeholder:    "placeholder"
        case .new:            NotesStore.newCardOrigin
        }
    }
}

// MARK: - Card

/// One note at rest: title, a couple of lines of body, when it was last touched.
private struct NoteCard: View {
    let item: NoteItem
    /// In the air. The fill lifts a step, like a hover that will not end.
    let lifted: Bool

    var body: some View {
        NotchTile(interactive: !lifted) {
            VStack(alignment: .leading, spacing: Metrics.spacingTight) {
                Text(item.title)
                    .font(Style.subtitle.weight(.semibold))
                    .foregroundStyle(Style.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(item.preview.isEmpty ? "No additional text" : item.preview)
                    .font(Style.caption)
                    .foregroundStyle(item.preview.isEmpty ? Style.inkFaint : Style.inkMuted)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(item.modified, format: .relative(presentation: .named))
                    .font(Style.caption)
                    .foregroundStyle(Style.inkFaint)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: NotesLayout.cardBodyHeight)
        }
        .background(
            RoundedRectangle(cornerRadius: Style.tileRadius, style: .continuous)
                .fill(lifted ? Style.fillHover : .clear)
        )
    }
}

/// Where the lifted card will land: the outline of a card, dashed, nothing inside.
private struct LandingSlot: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Style.tileRadius, style: .continuous)
            .strokeBorder(Style.dashed, style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
            .frame(height: NotesLayout.cardBodyHeight + NotesLayout.tilePadding * 2)
            .accessibilityHidden(true)
    }
}

// MARK: - Strips

private struct ConfirmStrip: View {
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        NotchTile(interactive: false) {
            HStack(spacing: Metrics.slotSpacing) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(Style.subtitle.weight(.semibold))
                    .foregroundStyle(Style.danger)
                Text("Delete this note?")
                    .font(Style.subtitle)
                    .foregroundStyle(Style.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text("Cancel")
                    .font(Style.subtitle)
                    .foregroundStyle(Style.inkMuted)
                    .contentShape(Rectangle())
                    .notchPointer()
                    .onTapGesture(perform: cancel)
                Text("Delete")
                    .font(Style.subtitle.weight(.semibold))
                    .foregroundStyle(Style.danger)
                    .contentShape(Rectangle())
                    .notchPointer()
                    .onTapGesture(perform: confirm)
            }
        }
    }
}

private struct FailureStrip: View {
    let failure: NoteStoreError
    let dismiss: () -> Void

    var body: some View {
        NotchTile(interactive: false) {
            HStack(alignment: .top, spacing: Metrics.slotSpacing) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(Style.subtitle.weight(.semibold))
                    .foregroundStyle(Style.danger)
                Text(failure.message)
                    .font(Style.subtitle)
                    .foregroundStyle(Style.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text("Dismiss")
                    .font(Style.subtitle)
                    .foregroundStyle(Style.inkMuted)
                    .contentShape(Rectangle())
                    .notchPointer()
                    .onTapGesture(perform: dismiss)
            }
        }
    }
}

// MARK: - Layout

/// Sizes local to this pane's composition. Everything shared lives in `Metrics`.
private enum NotesLayout {
    /// Card content height: a title line, two preview lines and the date.
    static let cardBodyHeight: CGFloat = 60
    /// `NotchTile`'s vertical padding, mirrored so the landing slot is card-sized.
    /// NotchCore gap: the tile does not expose its padding.
    static let tilePadding: CGFloat = 9
    static let headerControl: CGFloat = 12
    static let formatControl: CGFloat = 10
    static let savingDot: CGFloat = 5

    /// Movement before a press becomes a drag. Under this it is a tap that opens the note.
    static let liftSlack: CGFloat = 6
    /// The lifted card leans a touch, the cue that it is loose and can be carried.
    static let liftTilt: Double = 2.5
    static let liftScale: Double = 1.04
}
