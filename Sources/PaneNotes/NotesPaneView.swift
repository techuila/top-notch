import NotchCore
import SwiftUI

/// The whole pane: list, editor, confirmations and failures.
struct NotesPaneView: View {
    @Bindable var store: NotesStore
    @Namespace private var titleGeometry

    var body: some View {
        ZStack(alignment: .top) {
            if store.showsEditor {
                editor
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .paneInsets()
        .overlay(alignment: .bottom) { footer }
        .notchAnimation(Motion.morph, value: store.showsEditor)
        .notchAnimation(Motion.content, value: store.items)
    }

    // MARK: List

    private var list: some View {
        ScrollView(.vertical) {
            VStack(spacing: Metrics.slotSpacing / 2) {
                ForEach(store.items) { item in
                    NoteRow(
                        item: item,
                        geometry: titleGeometry,
                        open: { store.open(item.id) }
                    )
                }
                newNoteRow
            }
            .padding(.bottom, Metrics.slotSpacing)
        }
        .scrollIndicators(.never)
    }

    private var newNoteRow: some View {
        NotchTile {
            HStack(spacing: Metrics.slotSpacing) {
                Image(systemName: "plus")
                    .font(Style.subtitle.weight(.semibold))
                Text(store.items.isEmpty ? "Write your first note" : "New note")
                    .font(Style.subtitle)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Style.inkMuted)
        }
        .contentShape(Rectangle())
        .onTapGesture { store.newNote() }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("New note")
    }

    // MARK: Editor

    private var editor: some View {
        VStack(alignment: .leading, spacing: Metrics.slotSpacing / 2) {
            HStack(spacing: Metrics.slotSpacing / 2) {
                NotchButton("chevron.left", size: 12) { store.closeEditor() }
                    .accessibilityLabel("Back to notes")

                editorTitleView

                Spacer(minLength: 0)

                if store.isSaving {
                    Circle()
                        .fill(Style.notesAccent)
                        .frame(width: 5, height: 5)
                        .transition(.opacity)
                        .accessibilityLabel("Saving")
                }

                if let item = store.editorItem {
                    NotchButton("trash", size: 12) { store.requestDelete(item.id) }
                        .accessibilityLabel("Delete note")
                }
            }

            NoteTextEditor(
                text: $store.draft,
                onCancel: { store.closeEditor() },
                onCommit: { store.closeEditor() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Style.tileRadius, style: .continuous)
                    .fill(Style.fill)
            )

            Text("esc closes, command return saves and closes")
                .font(Style.label)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Style.inkFaint)
        }
        .padding(.bottom, Metrics.slotSpacing / 2)
    }

    /// The row's title travels into the editor header rather than one fading out while
    /// another fades in.
    @ViewBuilder
    private var editorTitleView: some View {
        let title = Text(store.editorItem?.title ?? NotesStore.firstLine(of: store.draft))
            .font(Style.title)
            .foregroundStyle(Style.ink)
            .lineLimit(1)
            .truncationMode(.tail)
        if let id = store.editorNoteID {
            title.matchedGeometryEffect(id: id, in: titleGeometry, isSource: false)
        } else {
            title
        }
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

// MARK: - Row

private struct NoteRow: View {
    let item: NoteItem
    let geometry: Namespace.ID
    let open: () -> Void

    var body: some View {
        NotchTile {
            HStack(spacing: Metrics.slotSpacing) {
                Text(item.title)
                    .font(Style.subtitle)
                    .foregroundStyle(Style.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .matchedGeometryEffect(id: item.id, in: geometry, isSource: true)
                Spacer(minLength: 0)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(.isButton)
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
                    .onTapGesture(perform: cancel)
                Text("Delete")
                    .font(Style.subtitle.weight(.semibold))
                    .foregroundStyle(Style.danger)
                    .contentShape(Rectangle())
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
                    .onTapGesture(perform: dismiss)
            }
        }
    }
}
