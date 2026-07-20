import SwiftUI
import AppKit

/// Two bits of AppKit polish SwiftUI can't express, applied by walking the window:
///  1. Thin, auto-hiding *overlay* scrollers on every scroll view (the system
///     "Show scroll bars: Always" setting otherwise renders a heavy legacy bar).
///  2. No focus ring on list tables — SwiftUI `List` rows draw a blue AppKit focus
///     ring around themselves on right-click, which `.focusEffectDisabled()` can't
///     reach; setting `focusRingType = .none` on the table + its rows removes it.
///
/// Perf contract: `updateNSView` fires on *every* SwiftUI update (tab switch,
/// folder toggle, keystroke), so the walk is (a) coalesced to at most one per
/// runloop turn and (b) mutation-free when nothing needs changing — every setter
/// is guarded, because unconditional sets invalidate AppKit layout/display and
/// made the whole app feel laggy.
struct ThinScrollers: NSViewRepresentable {
    final class Coordinator { var walkScheduled = false }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        scheduleWalk(from: v, context.coordinator)
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        scheduleWalk(from: nsView, context.coordinator)
    }

    /// Coalesce: a single interaction can produce several SwiftUI update passes;
    /// walk the window once at the end of the runloop turn instead of per pass.
    private func scheduleWalk(from view: NSView, _ coordinator: Coordinator) {
        guard !coordinator.walkScheduled else { return }
        coordinator.walkScheduled = true
        DispatchQueue.main.async {
            coordinator.walkScheduled = false
            guard let content = view.window?.contentView else { return }
            styleScrollers(in: content)
        }
    }

    private func styleScrollers(in view: NSView) {
        if let scroll = view as? NSScrollView {
            if scroll.scrollerStyle != .overlay { scroll.scrollerStyle = .overlay }
            if let v = scroll.verticalScroller, v.controlSize != .small { v.controlSize = .small }
            if let h = scroll.horizontalScroller, h.controlSize != .small { h.controlSize = .small }
        }
        if let table = view as? NSTableView {
            disableFocusRing(in: table)   // kills the blue right-click ring on List rows
        }
        view.subviews.forEach(styleScrollers)
    }

    /// Suppress the focus ring on a table and every row/cell view inside it.
    private func disableFocusRing(in view: NSView) {
        if view.focusRingType != .none { view.focusRingType = .none }
        view.subviews.forEach(disableFocusRing)
    }
}
