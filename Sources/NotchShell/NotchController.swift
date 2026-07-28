import AppKit
import NotchCore
import QuartzCore
import SwiftUI

/// Owns the notch window and everything drawn in it.
///
/// The window is created once at a fixed size and never resized; only the surface inside
/// it animates. Cursor tracking is a pair of `NSEvent` monitors with a one-frame throttle,
/// so with nothing live and the pointer elsewhere the app does no work at all.
@MainActor
public final class NotchController {
    private let panes: [any NotchPane]
    private let hitBox = NotchHitBox()

    private var panel: NotchPanel?
    private var model: NotchShellModel?

    private var globalMonitor: Any?
    private var moveMonitor: Any?
    private var wheelMonitor: Any?
    private var appObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    private var closeTask: Task<Void, Never>?
    private var lastSample: CFTimeInterval = 0
    private var lastWheel: CFTimeInterval = 0
    private var displaysAsleep = false

    public init(panes: [any NotchPane]) {
        self.panes = panes
    }

    // MARK: Lifecycle

    /// Places the notch window on the preferred screen and begins tracking the cursor.
    public func start() {
        guard panel == nil, let screen = NotchGeometry.preferredScreen() else { return }

        let model = NotchShellModel(panes: panes, geometry: NotchGeometry.measure(screen))
        self.model = model

        let size = panelSize(for: screen)
        let panel = NotchPanel(hitBox: hitBox, size: size)
        let root = NotchRootView(model: model, hitBox: hitBox) { [weak self] inside in
            self?.hoverChanged(inside)
        }
        let host = NSHostingView(rootView: root)
        host.translatesAutoresizingMaskIntoConstraints = false
        if let container = panel.contentView {
            container.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                host.topAnchor.constraint(equalTo: container.topAnchor),
                host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }
        place(panel, on: screen, size: size)
        panel.orderFrontRegardless()
        self.panel = panel

        installMonitors()
        installObservers()
    }

    public func stop() {
        closeTask?.cancel()
        closeTask = nil
        removeMonitors()
        removeObservers()
        model?.teardown()
        panel?.orderOut(nil)
        panel = nil
        model = nil
    }

    // MARK: Placement

    /// Big enough for the tallest pane plus the shadow, and never resized after this.
    private func panelSize(for screen: NSScreen) -> CGSize {
        let tallest = panes.map(\.contentHeight).max() ?? Metrics.defaultPaneHeight
        let content = max(tallest, Metrics.defaultPaneHeight) + ShellMetrics.heightHeadroom
        let height = Metrics.panelHeight(forContent: content) + ShellMetrics.windowMargin
        let width = Metrics.expandedWidth + ShellMetrics.windowMargin * 2
        return CGSize(
            width: min(width, screen.frame.width),
            height: min(height, screen.frame.height)
        )
    }

    private func place(_ panel: NSPanel, on screen: NSScreen, size: CGSize) {
        panel.setFrame(
            CGRect(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.maxY - size.height,
                width: size.width,
                height: size.height
            ),
            display: false
        )
    }

    /// Screens changed, woke, or the notched display was unplugged.
    private func rebuild() {
        guard let panel, let model else { return }
        guard let screen = NotchGeometry.preferredScreen() else {
            panel.orderOut(nil)
            return
        }
        model.geometry = NotchGeometry.measure(screen)
        place(panel, on: screen, size: panelSize(for: screen))
        if !displaysAsleep {
            panel.orderFrontRegardless()
        }
    }

    // MARK: Monitors

