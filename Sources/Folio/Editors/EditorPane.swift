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
                // Ambient write-mode signal: a hairline accent rule pinned to the
                // pane's top edge, present only while editing — the mode stays
                // glanceable peripherally without a banner. (Reading needs no
                // signal; it's the default state.)
                .overlay(alignment: .top) {
                    ZStack {
                        if ui.mode == .edit {
                            Rectangle().fill(settings.selectionTint.opacity(0.5))
                                .frame(height: 2)
                                .transition(.opacity)
                        }
                    }
                    .animation(.smooth(duration: 0.2), value: ui.mode)
                    .allowsHitTesting(false)
                }
                .background(settings.paneBackground ?? Color(nsColor: .textBackgroundColor))
                .background { findShortcuts }
                // A global-search hit hands us a query + occurrence to focus.
                .onChange(of: ui.pendingFind) { consumePendingFind() }
                .onAppear { consumePendingFind() }
                // Esc in reading mode (routed via the key monitor): close the
                // find bar if it's open; otherwise it was consumed just to stay
                // silent — Esc has no further meaning while reading.
                .onChange(of: ui.escapePulse) { if find.active { find.close() } }
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
                    .frame(maxWidth: max(settings.readableWidth, 640))   // not columnWidth: a full-width bar reads badly
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    // Composite above the reading scroll view (a *later* sibling
                    // paints over the bar's downward shadow otherwise — it
                    // rendered with a hard cutoff line in reading mode).
                    .zIndex(1)
            }
            if settings.showInlineTitle {
                NoteTitleField()
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.top, find.active ? 10 : 28)
                    .padding(.bottom, 2)
            }
            // NoteReader stays mounted (hidden) while writing: remounting it on
            // every mode switch paid an empty frame + full parse + full document
            // layout inside the switch animation — over a second on bigger notes.
            // Kept alive it costs nothing per keystroke (its parse task freezes
            // while hidden, see NoteReader.parseTaskID) and edit→read becomes an
            // opacity flip, plus one visible re-layout only if the text changed.
            ZStack {
                NoteReader(find: find)
                    .opacity(ui.mode == .read ? 1 : 0)
                    .allowsHitTesting(ui.mode == .read)
                    .accessibilityHidden(ui.mode != .read)
                if ui.mode == .edit {
                    LivePreviewEditor(
                    text: $vault.content,
                    scrollTo: $vault.scrollRequest,
                    onChange: { vault.contentEdited() },
                    resolveWikilink: { vault.resolve($0) != nil },
                    noteNames: { vault.allNoteNames },
                    onOpenLink: openLink,
                    previewForLink: previewForLink,
                    // Esc is the exit ramp: close the find bar if it's open,
                    // otherwise return home to reading.
                    onEscape: {
                        if find.active { find.close() }
                        else { withAnimation(.smooth(duration: 0.2)) { ui.mode = .read } }
                    },
                        background: settings.nsPaneBackground,
                        selectionHighlight: settings.nsSelectionHighlight,
                        caretColor: settings.nsCaretColor,
                        readableWidth: settings.columnWidth,
                        theme: Theme(settings),
                        find: find
                    )
                }
            }
        }
        .animation(.smooth(duration: 0.18), value: find.active)
    }

    /// Apply a jump requested by global search: open the find bar on the query and
    /// focus the requested occurrence. `FindModel.query`'s didSet already zeroes
    /// `current`, and ReadingView no longer re-zeroes it on the query change, so
    /// setting `current` right after `query` survives into the recompute. If the
    /// occurrence is out of range (e.g. reading-mode block parsing counts matches
    /// slightly differently), the mode's recompute clamps it to the nearest match.
    private func consumePendingFind() {
        guard let pending = ui.pendingFind else { return }
        ui.pendingFind = nil
        find.query = pending.query
        find.active = true
        find.current = pending.occurrence
        find.focusRequest &+= 1
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
            // ⌘-click a wikilink → open in a new tab.
            let newTab = NSApp.currentEvent?.modifierFlags.contains(.command) ?? false
            vault.openWikilink(target, inNewTab: newTab)
            return true
        }
        if url.scheme == "http" || url.scheme == "https" {
            NSWorkspace.shared.open(url)
            return true
        }
        // Relative/file links — resolve against the note/vault (see openLocalLink).
        if url.scheme == nil || url.isFileURL {
            vault.openLocalLink(url.isFileURL ? url.path : url.absoluteString)
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
