import SwiftUI

/// Notion-style large page title at the top of a note. In Writing mode it's an
/// editable field — editing it renames the file (and updates links across the
/// vault) on commit. In Reading mode it's plain, non-focusable text, so clicking
/// it never steals keyboard focus from the page.
struct NoteTitleField: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var settings: AppSettings
    @State private var title = ""
    @FocusState private var focused: Bool

    private let titleFont = Font.system(size: 30, weight: .bold, design: .rounded)

    var body: some View {
        Group {
            if ui.mode == .read {
                Text(title.isEmpty ? "Untitled" : title)
                    .font(titleFont)
                    .foregroundStyle(title.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("Untitled", text: $title)
                    .textFieldStyle(.plain)
                    .font(titleFont)
                    .focused($focused)
                    .onSubmit(commit)
                    // NSTextField edits through the window's shared field editor,
                    // so its caret is unreachable from here; `.tint` is the hook
                    // SwiftUI gives for it.
                    .tint(settings.selectionTint)
            }
        }
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
