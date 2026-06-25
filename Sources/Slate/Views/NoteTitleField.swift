import SwiftUI

/// Notion-style large page title at the top of a note. Editing it renames the
/// file (and updates links across the vault) on commit.
struct NoteTitleField: View {
    @EnvironmentObject private var vault: VaultStore
    @State private var title = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Untitled", text: $title)
            .textFieldStyle(.plain)
            .font(.system(size: 30, weight: .bold, design: .rounded))
            .focused($focused)
            .onSubmit(commit)
            .onChange(of: vault.selection) { load() }
            .onAppear(perform: load)
    }

    private func load() {
        title = vault.selection.map { ($0.lastPathComponent as NSString).deletingPathExtension } ?? ""
    }

    private func commit() {
        guard let sel = vault.selection else { return }
        let current = (sel.lastPathComponent as NSString).deletingPathExtension
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != current { vault.rename(sel, to: trimmed) }
        else { load() }
    }
}
