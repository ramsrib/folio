import SwiftUI
import AppKit

/// Reaches the hosting `NSWindow` to make the title bar transparent, hide the
/// title, allow background dragging, and tint the window to the theme color.
struct WindowConfigurator: NSViewRepresentable {
    var background: NSColor?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        // Let our SwiftUI content draw all the way up into the title-bar strip
        // (so a custom title-bar row sits under the traffic lights, not below them).
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = background ?? .windowBackgroundColor
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
