import SwiftUI
import AppKit

/// Two bits of AppKit polish SwiftUI can't express, applied by walking the window:
///  1. Thin, auto-hiding *overlay* scrollers on every scroll view (the system
///     "Show scroll bars: Always" setting otherwise renders a heavy legacy bar).
///  2. No focus ring on list tables — SwiftUI `List` rows draw a blue AppKit focus
///     ring around themselves on right-click, which `.focusEffectDisabled()` can't
///     reach; setting `focusRingType = .none` on the table + its rows removes it.
///
/// Attached once in the main window; re-runs on updates so freshly-created rows and
/// palettes are covered too.
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
        if let table = view as? NSTableView {
            disableFocusRing(in: table)   // kills the blue right-click ring on List rows
        }
        view.subviews.forEach(styleScrollers)
    }

    /// Suppress the focus ring on a table and every row/cell view inside it.
    private func disableFocusRing(in view: NSView) {
        view.focusRingType = .none
        view.subviews.forEach(disableFocusRing)
    }
}
