import SwiftUI

enum EditorMode { case edit, read }

/// Window-level UI state (overlays, view mode) kept separate from vault/data state.
@MainActor
final class UIState: ObservableObject {
    @Published var showQuickSwitcher = false
    @Published var showCommandPalette = false
    @Published var mode: EditorMode = .edit
}
