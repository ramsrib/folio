import SwiftUI

/// Window-level UI state (overlays) kept separate from vault/data state.
@MainActor
final class UIState: ObservableObject {
    @Published var showQuickSwitcher = false
    @Published var showCommandPalette = false
}
