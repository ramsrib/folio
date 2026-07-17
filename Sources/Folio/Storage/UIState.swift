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
    /// A jump requested by global search: open the note's find bar on this query,
    /// focused on the given occurrence. Consumed (and cleared) by EditorPane.
    @Published var pendingFind: PendingFind?
    /// Bumped by the "Filter Files" command to focus the sidebar filter field.
    @Published var sidebarFilterFocus = 0
    /// Bumped by the "Toggle Sidebar" command (the sidebar's shown/hidden state
    /// lives in ContentView; this pulse asks it to flip).
    @Published var toggleSidebar = 0
    @Published var mode: EditorMode = .read
}

struct PendingFind: Equatable {
    let query: String
    let occurrence: Int
}
