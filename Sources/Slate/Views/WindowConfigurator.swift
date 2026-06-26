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
    }
}
