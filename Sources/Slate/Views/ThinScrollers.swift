import SwiftUI
import AppKit

/// Forces thin, auto-hiding *overlay* scrollers on every scroll view in the window.
///
/// When the system "Show scroll bars" setting is "Always", AppKit renders a thick,
/// opaque *legacy* scroller — visually heavy and distracting. Setting
/// `scrollerStyle = .overlay` per scroll view overrides that, giving the thin
/// translucent bar that fades when idle. Attached once in the main window, it scans
/// the whole view tree so the sidebar list, reading view, and editor all match.
struct ThinScrollers: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { apply(from: v) }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { apply(from: nsView) }
    }

    private func apply(from view: NSView) {
        guard let content = view.window?.contentView else { return }
        styleScrollers(in: content)
    }

    private func styleScrollers(in view: NSView) {
        if let scroll = view as? NSScrollView {
            scroll.scrollerStyle = .overlay
            scroll.verticalScroller?.controlSize = .small
            scroll.horizontalScroller?.controlSize = .small
        }
        view.subviews.forEach(styleScrollers)
    }
}
