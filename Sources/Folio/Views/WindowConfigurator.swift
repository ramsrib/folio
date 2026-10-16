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
        var observers: [NSObjectProtocol] = []

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }

    /// Configures from `viewDidMoveToWindow`, i.e. as soon as the window exists and
    /// before its first frame. The old `DispatchQueue.main.async` from
    /// `makeNSView` ran a turn late and often found `view.window` still nil, so
    /// the window launched with stock chrome (lights high) until some later
    /// SwiftUI update happened to configure it.
    final class HostView: NSView {
        var onWindow: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow?(window) }   // also fires with nil on teardown
        }
    }

    func makeNSView(context: Context) -> HostView {
        let view = HostView()
        let coordinator = context.coordinator
        view.onWindow = { configure($0, coordinator) }
        return view
    }

    func updateNSView(_ nsView: HostView, context: Context) {
        let coordinator = context.coordinator
        nsView.onWindow = { configure($0, coordinator) }
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
            coordinator.didConfigureChrome = true
            // AppKit puts the buttons back at their stock 28pt-bar spot whenever it
            // lays out the title bar again — on resize, key/main changes, leaving
            // full screen — so centering once is not enough; it has to follow each.
            let names: [Notification.Name] = [
                NSWindow.didResizeNotification, NSWindow.didExitFullScreenNotification,
                NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification,
            ]
            coordinator.observers = names.map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak window] _ in
                    guard let window else { return }
                    Self.centerTrafficLights(window, barHeight: Self.barHeight)
                }
            }
            // Closing a background native tab hides the tab bar and restores the
            // stock title bar without any of the above firing on the survivor, so
            // any window closing re-centres too — a turn later, once AppKit has
            // finished taking the tab bar down.
            coordinator.observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: nil, queue: .main
            ) { [weak window] note in
                guard let window, note.object as? NSWindow !== window else { return }
                DispatchQueue.main.async { [weak window] in
                    guard let window else { return }
                    Self.centerTrafficLights(window, barHeight: Self.barHeight)
                }
            })
        }
        if translucent {
            window.isOpaque = false
            window.backgroundColor = .clear
        } else {
            window.isOpaque = true
            window.backgroundColor = background ?? .windowBackgroundColor
        }
        coordinator.applied = (background, translucent)
        Self.centerTrafficLights(window, barHeight: Self.barHeight)
    }

    /// Height of ContentView's custom title-bar row — the single source for both
    /// the row's frame and the traffic-light centering below.
    static let barHeight: CGFloat = 42

    /// Vertically center the traffic lights within our taller (42pt) title bar.
    ///
    /// The title-bar container is stretched to the full bar first: left at its
    /// stock ~28pt, a centered button would hang off its bottom edge, clipped and
    /// outside its own hover area. Idempotent — absolute targets, change-guarded,
    /// so the repeated calls from the window observers neither drift nor relayout.
    static func centerTrafficLights(_ window: NSWindow, barHeight: CGFloat) {
        // Full screen draws the title bar in its own reveal window; leave it stock.
        guard !window.styleMask.contains(.fullScreen) else { return }
        // Merged into native window tabs, the container also holds the tab strip
        // (~68pt); forcing it to 42 would push the lights into that strip and let
        // it swallow clicks meant for our row. AppKit owns that layout.
        guard window.tabGroup?.isTabBarVisible != true else { return }
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window.standardWindowButton($0) }
        guard let titlebarView = buttons.first?.superview,
              let container = titlebarView.superview else { return }
        let target = NSRect(x: container.frame.minX, y: window.frame.height - barHeight,
                            width: container.frame.width, height: barHeight)
        if container.frame != target { container.frame = target }
        for button in buttons {
            let y = ((titlebarView.bounds.height - button.frame.height) / 2).rounded()
            if button.frame.origin.y != y {
                button.setFrameOrigin(NSPoint(x: button.frame.origin.x, y: y))
            }
        }
    }
}
