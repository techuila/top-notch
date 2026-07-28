import SwiftUI

/// The four panes, in the order they appear when scrolling sideways.
public enum PaneID: String, CaseIterable, Identifiable, Sendable {
    case music, drop, notes, focus

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .music: "Music"
        case .drop:  "Drop"
        case .notes: "Notes"
        case .focus: "Focus"
        }
    }

    /// SF Symbol shown in the idle bar when this pane is the focused identity.
    public var glyph: String {
        switch self {
        case .music: "music.note"
        case .drop:  "square.stack.3d.up"
        case .notes: "pencil.and.scribble"
        case .focus: "timer"
        }
    }
}

/// A single renderable item for one of the idle slots.
///
/// Panes describe what they want shown; the shell decides how to draw it. This keeps
/// every idle indicator visually consistent and stops panes from styling the notch.
public enum IdleItem: Equatable, Sendable {
    /// Album artwork. The shell rounds and shadows it.
    case artwork(NotchImage?)
    /// Live audio levels, 0...1, drawn as the waveform. Five values is the house standard.
    case waveform([Float])
    /// A progress ring with a short label beside it, used by a running pomodoro.
    case ring(progress: Double, label: String)
    /// An SF Symbol plus a short value, e.g. a file count.
    case badge(symbol: String, text: String)
    /// A bare SF Symbol, used as the focused identity when there is nothing richer.
    case glyph(String)
}

/// What a pane publishes to the idle notch.
///
/// See OPINIONS.md for the locked rules the shell applies to these. In short: a running
/// pomodoro owns the outer-left slot permanently, the focused pane supplies the inner-left
/// identity, and everything else queues into the rotating right slot.
public struct IdleSignal: Equatable, Sendable {
    /// True when this pane has live state worth focusing on. Drives the focus rule.
    public var isLive: Bool

    /// Higher wins when several panes are live. Music is 100, a running pomodoro is 90.
    public var priority: Int

    /// Claims the permanent outer-left slot. Only a running pomodoro may set this.
    public var pinnedLeading: IdleItem?

    /// This pane's identity when it is the focused one, shown in the inner-left slot.
    public var identity: IdleItem?

    /// This pane's live value, queued into the rotating right slot.
    public var rotating: IdleItem?

    /// 0...1, drives the progress line along the notch bottom edge. Only the focused
    /// pane's value is used. `nil` hides the line.
    public var progress: Double?

    public static let inactive = IdleSignal(isLive: false, priority: 0)

    public init(
        isLive: Bool,
        priority: Int,
        pinnedLeading: IdleItem? = nil,
        identity: IdleItem? = nil,
        rotating: IdleItem? = nil,
        progress: Double? = nil
    ) {
        self.isLive = isLive
        self.priority = priority
        self.pinnedLeading = pinnedLeading
        self.identity = identity
        self.rotating = rotating
        self.progress = progress
    }
}

/// Implemented once per feature module. The shell owns everything else.
///
/// Conformers must be `@MainActor` and `@Observable` so the shell re-renders when
/// `idle` or `contentHeight` changes.
@MainActor
public protocol NotchPane: AnyObject {
    var id: PaneID { get }

    /// Height this pane wants for its content area, excluding the pill row and padding.
    /// The panel animates its total height to match. Keep it stable; changing it on every
    /// keystroke will make the panel breathe.
    var contentHeight: CGFloat { get }

    /// What this pane wants shown while the notch is closed.
    var idle: IdleSignal { get }

    /// The expanded content. Sized to the full panel width; use `Metrics.paneInset`
    /// for horizontal padding rather than inventing your own.
    @ViewBuilder func content() -> AnyView

    /// Called when the pane scrolls into view. Start observers and timers here.
    func activate()

    /// Called when the pane scrolls away or the notch closes. Stop anything expensive.
    /// Anything that must keep running while closed belongs in a service, not here.
    func deactivate()
}

public extension NotchPane {
    func activate() {}
    func deactivate() {}
}
