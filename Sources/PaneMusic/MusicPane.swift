import NotchCore
import SwiftUI

/// STUB. Owned by the music agent, which replaces this file and adds the rest of the module.
/// Keep the type name and the `NotchPane` conformance; the app target constructs this.
@MainActor
@Observable
public final class MusicPane: NotchPane {
    public let id: PaneID = .music
    public var contentHeight: CGFloat { 114 }
    public var idle: IdleSignal { .inactive }

    public init() {}

    public func content() -> AnyView {
        AnyView(
            Text("Music").font(Style.title).foregroundStyle(Style.inkMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
    }
}
