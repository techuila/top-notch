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

    private var dragCatcher: AnyView?
    private var dragCatcherHost: NSHostingView<AnyView>?
    private var isDragTargeted: (@MainActor () -> Bool)?
    private var dragArmed = false
    private var dragPasteboardChange = -1
    private var dragPasteboardHasFiles = false

    public init(panes: [any NotchPane]) {
        self.panes = panes
    }

    // MARK: Public entry points

    /// Opens the panel on whatever pane the notch is currently about.
    public func present() {
        guard let model else { return }
        present(model.focusedID)
    }

    /// Opens the panel and lands on `pane`. Used by anything that has to reveal a feature
    /// without a hover, most obviously a file drag arriving at the notch.
    public func present(_ pane: PaneID) {
        guard let model else { return }
        closeTask?.cancel()
        closeTask = nil
        withAnimation(Motion.reduced(Motion.morph)) {
            model.setPhase(.expanded)
            model.land(on: pane)
        }
    }

    /// Installs an invisible drag destination across a band around the collapsed notch.
    ///
    /// The band only becomes hit-testable while a file drag is actually in flight nearby,
    /// because the window is deliberately inert the rest of the time and must stay that way
    /// for the menu bar to work. `isTargeted` is read at the points where the shell would
    /// otherwise collapse, so the panel holds open under a hovering drag; cursor proximity
    /// cannot do that job while a mouse button is down.
    public func setDragCatcher(_ view: AnyView, isTargeted: @escaping @MainActor () -> Bool) {
        dragCatcher = view
        self.isDragTargeted = isTargeted
        if let container = panel?.contentView {
            mountDragCatcher(in: container)
        }
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

        if let container = panel.contentView {
            mountDragCatcher(in: container)
        }
        layoutDragCatcher()
        installMonitors()
        installObservers()
    }

    public func stop() {
        closeTask?.cancel()
        closeTask = nil
        removeMonitors()
        removeObservers()
        model?.teardown()
        dragCatcherHost?.removeFromSuperview()
        dragCatcherHost = nil
        panel?.orderOut(nil)
        panel = nil
        model = nil
    }

    // MARK: Drag catcher

    /// Mounted above the SwiftUI surface, because a drag destination is found by hit
    /// testing downwards: if the surface answered first, the drag would land on a view
    /// with no registered types and the notch itself would refuse files.
    private func mountDragCatcher(in container: NSView) {
        guard let view = dragCatcher, dragCatcherHost == nil else { return }
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = true
        host.isHidden = true
        container.addSubview(host, positioned: .above, relativeTo: nil)
        dragCatcherHost = host
    }

    /// A band as wide as the notch plus a shoulder each side, reaching down past the
    /// collapsed bar, expressed in window coordinates.
    private func dragBand(in bounds: CGRect) -> CGRect {
        let hardware = model?.geometry.hardwareWidth ?? NotchGeometry.synthetic.hardwareWidth
        let width = hardware + ShellMetrics.dragCatchMargin * 2
        let height = ShellMetrics.idleHeight + ShellMetrics.dragCatchMargin
        return CGRect(
            x: bounds.midX - width / 2,
            y: bounds.maxY - height,
            width: width,
            height: height
        )
    }

    private func layoutDragCatcher() {
        guard let container = panel?.contentView else { return }
        let band = dragBand(in: container.bounds)
        hitBox.dragBand = band
        dragCatcherHost?.frame = band
    }

    // MARK: Placement

    /// Big enough for the tallest pane plus the shadow, and never resized after this.
    private func panelSize(for screen: NSScreen) -> CGSize {
        let tallest = panes.map(\.contentHeight).max() ?? Metrics.defaultPaneHeight
        let content = max(tallest, Metrics.defaultPaneHeight) + ShellMetrics.heightHeadroom
        let height = Metrics.panelHeight(forContent: content)
            + ShellMetrics.pillBreathingRoom + ShellMetrics.windowMargin
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
        layoutDragCatcher()
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
        let width = model.geometry.hardwareWidth + ShellMetrics.idleShoulderPadding * 2
        return CGRect(
            x: panel.frame.midX - width / 2,
            y: panel.frame.maxY - ShellMetrics.idleHeight,
            width: width,
            height: ShellMetrics.idleHeight
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

    // MARK: Drag arming

    /// The catch band goes live only while a file drag is genuinely in flight and heading
    /// this way, and goes inert again as soon as the button comes up. Anything laxer would
    /// turn the top of the screen into a permanent event sink.
    private func updateDragArming(at location: CGPoint, panel: NSPanel) {
        guard dragCatcherHost != nil else { return }

        let band = dragBand(in: panel.contentView?.bounds ?? .zero)
        let onScreen = CGRect(
            x: panel.frame.minX + band.minX,
            y: panel.frame.minY + band.minY,
            width: band.width,
            height: band.height
        )
        let reach = onScreen.insetBy(dx: -ShellMetrics.dragApproach, dy: -ShellMetrics.dragApproach)

        let wanted: Bool
        if NSEvent.pressedMouseButtons != 0 {
            wanted = reach.contains(location) && dragPasteboardCarriesFiles()
        } else {
            wanted = isDragTargeted?() == true
        }

        guard wanted != dragArmed else { return }
        dragArmed = wanted
        hitBox.dragArmed = wanted
        dragCatcherHost?.isHidden = !wanted
    }

    /// Cached per pasteboard change: reading the drag pasteboard is cross process, and this
    /// is on the mouse-moved path.
    private func dragPasteboardCarriesFiles() -> Bool {
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != dragPasteboardChange else { return dragPasteboardHasFiles }
        dragPasteboardChange = pasteboard.changeCount

        let promised = Set(NSFilePromiseReceiver.readableDraggedTypes)
        let carriesPromise = pasteboard.types?.contains { promised.contains($0.rawValue) } ?? false
        dragPasteboardHasFiles = carriesPromise || pasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
        return dragPasteboardHasFiles
    }

    private func sample(_ location: CGPoint, force: Bool = false) {
        guard !displaysAsleep, let panel, let model else { return }

        let now = CACurrentMediaTime()
        if !force {
            guard now - lastSample >= ShellMetrics.sampleInterval else { return }
        }
        lastSample = now

        let onSurface = isOnSurface(location, panel: panel, model: model)
        updateDragArming(at: location, panel: panel)

        // Clicks land on the notch only while the pointer is actually over it; everywhere
        // else the window is inert and the menu bar and desktop behave normally. Only the
        // disabling half waits for the button to come up, so a gesture in progress is never
        // dropped, while an incoming drag can still wake the window.
        if onSurface || dragArmed {
            panel.ignoresMouseEvents = false
        } else if NSEvent.pressedMouseButtons == 0, !panel.ignoresMouseEvents {
            panel.ignoresMouseEvents = true
        }

        // A drag hovering the notch holds it open by itself. Proximity cannot help here:
        // the pointer rules do not apply while a mouse button is down.
        if isDragTargeted?() == true {
            transition(to: .expanded)
            return
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
            guard closeTask == nil, isDragTargeted?() != true else { return }
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
        guard isDragTargeted?() != true else { return }
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
