import SwiftUI

/// A single note: reading mode (shared ReadingView) with a toggle to a light
/// Markdown editor. Edits write back through VaultStore's debounced save.
struct NoteScreen: View {
    let file: MarkdownFile
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Group {
            if ui.mode == .edit {
                MarkdownEditScreen()
            } else {
                ReadingView()
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
            }
        }
        .onAppear { vault.select(file.id); ui.mode = .read }
        .onDisappear { vault.flushSave() }
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
