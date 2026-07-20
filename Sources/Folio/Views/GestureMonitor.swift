import SwiftUI
import AppKit

/// Trackpad gestures for the reader, installed once as an invisible view in
/// ContentView's background (the `KeyboardScroller` pattern): local event
/// monitors, torn down on dismantle and scoped to this view's window.
///
///  - Two-finger horizontal swipe → back / forward history. macOS synthesizes
///    `.swipe` events from two-finger scrolls when Trackpad ▸ "Swipe between
///    pages" is on (the default). We only watch `.swipe`, never raw scrollWheel,
///    so a horizontal scroll *consumed* by a code block's ScrollView never pages —
///    the swipe only fires when nothing ate the scroll, which is what we want.
///  - Pinch (magnify) → reading text size.
struct GestureMonitor: NSViewRepresentable {
    let vault: VaultStore
    let settings: AppSettings
    let ui: UIState

    func makeCoordinator() -> Coordinator { Coordinator(vault: vault, settings: settings, ui: ui) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(on: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitors()
    }

    final class Coordinator {
        let vault: VaultStore
        let settings: AppSettings
        let ui: UIState
        weak var view: NSView?
        private var swipeMonitor: Any?
        private var magnifyMonitor: Any?
        private var keyMonitor: Any?

        // Pinch accumulator. `event.magnification` arrives as many small deltas over
        // a gesture; we step the font each time the running total crosses ±0.12 and
        // subtract that step, so a slow pinch bumps once and a fast one bumps several
        // times. No live font scaling mid-gesture — one discrete step per threshold.
        private var magAccum: CGFloat = 0
        private let magStep: CGFloat = 0.12

        init(vault: VaultStore, settings: AppSettings, ui: UIState) {
            self.vault = vault
            self.settings = settings
            self.ui = ui
        }

        func install(on view: NSView) {
            self.view = view
            if swipeMonitor == nil {
                swipeMonitor = NSEvent.addLocalMonitorForEvents(matching: .swipe) { [weak self] event in
                    self?.handleSwipe(event) ?? event
                }
            }
            if magnifyMonitor == nil {
                magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
                    self?.handleMagnify(event) ?? event
                }
            }
            if keyMonitor == nil {
                keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    self?.handleKey(event) ?? event
                }
            }
        }

        /// Global Esc: dismiss whichever palette/overlay is open. Each palette has
        /// its own `onExitCommand`, but that only fires when the palette actually
        /// holds focus — opened from the command palette (or with focus elsewhere),
        /// Esc used to fall through to nothing. This monitor is the reliable path;
        /// when no palette is open the event passes through untouched (find bar,
        /// editor's Esc-to-reading, `[[` completion all keep their behavior).
        private func handleKey(_ event: NSEvent) -> NSEvent? {
            guard event.keyCode == 53,                      // Esc
                  let win = view?.window, event.window === win else { return event }
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard ui.anyPaletteShown else { return false }
                ui.dismissPalettes()
                return true
            }
            return handled ? nil : event
        }

        /// Map a horizontal swipe to Back/Forward. Direction per the NSEvent.h header:
        /// "-1 for swipe right and 1 for swipe left" — so `deltaX < 0` is a rightward
        /// swipe. Safari pages *back* on a rightward swipe (the page slides right to
        /// reveal the previous one), so rightward (deltaX < 0) → Back, matching Safari.
        /// (Note: the SDK's sign is the opposite of what a naive reading suggests, so
        /// this is verified against the header, not assumed.) Returns nil to consume a
        /// handled swipe, else the event to pass it through.
        private func handleSwipe(_ event: NSEvent) -> NSEvent? {
            guard let win = view?.window, event.window === win else { return event }
            let dx = event.deltaX
            guard dx != 0 else { return event }   // ignore vertical swipes
            // Local monitors are delivered on the main thread, so hopping to the
            // MainActor-isolated store is safe to assert rather than dispatch. Return
            // a Bool (not the NSEvent) out of the hop — NSEvent isn't Sendable and
            // can't cross the actor boundary in the Swift 6 language mode.
            let handled = MainActor.assumeIsolated { () -> Bool in
                // Never navigate the note *behind* an open palette.
                guard !ui.anyPaletteShown else { return false }
                if dx < 0 {
                    guard vault.canGoBack else { return false }
                    vault.goBack()
                } else {
                    guard vault.canGoForward else { return false }
                    vault.goForward()
                }
                return true
            }
            return handled ? nil : event   // consume when handled, else pass through
        }

        /// Pinch → step the reading body size. Adjusts the reading font (harmless in
        /// write mode, where it's not shown). Consumes the event either way so a pinch
        /// never falls through to some other magnify handler.
        private func handleMagnify(_ event: NSEvent) -> NSEvent? {
            guard let win = view?.window, event.window === win else { return event }
            // A pinch over an open palette shouldn't resize the note behind it.
            let paletteShown = MainActor.assumeIsolated { ui.anyPaletteShown }
            guard !paletteShown else { return event }
            if event.phase.contains(.began) { magAccum = 0 }
            magAccum += event.magnification
            // Delivered on the main thread → safe to touch the MainActor settings.
            MainActor.assumeIsolated {
                while magAccum >= magStep {
                    settings.biggerText()
                    magAccum -= magStep
                }
                while magAccum <= -magStep {
                    settings.smallerText()
                    magAccum += magStep
                }
            }
            return nil   // always consume a pinch so it never falls through
        }

        func removeMonitors() {
            if let swipeMonitor { NSEvent.removeMonitor(swipeMonitor); self.swipeMonitor = nil }
            if let magnifyMonitor { NSEvent.removeMonitor(magnifyMonitor); self.magnifyMonitor = nil }
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        }

        deinit { removeMonitors() }
    }
}
