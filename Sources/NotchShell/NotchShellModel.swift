import NotchCore
import SwiftUI

/// One resolved idle slot: the item plus the pane that published it, so the shell can
/// tint it with that feature's accent without the pane styling the notch itself.
struct IdleEntry: Equatable {
    var pane: PaneID
    var item: IdleItem
}

/// The idle bar, resolved from every pane's `IdleSignal` by the locked rules in DECISIONS.
struct IdleComposition: Equatable {
    var pinned: IdleEntry?
    var identity: IdleEntry?
    var rotor: [IdleEntry]
    var progress: Double?
    /// The pane whose value `progress` is, so the line is tinted by its real owner.
    var progressPane: PaneID?

    var hasLeading: Bool { pinned != nil || identity != nil }
}

/// Everything the shell views read. The controller owns one of these and mutates it from
/// the cursor monitor; the views observe it.
@MainActor
@Observable
final class NotchShellModel {
    let panes: [any NotchPane]
    var geometry: NotchGeometry
    var phase: NotchPhase = .idle
    var rotorIndex: Int = 0

    /// Bound straight to the pane host's scroll position, which makes it the single source
    /// of truth for where the panel is. A pill tap and a swipe both just write here, so the
    /// two can never fight over the same value.
    var scrollTarget: PaneID? {
        didSet {
            guard let id = scrollTarget, id != oldValue else { return }
            if phase == .expanded { setActive(id) }
            focus(id)
        }
    }

    /// The pane the notch is about: what the idle bar draws for, and where opening lands.
    ///
    /// Sticky, and remembered across launches. It moves only when the user lands on a
    /// pane; no pane may ever claim it on its own.
    private(set) var focusedID: PaneID

    /// The pane that has had `activate()` called without a matching `deactivate()`.
    private var activated: PaneID?

    private let defaults: UserDefaults
    private static let focusedKey = "shell.focusedPane"

    init(panes: [any NotchPane], geometry: NotchGeometry, defaults: UserDefaults = .standard) {
        self.panes = panes
        self.geometry = geometry
        self.defaults = defaults

        let remembered = defaults.string(forKey: Self.focusedKey).flatMap(PaneID.init(rawValue:))
        let start = remembered.flatMap { id in panes.first { $0.id == id }?.id }
            ?? panes.first?.id ?? .music
        self.focusedID = start
        self.scrollTarget = start
    }

    var landed: PaneID { scrollTarget ?? panes.first?.id ?? .music }

    // MARK: Panes

    var order: [PaneID] { panes.map(\.id) }

    func pane(_ id: PaneID) -> (any NotchPane)? {
        panes.first { $0.id == id }
    }

    var landedContentHeight: CGFloat {
        pane(landed)?.contentHeight ?? Metrics.defaultPaneHeight
    }

    // MARK: Focus

    /// The user landing on a pane is the only thing that moves focus. Landing back on the
    /// pane the notch is already about changes nothing.
    private func focus(_ id: PaneID) {
        guard id != focusedID else { return }
        focusedID = id
        defaults.set(id.rawValue, forKey: Self.focusedKey)
    }

    var panelHeight: CGFloat {
        Metrics.panelHeight(forContent: landedContentHeight) + ShellMetrics.pillBreathingRoom
    }

    // MARK: Idle composition

