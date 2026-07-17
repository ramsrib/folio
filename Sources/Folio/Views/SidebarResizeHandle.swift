import SwiftUI
import AppKit

/// AppKit-backed drag handle for the sidebar divider.
///
/// The window is movable-by-background (hidden-title-bar design), and AppKit
/// arbitrates window-move vs. event-delivery by asking the *hit view*'s
/// `mouseDownCanMoveWindow` — a SwiftUI DragGesture never gets a say, so a
/// gesture-based divider dragged the whole window instead of resizing. A real
/// NSView that returns false and tracks the drag itself wins that arbitration.
struct SidebarResizeHandle: NSViewRepresentable {
    /// Called during the drag with the horizontal delta from the drag's start.
    var onDrag: (CGFloat) -> Void
    var onEnd: () -> Void

    func makeNSView(context: Context) -> HandleView {
        let v = HandleView()
        v.onDrag = onDrag
        v.onEnd = onEnd
        return v
    }

    func updateNSView(_ v: HandleView, context: Context) {
        v.onDrag = onDrag
        v.onEnd = onEnd
    }

    final class HandleView: NSView {
        var onDrag: (CGFloat) -> Void = { _ in }
        var onEnd: () -> Void = {}
        private var startX: CGFloat = 0

        override var mouseDownCanMoveWindow: Bool { false }

        // Cursor via cursor rects (not onHover push/pop): AppKit restores it
        // reliably even when the drag ends outside the handle.
        override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }

        override func mouseDown(with event: NSEvent) { startX = event.locationInWindow.x }
        override func mouseDragged(with event: NSEvent) { onDrag(event.locationInWindow.x - startX) }
        override func mouseUp(with event: NSEvent) { onEnd() }
    }
}
