import SwiftUI
import AppKit

/// Hosts the note: a centered reading column with a Notion-style page title, the
/// Live Preview editor, a hover-reveal outline (right edge), and an inline
/// backlinks section (bottom). No side panels.
struct EditorPane: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        if vault.selection != nil {
            noteBody
                .overlay(alignment: .topTrailing) {
                    OutlineFloater().padding(.top, 14).padding(.trailing, 10)
                }
                .overlay(alignment: .bottom) {
                    BacklinksBar().frame(maxWidth: .infinity)
                }
                .background(settings.paneBackground ?? Color(nsColor: .textBackgroundColor))
        } else {
            ContentUnavailableView("Select a note", systemImage: "doc.text",
                description: Text("Pick a note from the sidebar to start editing."))
        }
    }

    private var noteBody: some View {
        VStack(spacing: 0) {
            NoteTitleField()
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.top, 28)
                .padding(.bottom, 2)
            if ui.mode == .read {
                ReadingView()
            } else {
                LivePreviewEditor(
                    text: $vault.content,
                    scrollTo: $vault.scrollRequest,
                    onChange: { vault.contentEdited() },
                    resolveWikilink: { vault.resolve($0) != nil },
                    noteNames: { vault.allNoteNames },
                    onOpenLink: openLink,
                    background: settings.nsPaneBackground,
                    readableWidth: settings.readableWidth
                )
            }
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
}
