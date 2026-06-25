import SwiftUI
import AppKit

/// Hosts the Live Preview editor for the selected note (or an empty state).
struct EditorPane: View {
    @EnvironmentObject private var vault: VaultStore

    var body: some View {
        if vault.selection != nil {
            LivePreviewEditor(
                text: $vault.content,
                scrollTo: $vault.scrollRequest,
                onChange: { vault.contentEdited() },
                resolveWikilink: { vault.resolve($0) != nil },
                noteNames: { vault.allNoteNames },
                onOpenLink: openLink
            )
            .background(Color(nsColor: .textBackgroundColor))
            .toolbar { ToolbarItem(placement: .status) { saveStatus } }
        } else {
            ContentUnavailableView("Select a note", systemImage: "doc.text",
                description: Text("Pick a note from the sidebar to start editing."))
        }
    }

    /// Route a clicked link: `slate://wikilink?target=…` navigates/creates;
    /// http(s) opens in the browser.
    private func openLink(_ url: URL) -> Bool {
        if url.scheme == "slate", url.host == "wikilink" {
            let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "target" })?.value ?? ""
            vault.openWikilink(target)
            return true
        }
        if url.scheme == "http" || url.scheme == "https" {
            NSWorkspace.shared.open(url)
            return true
        }
        return false
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
