import NotchCore
import SwiftUI

/// STUB. Owned by the drop-shelf agent, which replaces this file and adds the rest of
/// the module. Keep the type name and the `NotchPane` conformance.
@MainActor
@Observable
public final class DropPane: NotchPane {
    public let id: PaneID = .drop
    public var contentHeight: CGFloat { 102 }
    public var idle: IdleSignal { .inactive }

    public init() {}

    public func content() -> AnyView {
        AnyView(
            Text("Drop").font(Style.title).foregroundStyle(Style.inkMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
    }
}
