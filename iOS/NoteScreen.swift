import SwiftUI

/// A single note: reading mode (shared ReadingView) with a toggle to a light
/// Markdown editor. Edits write back through VaultStore's debounced save.
struct NoteScreen: View {
    let file: MarkdownFile
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var find = FindModel()   // find bar not yet wired on iOS

    var body: some View {
        Group {
            if ui.mode == .edit, !vault.isSelectionMissing {
                MarkdownEditScreen()
            } else {
                ReadingView(find: find)
            }
        }
        .background(settings.paneBackground ?? Color(.systemBackground))
        .navigationTitle(file.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        ui.mode = ui.mode == .edit ? .read : .edit
                    }
                } label: {
                    Image(systemName: ui.mode == .edit ? "book" : "pencil.line")
                }
                .accessibilityLabel(ui.mode == .edit ? "Reading mode" : "Edit")
                // A note whose file is gone from disk is read-only: the store
                // holds no write target for it, so an editor here would take
                // edits that could never be saved.
                .disabled(vault.isSelectionMissing)
            }
        }
        .onAppear { vault.select(file.id); ui.mode = .read }
        .onDisappear { vault.flushSave() }
        // The file can go while the screen is up (deleted on the Mac and synced,
        // or from the Files app); leave the editor the moment it does.
        .onChange(of: vault.isSelectionMissing) {
            if vault.isSelectionMissing { ui.mode = .read }
        }
    }
}

/// Plain Markdown editor; saves back via VaultStore (debounced) on each change.
private struct MarkdownEditScreen: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        TextEditor(text: $vault.content)
            .font(.system(size: settings.bodyFontSize, design: settings.readingFont.design))
            .lineSpacing(3)
            .scrollContentBackground(.hidden)
            .background(settings.paneBackground ?? Color(.systemBackground))
            .padding(.horizontal, 12)
            .onChange(of: vault.content) { vault.contentEdited() }
            .autocorrectionDisabled(false)
    }
}
