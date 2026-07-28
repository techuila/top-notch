import NotchCore
import SwiftUI

/// STUB. Owned by the quick-notes agent, which replaces this file and adds the rest of
/// the module. Keep the type name and the `NotchPane` conformance.
@MainActor
@Observable
public final class NotesPane: NotchPane {
    public let id: PaneID = .notes
    public var contentHeight: CGFloat { 142 }
    public var idle: IdleSignal { .inactive }

    public init() {}

    public func content() -> AnyView {
        AnyView(
            Text("Notes").font(Style.title).foregroundStyle(Style.inkMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
    }
}
