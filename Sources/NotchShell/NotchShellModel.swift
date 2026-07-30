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
            landedByUser(id)
        }
    }

    /// The pane the notch is about: what the idle bar draws for, and where opening lands.
    ///
    /// Sticky, and remembered across launches. It moves when the user lands on a pane, and
    /// otherwise only when a pane claims it under the rules in `applyClaim`.
    private(set) var focusedID: PaneID

    /// The pane that has had `activate()` called without a matching `deactivate()`.
    private var activated: PaneID?

    /// Panes that were live the last time claims were evaluated, so a claim can be applied
    /// on the transition into live rather than for as long as the pane stays live.
    private var liveLast: Set<PaneID> = []

    /// A claim waiting for the notch to be closed long enough to apply it.
    private var pendingClaim: PaneID?
    private var claimTask: Task<Void, Never>?

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

        trackClaims()
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

    /// The user landing on a pane is the strongest signal there is, so it takes focus at
    /// once and throws away anything a pane was waiting to claim. Landing back on the pane
    /// the notch is already about is not a choice and changes nothing, which is what keeps
    /// merely opening the panel from cancelling a claim.
    private func landedByUser(_ id: PaneID) {
        guard id != focusedID else { return }
        cancelClaim()
        focus(id)
    }

    private func focus(_ id: PaneID) {
        guard id != focusedID else { return }
        focusedID = id
        defaults.set(id.rawValue, forKey: Self.focusedKey)
    }

    /// Re-arms itself after every change to any pane's signal.
    ///
    /// Observation, not polling: with nothing playing and nothing running this costs
    /// exactly nothing, which is the only way a rule like this is allowed to exist in an
    /// app that sits on screen all day.
    private func trackClaims() {
        withObservationTracking {
            for pane in panes {
                let signal = pane.idle
                _ = (signal.isLive, signal.claimsFocus, signal.priority)
            }
        } onChange: { [weak self] in
            // `onChange` fires before the write lands, so the new values are read back on
            // the next main-actor turn rather than here.
            Task { @MainActor [weak self] in
                self?.evaluateClaims()
                self?.trackClaims()
            }
        }
    }

    /// Turns "this pane just went live" into at most one claim.
    private func evaluateClaims() {
        var candidates: [(id: PaneID, priority: Int)] = []

        for pane in panes {
            let signal = pane.idle
            let wasLive = liveLast.contains(pane.id)

            if signal.isLive, !wasLive {
                liveLast.insert(pane.id)
                if signal.claimsFocus { candidates.append((pane.id, signal.priority)) }
            } else if !signal.isLive, wasLive {
                liveLast.remove(pane.id)
                // Nothing to switch to any more.
                if pendingClaim == pane.id { cancelClaim() }
            }
        }

        guard let winner = candidates.max(by: { $0.priority < $1.priority })?.id else { return }
        guard winner != focusedID else { return }
        arm(winner)
    }

    private func arm(_ id: PaneID) {
        pendingClaim = id
        startClaimCountdown()
    }

    /// Waits out `Motion.focusClaimDelay` and applies the claim, unless the panel is open.
    ///
    /// An open panel does not run the clock at all. The countdown is restarted by
    /// `setPhase` when the panel closes, so waiting on the user costs no timer however
    /// long they leave it open.
    private func startClaimCountdown() {
        guard pendingClaim != nil, phase != .expanded else { return }
        claimTask?.cancel()
        claimTask = Task { [weak self] in
            try? await Task.sleep(for: Motion.focusClaimDelay)
            guard !Task.isCancelled else { return }
            self?.applyClaim()
        }
    }

    private func applyClaim() {
        claimTask = nil
        guard let id = pendingClaim, phase != .expanded else { return }
        pendingClaim = nil
        withAnimation(Motion.reduced(Motion.slot)) {
            focus(id)
            scrollTarget = id
        }
    }

    private func cancelClaim() {
        claimTask?.cancel()
        claimTask = nil
        pendingClaim = nil
    }

    var panelHeight: CGFloat {
        Metrics.panelHeight(forContent: landedContentHeight)
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

        return IdleComposition(
            pinned: pinned,
            identity: identity,
            rotor: rotor,
            progress: focusedSignal?.progress
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
            // A pending claim keeps waiting, but its clock stops while the panel is open
            // and starts again from the top once it closes.
            claimTask?.cancel()
            claimTask = nil
        } else {
            if wasExpanded { setActive(nil) }
            startClaimCountdown()
        }
    }

    func land(on id: PaneID) {
        scrollTarget = id
    }

    func teardown() {
        cancelClaim()
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
