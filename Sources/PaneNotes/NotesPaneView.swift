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
        .onAppear { store.resolveTitlesIfNeeded() }
    }

    // MARK: List

    private var list: some View {
        ScrollView(.vertical) {
            VStack(spacing: Metrics.slotSpacing / 2) {
                ForEach(store.items) { item in
                    NoteRow(
                        item: item,
                        isUnlocking: store.unlockingNoteID == item.id,
                        geometry: titleGeometry,
                        open: { store.open(item.id) },
                        togglePrivacy: { store.requestPrivacyChange(item.id) }
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
                    NotchButton(item.isPrivate ? "lock.fill" : "lock.open", size: 12) {
                        store.requestPrivacyChange(item.id)
                    }
                    .accessibilityLabel(item.isPrivate ? "Make this note public" : "Lock this note")
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
        if let confirmation = store.pendingConfirmation {
            ConfirmStrip(
                confirmation: confirmation,
                confirm: { store.confirm(confirmation) },
                cancel: { store.cancelConfirmation() }
            )
            .paneInsets()
            .padding(.bottom, Metrics.slotSpacing / 2)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if let failure = store.failure {
            FailureStrip(
                failure: failure,
                retry: failure.isRetryable ? { store.retryUnlock() } : nil,
                reset: failure == .keyMissing ? { store.requestPrivateReset() } : nil,
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
    let isUnlocking: Bool
    let geometry: Namespace.ID
    let open: () -> Void
    let togglePrivacy: () -> Void

    var body: some View {
        NotchTile {
            HStack(spacing: Metrics.slotSpacing) {
                titleView
                Spacer(minLength: 0)
                trailing
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.title ?? "Locked private note")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var titleView: some View {
        if let title = item.title {
            Text(title)
                .font(Style.subtitle)
                .foregroundStyle(Style.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .matchedGeometryEffect(id: item.id, in: geometry, isSource: true)
        } else {
            // Deliberately hidden, not missing: a run of text the right rough width for
            // this note's title, blurred out. The width bucket is the only thing a
            // private note's file discloses.
            Text(NoteRow.redaction(for: item.titleHint))
                .font(Style.subtitle)
                .foregroundStyle(Style.ink.opacity(0.8))
                .lineLimit(1)
                .blur(radius: 3.4)
                .accessibilityHidden(true)
                .matchedGeometryEffect(id: item.id, in: geometry, isSource: true)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if isUnlocking {
            ProgressView()
                .controlSize(.mini)
                .tint(Style.notesAccent)
        } else if item.isPrivate {
            Image(systemName: item.title == nil ? "lock.fill" : "lock.open.fill")
                .font(Style.subtitle.weight(.semibold))
                .foregroundStyle(Style.notesAccent)
                .accessibilityLabel(item.title == nil ? "Locked" : "Unlocked")
        } else {
            NotchButton("lock.open", size: 11, action: togglePrivacy)
                .accessibilityLabel("Lock this note")
        }
    }

    /// Fixed strings, chosen by a coarse length bucket, so a locked row looks like a
    /// title without being derived from one.
    static func redaction(for hint: Int) -> String {
        switch max(0, min(3, hint)) {
        case 0: "Private"
        case 1: "Private note"
        case 2: "Private note, kept aside"
        default: "Private note, kept aside for later"
        }
    }
}

// MARK: - Strips

private struct ConfirmStrip: View {
    let confirmation: NotesConfirmation
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        NotchTile(interactive: false) {
            HStack(spacing: Metrics.slotSpacing) {
                Image(systemName: symbol)
                    .font(Style.subtitle.weight(.semibold))
                    .foregroundStyle(tint)
                Text(question)
                    .font(Style.subtitle)
                    .foregroundStyle(Style.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text("Cancel")
                    .font(Style.subtitle)
                    .foregroundStyle(Style.inkMuted)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: cancel)
                Text(action)
                    .font(Style.subtitle.weight(.semibold))
                    .foregroundStyle(tint)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: confirm)
            }
        }
    }

    private var symbol: String {
        switch confirmation {
        case .lock: "lock.fill"
        case .unlock: "lock.open.fill"
        case .delete, .resetPrivateNotes: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch confirmation {
        case .lock, .unlock: Style.notesAccent
        case .delete, .resetPrivateNotes: Style.danger
        }
    }

    private var question: String {
        switch confirmation {
        case .lock: "Lock this note? Touch ID will be needed to read it."
        case .unlock: "Remove the lock? Anyone at this Mac could read it."
        case .delete: "Delete this note?"
        case .resetPrivateNotes: "Delete every unreadable private note?"
        }
    }

    private var action: String {
        switch confirmation {
        case .lock: "Lock"
        case .unlock: "Unlock"
        case .delete: "Delete"
        case .resetPrivateNotes: "Delete"
        }
    }
}

private struct FailureStrip: View {
    let failure: NoteLockError
    let retry: (() -> Void)?
    let reset: (() -> Void)?
    let dismiss: () -> Void

    var body: some View {
        NotchTile(interactive: false) {
            HStack(alignment: .top, spacing: Metrics.slotSpacing) {
                Image(systemName: "lock.trianglebadge.exclamationmark")
                    .font(Style.subtitle.weight(.semibold))
                    .foregroundStyle(Style.danger)
                Text(failure.message)
                    .font(Style.subtitle)
                    .foregroundStyle(Style.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    if let retry {
                        Text("Try again")
                            .font(Style.subtitle.weight(.semibold))
                            .foregroundStyle(Style.notesAccent)
                            .contentShape(Rectangle())
                            .onTapGesture(perform: retry)
                    }
                    if let reset {
                        Text("Reset")
                            .font(Style.subtitle.weight(.semibold))
                            .foregroundStyle(Style.danger)
                            .contentShape(Rectangle())
                            .onTapGesture(perform: reset)
                    }
                    Text("Dismiss")
                        .font(Style.subtitle)
                        .foregroundStyle(Style.inkMuted)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: dismiss)
                }
            }
        }
    }
}
