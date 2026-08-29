import SwiftUI

enum EditorMode { case edit, read }

/// Window-level UI state (overlays, view mode) kept separate from vault/data state.
@MainActor
final class UIState: ObservableObject {
    @Published var showQuickSwitcher = false
    @Published var showCommandPalette = false
    @Published var showTags = false
    @Published var showShortcuts = false
    @Published var showSearch = false          // ⇧⌘F global content search
    @Published var showVaultSwitcher = false   // ⇧⌘O switch/open a vault
    /// A jump requested by global search: open the note's find bar on this query,
    /// focused on the given occurrence. Consumed (and cleared) by EditorPane.
    @Published var pendingFind: PendingFind?
    /// Bumped by the "Filter Files" command to focus the sidebar filter field.
    @Published var sidebarFilterFocus = 0
    /// Bumped by the "Toggle Sidebar" command (the sidebar's shown/hidden state
    /// lives in ContentView; this pulse asks it to flip).
    @Published var toggleSidebar = 0
    @Published var mode: EditorMode = .read

    /// Settings as an in-window overlay (not a separate Settings window): it
    /// follows the theme for free, Esc closes it, and ⌘W can't hit a tab behind it.
    @Published var showSettings = false
    /// Bumped when Esc is pressed in reading mode with no palette open — the
    /// note pane consumes it (close the find bar if open). Swallowing the key
    /// also silences AppKit's unhandled-key funk, which played whenever nothing
    /// held keyboard focus.
    @Published var escapePulse = 0

    /// Any modal palette on screen — gates gestures and other note-level input
    /// so a swipe/pinch can't act on the note *behind* an open palette.
    var anyPaletteShown: Bool {
        showQuickSwitcher || showCommandPalette || showTags || showShortcuts || showSearch
            || showSettings || showVaultSwitcher
    }

    /// Close every palette/overlay — the single dismiss path used by the outside
    /// click-catcher and the global Esc handler.
    func dismissPalettes() {
        showQuickSwitcher = false
        showCommandPalette = false
        showTags = false
        showShortcuts = false
        showSearch = false
        showSettings = false
        showVaultSwitcher = false
    }
}

struct PendingFind: Equatable {
    let query: String
    let occurrence: Int
}
