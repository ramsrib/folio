import SwiftUI

enum InspectorTab: String, CaseIterable, Identifiable {
    case outline = "Outline"
    case backlinks = "Backlinks"
    var id: String { rawValue }
}

/// Window-level UI state (panels, overlays) kept separate from vault/data state.
@MainActor
final class UIState: ObservableObject {
    @Published var showQuickSwitcher = false
    @Published var showCommandPalette = false
    @Published var showInspector = true
    @Published var inspectorTab: InspectorTab = .outline
}
