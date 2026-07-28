import NotchCore
import SwiftUI

/// STUB. Owned by the pomodoro agent, which replaces this file and adds the rest of
/// the module. Keep the type name and the `NotchPane` conformance.
@MainActor
@Observable
public final class FocusPane: NotchPane {
    public let id: PaneID = .focus
    public var contentHeight: CGFloat { 132 }
    public var idle: IdleSignal { .inactive }

    public init() {}

    public func content() -> AnyView {
        AnyView(
            Text("Focus").font(Style.title).foregroundStyle(Style.inkMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
    }
}
