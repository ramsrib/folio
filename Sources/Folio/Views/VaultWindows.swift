import SwiftUI

/// Open a vault in a window, or focus the window already showing it.
///
/// Every "open this vault" path goes through here — the menu, the switcher, the
/// command palette, external file opens — so the dedupe rule lives in exactly one
/// place: **one window per vault path**.
@MainActor
enum VaultWindows {
    /// Set once the delegate exists; it owns the vault→window registry.
    static weak var delegate: AppDelegate?

    static func open(_ ref: VaultRef, using openWindow: OpenWindowAction) {
        guard delegate?.focus(vault: ref) != true else { return }
        openWindow(value: ref)
    }
}
