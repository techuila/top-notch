import SwiftUI

/// The three states the notch moves through. Panes can read the current one from the
/// environment if they want to lay themselves out differently while the panel is closing.
public enum NotchPhase: Equatable, Sendable {
    case idle
    case proximity
    case expanded

    public var isExpanded: Bool { self == .expanded }
}

/// Identifiers for the elements that travel between the idle bar and the expanded panel.
///
/// The shell owns the source anchors for all three and renders the moving views itself.
/// A pane that wants one of them to land somewhere specific attaches
/// `.matchedGeometryEffect(id: NotchTravelID.artwork.rawValue, in: namespace, isSource: false)`
/// to its own view, reading the namespace from `\.notchNamespace`.
public enum NotchTravelID: String, Hashable, Sendable, CaseIterable {
    case artwork
    case waveform
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
