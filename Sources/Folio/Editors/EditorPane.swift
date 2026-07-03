import SwiftUI
import AppKit

/// Hosts the note: a centered reading column with a Notion-style page title, the
/// Live Preview editor, a hover-reveal outline (right edge), and an inline
/// backlinks section (bottom). No side panels.
struct EditorPane: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var find = FindModel()

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
                .background { findShortcuts }
        } else {
            ContentUnavailableView("Select a note", systemImage: "doc.text",
                description: Text("Pick a note from the sidebar to start writing."))
        }
    }

    private var noteBody: some View {
        VStack(spacing: 0) {
            // Find bar is docked into the layout (below the tab bar, above the title)
            // so it's part of the page rather than floating over the content.
            if find.active {
                FindBar(find: find)
                    .frame(maxWidth: max(settings.readableWidth, 640))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            NoteTitleField()
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.top, find.active ? 10 : 28)
                .padding(.bottom, 2)
            if ui.mode == .read {
                ReadingView(find: find)
            } else {
                LivePreviewEditor(
                    text: $vault.content,
                    scrollTo: $vault.scrollRequest,
                    onChange: { vault.contentEdited() },
                    resolveWikilink: { vault.resolve($0) != nil },
                    noteNames: { vault.allNoteNames },
                    onOpenLink: openLink,
                    previewForLink: previewForLink,
                    background: settings.nsPaneBackground,
                    readableWidth: settings.readableWidth,
                    find: find
                )
            }
        }
        .animation(.smooth(duration: 0.18), value: find.active)
    }

    /// Invisible buttons carrying the find keyboard shortcuts, present in both modes.
    private var findShortcuts: some View {
        ZStack {
            Button("") { find.open() }.keyboardShortcut("f", modifiers: .command)
            Button("") { find.next() }.keyboardShortcut("g", modifiers: .command)
            Button("") { find.prev() }.keyboardShortcut("g", modifiers: [.command, .shift])
        }
        .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
    }

    /// Route a clicked link: `folio://wikilink?target=…` navigates/creates;
    /// http(s) opens in the browser.
    private func openLink(_ url: URL) -> Bool {
        if url.scheme == "folio", url.host == "wikilink" {
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

    /// Peek text for a hovered wikilink: the first ~800 chars of the target note.
    private func previewForLink(_ url: URL) -> String? {
        guard url.scheme == "folio", url.host == "wikilink" else { return nil }
        let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "target" })?.value ?? ""
        guard let dest = vault.resolve(target),
              let text = try? String(contentsOf: dest, encoding: .utf8) else { return nil }
        return String(text.prefix(800))
    }
}
