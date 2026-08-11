import SwiftUI

/// The three states the notch moves through. Panes can read the current one from the
/// environment if they want to lay themselves out differently while the panel is closing.
public enum NotchPhase: Equatable, Sendable {
    case idle
    case proximity
    case expanded

    public var isExpanded: Bool { self == .expanded }
}

/// Identifiers for the matched elements that persist across the idle bar and the
/// expanded panel: the album art and the waveform, each one instance morphing between
/// its idle slot and its place in the music pane (owner decision, 2026-08-12:
/// components that exist in both states travel to their place, they never hide and
/// show). The bottom-edge progress line persists too, but is laid out directly by the
/// travel layer against the live surface instead of being matched.
public enum NotchTravelID: String, Hashable, Sendable, CaseIterable {
    case artwork
    case waveform
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
