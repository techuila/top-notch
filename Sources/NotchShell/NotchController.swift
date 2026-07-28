import AppKit
import NotchCore
import SwiftUI

/// Owns the notch window and everything drawn in it.
///
/// STUB. Owned by the shell agent, which replaces this file and adds the rest of the
/// module. The public surface below is a contract the app target depends on; keep it.
@MainActor
public final class NotchController {
    private let panes: [any NotchPane]
    private var window: NSWindow?

    public init(panes: [any NotchPane]) {
        self.panes = panes
    }

    /// Places the notch window on the preferred screen and begins tracking the cursor.
    public func start() {
        guard window == nil, let screen = NotchGeometry.preferredScreen() else { return }
        let geometry = NotchGeometry.measure(screen)

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false

        let size = CGSize(width: Metrics.expandedWidth + 260, height: 320)
        panel.setFrame(
            CGRect(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.maxY - size.height,
                width: size.width,
                height: size.height
            ),
            display: false
        )
        panel.contentView = NSHostingView(
            rootView: NotchRootView(panes: panes, geometry: geometry)
        )
        panel.orderFrontRegardless()
        window = panel
    }

    public func stop() {
        window?.orderOut(nil)
        window = nil
    }
}

/// STUB root view. The shell agent replaces this with the real idle bar, proximity
/// state, pill row and horizontally scrolling pane host.
struct NotchRootView: View {
    let panes: [any NotchPane]
    let geometry: NotchGeometry

    var body: some View {
        VStack {
            Color.clear
                .frame(width: geometry.hardwareWidth + 120, height: Metrics.idleHeight)
                .notchMaterial(isExpanded: false, cornerRadius: Metrics.idleCornerRadius)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
