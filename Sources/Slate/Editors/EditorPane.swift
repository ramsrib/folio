import SwiftUI

/// Hosts the Live Preview editor for the selected note (or an empty state).
struct EditorPane: View {
    @EnvironmentObject private var vault: VaultStore

    var body: some View {
        if vault.selection != nil {
            LivePreviewEditor(text: $vault.content, onChange: { vault.scheduleSave() })
                .background(Color(nsColor: .textBackgroundColor))
                .toolbar { ToolbarItem(placement: .status) { saveStatus } }
        } else {
            ContentUnavailableView("Select a note", systemImage: "doc.text",
                description: Text("Pick a note from the sidebar to start editing."))
        }
    }

    @ViewBuilder
    private var saveStatus: some View {
        if vault.savedAt != nil {
            Label("Saved", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
}
