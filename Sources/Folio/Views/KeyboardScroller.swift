import SwiftUI
import AppKit

/// Vim-style keyboard navigation for Reading mode. Attached inside the reading
/// scroll view, so it's installed only while Reading mode is on screen and torn
/// down when you switch to writing.
///
/// Keys:
///   j / k          line down / up
///   h / l          left / right
///   d / ⌃d         half-page down      u / ⌃u   half-page up
///   ⌃f / Space     page down           ⌃b / ⇧Space   page up
///   gg             top                 G        bottom
///
/// Scrolling is eased rather than jumped: each key press pushes a *target* offset
/// and a 60fps timer glides the clip view toward it, so taps ease smoothly and a
/// held key glides continuously. Keystrokes are ignored while an *editable* text
/// responder is focused (so the command palette and editable fields keep working);
/// ⌘/⌥ shortcuts always pass straight through.
struct KeyboardScroller: NSViewRepresentable {
    var step: CGFloat = 56

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let coord = context.coordinator
        let step = self.step
        DispatchQueue.main.async { coord.scrollView = view.enclosingScrollView }

        coord.installMonitor(step: step)

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coord = context.coordinator
        DispatchQueue.main.async { coord.scrollView = nsView.enclosingScrollView }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        weak var scrollView: NSScrollView?
        var monitor: Any?
        private var target: CGPoint = .zero
        private var timer: Timer?
        private var pendingG = false

        /// Install the key monitor. Called by `makeNSView` and by Reading mode's
        /// text view, which owns its scroll view directly.
        func installMonitor(step: CGFloat = 56) {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let scroll = self.scrollView, event.window === scroll.window else { return event }
                // Don't hijack typing — but only step aside for *editable* responders
                // (palette search, the editor); read-only text selection still scrolls.
                if let text = scroll.window?.firstResponder as? NSText, text.isEditable { return event }

                let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
                // ⌘/⌥ shortcuts are never ours.
                if mods.contains(.command) || mods.contains(.option) { return event }
                let chars = event.charactersIgnoringModifiers ?? ""

                if mods.contains(.control) {
                    switch chars {
                    case "d": self.page(fraction: 0.5, up: false); return nil
                    case "u": self.page(fraction: 0.5, up: true);  return nil
                    case "f": self.page(fraction: 1.0, up: false); return nil
                    case "b": self.page(fraction: 1.0, up: true);  return nil
                    default:  return event   // other ⌃ combos pass through
                    }
                }

                switch chars {
                case "j": self.nudge(dx: 0, dy: step);  return nil
                case "k": self.nudge(dx: 0, dy: -step); return nil
                case "l": self.nudge(dx: step, dy: 0);  return nil
                case "h": self.nudge(dx: -step, dy: 0); return nil
                case "d": self.page(fraction: 0.5, up: false); return nil
                case "u": self.page(fraction: 0.5, up: true);  return nil
                case "G": self.jump(toBottom: true);  return nil
                case "g": self.handleG();             return nil
                case " ": self.page(fraction: 1.0, up: mods.contains(.shift)); return nil
                default:  return event
                }
            }
        }

        /// Push the scroll target by a delta and start the easing timer if idle.
        func nudge(dx: CGFloat, dy: CGFloat) {
            guard let clip = scrollView?.contentView else { return }
            // Resync to the live position when starting fresh, so a key press after a
            // trackpad scroll continues from where the page actually is.
            if timer == nil { target = clip.bounds.origin }
            target.x += dx
            target.y += dy
            clampTarget()
            if timer == nil { start() }
        }

        /// Scroll by a fraction of the visible height; full pages keep a little overlap.
        func page(fraction: CGFloat, up: Bool) {
            guard let clip = scrollView?.contentView else { return }
            let overlap: CGFloat = fraction >= 1 ? 40 : 0
            nudge(dx: 0, dy: (clip.bounds.height * fraction - overlap) * (up ? -1 : 1))
        }

        /// Glide to the very top or bottom of the document.
        func jump(toBottom: Bool) {
            guard let scroll = scrollView else { return }
            let clip = scroll.contentView
            if timer == nil { target = clip.bounds.origin }
            let doc = scroll.documentView ?? clip
            target.y = toBottom ? max(0, doc.frame.height - clip.bounds.height) : 0
            clampTarget()
            if timer == nil { start() }
        }

        /// `gg` → top: a `g` primes; a second `g` within the window jumps.
        func handleG() {
            if pendingG { pendingG = false; jump(toBottom: false) }
            else {
                pendingG = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.pendingG = false }
            }
        }

        private func clampTarget() {
            guard let scroll = scrollView else { return }
            let clip = scroll.contentView
            let doc = scroll.documentView ?? clip
            target.x = min(max(0, target.x), max(0, doc.frame.width - clip.bounds.width))
            target.y = min(max(0, target.y), max(0, doc.frame.height - clip.bounds.height))
        }

        private func start() {
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(timer, forMode: .common)   // keep gliding during scroll/tracking
            self.timer = timer
        }

        private func tick() {
            guard let scroll = scrollView else { return stop() }
            let clip = scroll.contentView
            clampTarget()
            let cur = clip.bounds.origin
            let dx = target.x - cur.x, dy = target.y - cur.y
            let next: CGPoint
            if abs(dx) < 0.5 && abs(dy) < 0.5 {
                next = target
                stop()
            } else {
                next = CGPoint(x: cur.x + dx * 0.22, y: cur.y + dy * 0.22)   // ease toward target
            }
            clip.scroll(to: next)
            scroll.reflectScrolledClipView(clip)
        }

        private func stop() { timer?.invalidate(); timer = nil }

        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            stop()
        }
        deinit { removeMonitor() }
    }
}
