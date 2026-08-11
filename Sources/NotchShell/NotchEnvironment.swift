import SwiftUI

/// The three states the notch moves through. Panes can read the current one from the
/// environment if they want to lay themselves out differently while the panel is closing.
public enum NotchPhase: Equatable, Sendable {
    case idle
    case proximity
    case expanded

    public var isExpanded: Bool { self == .expanded }
}

/// Identifier for the one element that persists across the idle bar and the expanded
/// panel: the bottom-edge progress line. Artwork and waveform used to travel too; the
/// open and close morphs are now a pure expand and shrink (owner decision), so each
/// state draws those in place and only the border line is matched between layouts.
public enum NotchTravelID: String, Hashable, Sendable, CaseIterable {
    case progress
}

private struct NotchNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

private struct NotchPhaseKey: EnvironmentKey {
    static let defaultValue: NotchPhase = .idle
}

public extension EnvironmentValues {
    /// The shared `matchedGeometryEffect` namespace used for the idle-to-expanded travel.
    /// `nil` only when a pane is previewed outside the shell.
    var notchNamespace: Namespace.ID? {
        get { self[NotchNamespaceKey.self] }
        set { self[NotchNamespaceKey.self] = newValue }
    }

    /// The state the notch is currently in.
    var notchPhase: NotchPhase {
        get { self[NotchPhaseKey.self] }
        set { self[NotchPhaseKey.self] = newValue }
    }
}
