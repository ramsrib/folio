import SwiftUI
import AppKit

/// Reaches the hosting `NSWindow` to make the title bar transparent, hide the
/// title, and tint the window to the theme color.
struct WindowConfigurator: NSViewRepresentable {
    var background: NSColor?
    /// When true, the window is see-through so a vibrancy sidebar can blur the
    /// desktop behind it (the Frosted theme); opaque content still hides it elsewhere.
    var translucent: Bool = false

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Remembers what was last applied so `updateNSView` — which SwiftUI calls on
    /// *every* content update (each tab switch, folder toggle, keystroke…) — can
    /// skip the window mutations entirely when nothing changed. Unconditionally
    /// re-setting styleMask/backgroundColor invalidated window-wide layout on
    /// every interaction, which read as app-wide lag.
    final class Coordinator {
        var applied: (background: NSColor?, translucent: Bool)?
        var didConfigureChrome = false
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let coordinator = context.coordinator
        DispatchQueue.main.async { configure(view.window, coordinator) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        guard coordinator.applied?.background != background
            || coordinator.applied?.translucent != translucent
            || coordinator.applied == nil else { return }
        DispatchQueue.main.async { configure(nsView.window, coordinator) }
    }

    private func configure(_ window: NSWindow?, _ coordinator: Coordinator) {
        guard let window else { return }
        if !coordinator.didConfigureChrome {
            // One-time chrome: let our SwiftUI content draw all the way up into the
            // title-bar strip (custom title-bar row under the traffic lights), and
            // move the window only by that strip (WindowDragGesture in ContentView)
            // — background dragging is for utility panels, not a reader where you
            // click/select/drag everywhere.
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = false
            // Create + tame the shared field editor now, while nothing is on
            // screen — created lazily on first focus, it would flash its default
            // white background/prediction candidates over the first palette.
            if let editor = window.fieldEditor(true, for: nil) as? NSTextView {
                tameFieldEditor(editor)
            }
            coordinator.didConfigureChrome = true
        }
        if translucent {
            window.isOpaque = false
            window.backgroundColor = .clear
        } else {
            window.isOpaque = true
            window.backgroundColor = background ?? .windowBackgroundColor
        }
        coordinator.applied = (background, translucent)
        centerTrafficLights(window, barHeight: 42)
    }

    /// Vertically center the traffic lights within our taller (42pt) title bar.
    /// Idempotent — sets an absolute target Y so repeated calls don't drift.
    private func centerTrafficLights(_ window: NSWindow, barHeight: CGFloat) {
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window.standardWindowButton($0) }
        guard let container = buttons.first?.superview else { return }
        for button in buttons {
            let h = button.frame.height
            let targetY = container.bounds.height - barHeight / 2 - h / 2   // center at barHeight/2 from top
            if abs(button.frame.origin.y - targetY) > 0.5 {
                button.setFrameOrigin(NSPoint(x: button.frame.origin.x, y: targetY))
            }
        }
    }
}