    var composition: IdleComposition {
        let focused = focusedID
        let focusedSignal = pane(focused)?.idle

        var pinned: IdleEntry?
        for pane in panes where pinned == nil {
            if let item = pane.idle.pinnedLeading {
                pinned = IdleEntry(pane: pane.id, item: item)
            }
        }

        // The pane holding the pinned slot never draws a second marker beside it.
        var identity: IdleEntry?
        if let item = focusedSignal?.identity, pinned?.pane != focused, item != pinned?.item {
            identity = IdleEntry(pane: focused, item: item)
        }

        // Focused pane first, then everyone else in declaration order.
        var rotor: [IdleEntry] = []
        if let item = focusedSignal?.rotating {
            rotor.append(IdleEntry(pane: focused, item: item))
        }
        for pane in panes where pane.id != focused {
            if let item = pane.idle.rotating {
                rotor.append(IdleEntry(pane: pane.id, item: item))
            }
        }

        // Nothing appears twice: drop anything already parked on the left, then dedupe.
        let parked = [pinned?.item, identity?.item].compactMap { $0 }
        var shown: [IdleItem] = []
        rotor = rotor.filter { entry in
            guard !parked.contains(entry.item), !shown.contains(entry.item) else { return false }
            shown.append(entry.item)
            return true
        }

        // The focused pane's value first. When it has none the line falls back to music,
        // because with no pane able to claim focus any more the music progress would
        // otherwise vanish the moment the user lands anywhere else (owner decision,
        // 2026-08-10). Only music publishes a bottom-edge progress today, so in practice
        // this is the music line whenever a track is loaded.
        var progress = focusedSignal?.progress
        var progressPane: PaneID? = progress == nil ? nil : focused
        if progress == nil, let music = pane(.music)?.idle.progress {
            progress = music
            progressPane = .music
        }

        return IdleComposition(
            pinned: pinned,
            identity: identity,
            rotor: rotor,
            progress: progress,
            progressPane: progressPane
        )
    }

    /// Every pane's pulse token, summed.
    ///
    /// The shell animates on this changing, never on what it equals, so the sum does not
    /// have to mean anything: any pane bumping its own token moves it, which is exactly
    /// the signal the notch needs. Panes only ever increase their token, so this only
    /// ever increases too.
    var pulse: Int {
        panes.reduce(0) { $0 + $1.idle.pulse }
    }

    /// The rotor entry currently parked in the slot, clamped so a shrinking rotor is safe.
    var visibleRotorEntry: IdleEntry? {
        let entries = composition.rotor
        guard !entries.isEmpty else { return nil }
        return entries[min(max(rotorIndex, 0), entries.count - 1)]
    }

    /// The album art that travels between idle and expanded, if the focused pane has one.
    var travellingArtwork: (present: Bool, image: NotchImage?) {
        let comp = composition
        if case .artwork(let image) = comp.identity?.item { return (true, image) }
        if case .artwork(let image) = comp.pinned?.item { return (true, image) }
        return (false, nil)
    }

    /// The waveform travels only while it is the item actually parked in the rotor.
    var travellingWaveform: [Float]? {
        if case .waveform(let levels) = visibleRotorEntry?.item { return levels }
        return nil
    }

    // MARK: State

    func setPhase(_ next: NotchPhase) {
        guard next != phase else { return }
        let wasExpanded = phase == .expanded
        if next == .expanded {
            // Opening always lands on the focused pane.
            scrollTarget = focusedID
        }
        phase = next
        if next == .expanded {
            setActive(landed)
        } else if wasExpanded {
            setActive(nil)
        }
    }

    func land(on id: PaneID) {
        scrollTarget = id
    }

    func teardown() {
        setActive(nil)
        phase = .idle
    }

    /// `activate()` and `deactivate()` each fire exactly once per pane visit.
    private func setActive(_ id: PaneID?) {
        guard activated != id else { return }
        if let previous = activated { pane(previous)?.deactivate() }
        activated = id
        if let id { pane(id)?.activate() }
    }

    // MARK: Rotor

    /// Drives the slot machine. Started by the idle bar's `task`, so it stops the moment
    /// the bar leaves the hierarchy and never runs while the panel is open.
    func runRotor(count: Int) async {
        rotorIndex = 0
        guard count > 1 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: Motion.rotationDwell)
            guard !Task.isCancelled else { return }
            withAnimation(Motion.reduced(Motion.rotate)) {
                rotorIndex = (rotorIndex + 1) % count
            }
        }
    }
}
