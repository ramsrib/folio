import SwiftUI
import AppKit

/// Reaches the hosting `NSWindow` to: make the title bar transparent/draggable,
/// tint it to the theme, and place the vault name as a **leading title-bar
/// accessory** — i.e. inline in the sidebar's portion of the title bar (after
/// the traffic lights), which SwiftUI's toolbar placements can't target.
struct WindowConfigurator: NSViewRepresentable {
    var background: NSColor?
    var title: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window, context.coordinator) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window, context.coordinator) }
    }

    private func configure(_ window: NSWindow?, _ coord: Coordinator) {
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = background ?? .windowBackgroundColor

        let label = AnyView(
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 8)
        )

        if let host = coord.host {
            host.rootView = label
            host.frame.size = host.fittingSize
        } else {
            let host = NSHostingView(rootView: label)
            host.frame.size = host.fittingSize
            let accessory = NSTitlebarAccessoryViewController()
            accessory.layoutAttribute = .leading
            accessory.view = host
            window.addTitlebarAccessoryViewController(accessory)
            coord.host = host
        }
    }

    final class Coordinator {
        var host: NSHostingView<AnyView>?
    }
}
