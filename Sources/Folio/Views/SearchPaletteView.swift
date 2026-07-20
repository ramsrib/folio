import SwiftUI

/// ⇧⌘F — vault-wide content search. Results are grouped per file (a file-name
/// header + up to a few matched-line snippets); ↑↓ walk the snippet rows across
/// groups, ↵ opens the note and lands the find bar on that exact occurrence,
/// ⌘↵ opens it in a new tab, Esc closes.
struct SearchPaletteView: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var model = ContentSearchModel()
    @State private var query = ""
    @State private var selected = 0        // flat index across all snippet rows
    @FocusState private var focused: Bool

    // Flattened, renderable structure: a header per file followed by its snippet
    // rows; snippet rows carry their flat index for selection + scroll targeting.
    private enum Element: Identifiable {
        case header(ContentSearchModel.FileResult)
        case snippet(file: MarkdownFile, snippet: ContentSearchModel.Snippet, flat: Int)
        var id: String {
            switch self {
            case .header(let fr):            return "h:" + fr.file.id.path
            case .snippet(_, let s, _):      return "s:\(s.id)"
            }
        }
    }

    private var elements: [Element] {
        var out: [Element] = []
        var flat = 0
        for fr in model.results {
            out.append(.header(fr))
            for s in fr.snippets { out.append(.snippet(file: fr.file, snippet: s, flat: flat)); flat += 1 }
        }
        return out
    }

    private var hitCount: Int { model.results.reduce(0) { $0 + $1.snippets.count } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "text.magnifyingglass").foregroundStyle(.secondary)
                TextField("Search in vault…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .autocorrectionDisabled(true)
                    .onChange(of: query) { runSearch() }
                if model.isSearching { ProgressView().controlSize(.small) }
            }
            .padding(16)
            Divider()
            ScrollViewReader { proxy in
                List {
                    ForEach(elements) { element in
                        elementView(element)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(8, for: .scrollContent)
                .animation(.easeOut(duration: 0.12), value: selected)
                .onChange(of: selected) { proxy.scrollTo(selected, anchor: .center) }
                .overlay { emptyState }
            }
            Divider()
            footer
        }
        .frame(width: 700, height: 540)
        .paletteSurface()
        .onAppear {
            focused = true
            tamePaletteFieldEditor()
            // Re-assert focus a runloop later: if something else held first
            // responder when the palette appeared (the editor, a filter field),
            // the immediate request can lose the race and leave the field dead.
            DispatchQueue.main.async { focused = true }
        }
        .onDisappear { model.cancel() }
        // Keep results live if the vault changes while the palette is open — the
        // revision counter bumps on every refresh (rename, external edit, create,
        // delete), and mtime keying re-reads only what actually changed.
        .onChange(of: vault.revision) { runSearch() }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.return, phases: .down) { handleReturn($0.modifiers) }
        .onExitCommand { ui.showSearch = false }
    }

    @ViewBuilder
    private func elementView(_ element: Element) -> some View {
        switch element {
        case .header(let fr):
            HStack(spacing: 6) {
                Image(systemName: "doc.text").font(.caption).foregroundStyle(.secondary)
                Text(fr.file.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text("·").foregroundStyle(.tertiary)
                Text("\(fr.matchCount)").font(.caption).foregroundStyle(.secondary)
                if fr.file.relativePath != "\(fr.file.name).md" {
                    Text(fr.file.relativePath).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
                Spacer()
            }
            .padding(.top, 8).padding(.bottom, 2).padding(.horizontal, 6)

        case let .snippet(file, snippet, flat):
            Text(snippetText(snippet))
                .font(.system(size: 12.5))
                .lineLimit(2)
                .padding(.vertical, 5).padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(flat == selected ? settings.selectionFill : .clear))
                .contentShape(Rectangle())
                .id(flat)
                .onTapGesture { open(file, snippet, newTab: false) }
        }
    }

    /// Render the snippet line with the matched substring emphasized.
    private func snippetText(_ s: ContentSearchModel.Snippet) -> AttributedString {
        var attr = AttributedString(s.line)
        if let lo = AttributedString.Index(s.range.lowerBound, within: attr),
           let hi = AttributedString.Index(s.range.upperBound, within: attr) {
            attr[lo..<hi].inlinePresentationIntent = .stronglyEmphasized
            attr[lo..<hi].foregroundColor = settings.selectionTint
        }
        return attr
    }

    @ViewBuilder private var emptyState: some View {
        if !query.isEmpty, model.results.isEmpty, !model.isSearching {
            Text("No matches").foregroundStyle(.secondary)
        } else if query.isEmpty {
            Text("Type to search across every note").foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if !query.isEmpty, !model.results.isEmpty {
                Text("\(model.totalMatches) \(model.totalMatches == 1 ? "match" : "matches") in \(model.totalFiles) \(model.totalFiles == 1 ? "file" : "files")")
                if model.capped {
                    Text("· showing top \(ContentSearchModel.fileCap)").foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text("↵ open · ⌘↵ new tab · esc close").font(.caption.monospaced()).foregroundStyle(.tertiary)
        }
        .font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    // MARK: Actions

    private func runSearch() {
        selected = 0
        model.search(query, files: vault.files)
    }

    private func move(_ delta: Int) {
        guard hitCount > 0 else { return }
        selected = min(max(selected + delta, 0), hitCount - 1)
    }

    private func handleReturn(_ modifiers: EventModifiers) -> KeyPress.Result {
        guard let (file, snippet) = hit(at: selected) else { return .handled }
        open(file, snippet, newTab: modifiers.contains(.command))
        return .handled
    }

    private func hit(at flat: Int) -> (MarkdownFile, ContentSearchModel.Snippet)? {
        var i = flat
        for fr in model.results {
            if i < fr.snippets.count { return (fr.file, fr.snippets[i]) }
            i -= fr.snippets.count
        }
        return nil
    }

    private func open(_ file: MarkdownFile, _ snippet: ContentSearchModel.Snippet, newTab: Bool) {
        // Set the jump before selecting so EditorPane observes it in the same update
        // and lands the find bar on this occurrence.
        ui.pendingFind = PendingFind(query: query, occurrence: snippet.occurrence)
        vault.select(file.id, inNewTab: newTab)
        ui.showSearch = false
    }
}