    private func installMonitors() {
        let moved: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: moved) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sample(NSEvent.mouseLocation)
            }
        }
        moveMonitor = NSEvent.addLocalMonitorForEvents(matching: moved) { [weak self] event in
            MainActor.assumeIsolated {
                self?.sample(NSEvent.mouseLocation)
            }
            return event
        }
        wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleWheel(event) ?? false }
            return handled ? nil : event
        }
    }

    private func removeMonitors() {
        for monitor in [globalMonitor, moveMonitor, wheelMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        globalMonitor = nil
        moveMonitor = nil
        wheelMonitor = nil
    }

    private func installObservers() {
        let center = NotificationCenter.default
        appObservers.append(
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebuild() }
            }
        )

        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(
            workspace.addObserver(
                forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.suspend() }
            }
        )
        workspaceObservers.append(
            workspace.addObserver(
                forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.resume() }
            }
        )
        workspaceObservers.append(
            workspace.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.resume() }
            }
        )
    }

    private func removeObservers() {
        appObservers.forEach(NotificationCenter.default.removeObserver)
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        appObservers.removeAll()
        workspaceObservers.removeAll()
    }

    /// Displays off: close, stop drawing, stop the panes.
    private func suspend() {
        displaysAsleep = true
        closeTask?.cancel()
        closeTask = nil
        collapse(to: .idle, animated: false)
        panel?.ignoresMouseEvents = true
        panel?.orderOut(nil)
    }

    private func resume() {
        guard displaysAsleep else { return }
        displaysAsleep = false
        rebuild()
    }

    // MARK: Cursor

    /// The stable trigger zone: the hardware notch plus one shoulder each side. It does not
    /// move with the animation, so entering and leaving cannot chatter.
    private func triggerRect(panel: NSPanel, model: NotchShellModel) -> CGRect {
        let width = model.geometry.hardwareWidth + Metrics.shoulderPadding * 2
        return CGRect(
            x: panel.frame.midX - width / 2,
            y: panel.frame.maxY - Metrics.idleHeight,
            width: width,
            height: Metrics.idleHeight
        )
    }

    /// The surface as currently drawn, in screen coordinates.
    private func surfaceRect(panel: NSPanel) -> CGRect {
        let size = hitBox.size
        return CGRect(
            x: panel.frame.midX - size.width / 2,
            y: panel.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    private func isOnSurface(_ point: CGPoint, panel: NSPanel, model: NotchShellModel) -> Bool {
        let surface = surfaceRect(panel: panel)
            .insetBy(dx: -ShellMetrics.hitSlack, dy: -ShellMetrics.hitSlack)
        return surface.contains(point) || triggerRect(panel: panel, model: model).contains(point)
    }

    private func sample(_ location: CGPoint, force: Bool = false) {
        guard !displaysAsleep, let panel, let model else { return }

        let now = CACurrentMediaTime()
        if !force {
            guard now - lastSample >= ShellMetrics.sampleInterval else { return }
        }
        lastSample = now

        let onSurface = isOnSurface(location, panel: panel, model: model)

        // Clicks land on the notch only while the pointer is actually over it; everywhere
        // else the window is inert and the menu bar and desktop behave normally. Never
        // flipped mid-drag, which would drop a gesture in progress.
        if NSEvent.pressedMouseButtons == 0, panel.ignoresMouseEvents == onSurface {
            panel.ignoresMouseEvents = !onSurface
        }

        if onSurface {
            transition(to: .expanded)
        } else if distance(location, triggerRect(panel: panel, model: model)) <= Motion.proximityRadius {
            transition(to: .proximity)
        } else {
            transition(to: .idle)
        }
    }

    private func hoverChanged(_ inside: Bool) {
        guard !displaysAsleep else { return }
        if inside {
            transition(to: .expanded)
        } else {
            sample(NSEvent.mouseLocation, force: true)
        }
    }

    private func transition(to target: NotchPhase) {
        guard let model else { return }

        if target == model.phase {
            closeTask?.cancel()
            closeTask = nil
            return
        }

        if target == .expanded {
            closeTask?.cancel()
            closeTask = nil
            withAnimation(Motion.reduced(Motion.morph)) { model.setPhase(.expanded) }
            return
        }

        // Leaving an open panel waits out the grace period, then re-reads the cursor, so a
        // slip across the edge does not close it.
        if model.phase == .expanded {
            guard closeTask == nil else { return }
            closeTask = Task { [weak self] in
                try? await Task.sleep(for: Motion.closeGrace)
                guard !Task.isCancelled, let self else { return }
                self.closeTask = nil
                self.settleAfterGrace()
            }
            return
        }

        withAnimation(Motion.reduced(Motion.slot)) { model.setPhase(target) }
    }

    private func settleAfterGrace() {
        guard let panel, let model, model.phase == .expanded else { return }
        let location = NSEvent.mouseLocation
        guard !isOnSurface(location, panel: panel, model: model) else { return }
        let near = distance(location, triggerRect(panel: panel, model: model)) <= Motion.proximityRadius
        collapse(to: near ? .proximity : .idle, animated: true)
    }

    private func collapse(to phase: NotchPhase, animated: Bool) {
        guard let model else { return }
        if animated {
            withAnimation(Motion.reduced(Motion.morph)) { model.setPhase(phase) }
        } else {
            model.setPhase(phase)
        }
    }

    // MARK: Scroll wheel

    /// A plain mouse only produces vertical deltas, so map those onto pane steps. Trackpad
    /// events carry precise deltas and are left alone, keeping their native momentum.
    private func handleWheel(_ event: NSEvent) -> Bool {
        guard let model, model.phase == .expanded else { return false }
        guard !event.hasPreciseScrollingDeltas else { return false }

        let raw = event.scrollingDeltaY
        let delta = event.isDirectionInvertedFromDevice ? -raw : raw
        guard abs(delta) > abs(event.scrollingDeltaX), abs(delta) > 0 else { return false }

        let now = CACurrentMediaTime()
        guard now - lastWheel > ShellMetrics.wheelDebounce else { return true }

        let order = model.order
        guard let current = order.firstIndex(of: model.landed) else { return true }
        let next = delta < 0 ? current + 1 : current - 1
        guard order.indices.contains(next) else { return true }

        lastWheel = now
        withAnimation(Motion.reduced(Motion.morph)) { model.land(on: order[next]) }
        return true
    }
}
