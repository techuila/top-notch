import AppKit
import Foundation
import NotchCore
import SwiftUI

/// The temporary file shelf.
///
/// Files dropped at the notch are copied into a scratch directory, parked for a day, and
/// dragged back out into any app as real files. The user's originals are only ever read.
@MainActor
@Observable
public final class DropPane: NotchPane {
    public let id: PaneID = .drop

    public var contentHeight: CGFloat {
        DropLayout.headerHeight + DropLayout.headerGap + DropLayout.shelfHeight
    }

    /// Live whenever something is parked, so the notch can say so while closed. The count
    /// rides the rotating right slot; the glyph is the identity when this pane is focused.
    public var idle: IdleSignal {
        let count = shelf.items.count
        return IdleSignal(
            isLive: count > 0,
            priority: 40,
            pinnedLeading: nil,
            identity: .glyph(PaneID.drop.glyph),
            rotating: count > 0 ? .badge(symbol: PaneID.drop.glyph, text: "\(count)") : nil,
            progress: nil
        )
    }

    let shelf: DropShelf

    public init() {
        shelf = DropShelf()
        // Restores the shelf and destroys whatever expired while the app was not running.
        // This happens at launch rather than on first activation, because the idle count
        // has to be right before the pane is ever opened.
        shelf.load()
    }

    public func content() -> AnyView {
        AnyView(
            DropWell(
                shelf: shelf,
                fallbackSize: CGSize(width: Metrics.expandedWidth, height: contentHeight)
            ) {
                DropShelfView(shelf: shelf)
            }
        )
    }

    // MARK: Shell interface

    /// Called the moment a drag enters the notch, collapsed or not.
    ///
    /// The shell sets this to whatever opens the panel and selects the drop pane. It fires
    /// on `draggingEntered`, before any drop, which is the whole point: the notch is closed
    /// and tiny when a drag starts, so it has to open itself and reveal the target rather
    /// than wait for a hover that never comes while the mouse button is down.
    public var onDragRequestsExpand: (() -> Void)? {
        get { shelf.onDragRequestsExpand }
        set { shelf.onDragRequestsExpand = newValue }
    }

    /// An invisible drag destination for the shell to place over the collapsed notch, and
    /// ideally over a band a little wider and taller than it, so a drag heading for the top
    /// of the screen is caught before the cursor is exactly on the housing.
    ///
    /// It draws nothing and takes whatever frame it is given. It accepts file URLs and
    /// file promises, and it is what makes the notch open on drag.
    public func dragWell() -> AnyView {
        AnyView(
            DropWell(
                shelf: shelf,
                fallbackSize: CGSize(width: Metrics.expandedWidth, height: Metrics.idleHeight)
            ) {
                Color.clear
            }
        )
    }

    /// True while a drag is over either drop target. The shell can hold the panel open on
    /// this rather than on cursor proximity, which does not apply during a drag.
    public var isDragTargeted: Bool { shelf.isTargeted }

    /// How many files are parked. Same number the idle badge shows.
    public var itemCount: Int { shelf.items.count }
}
