import SwiftUI
import AppKit

/// A SwiftUI wrapper over `NSVisualEffectView` — the native frosted/vibrancy
/// material. Used as the sidebar backdrop in the Frosted theme so it blurs the
/// desktop behind the window (which that theme makes translucent).
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active   // stay vibrant even when the window is inactive
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
        view.state = .active
    }
}
