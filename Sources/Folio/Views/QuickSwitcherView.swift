import SwiftUI

/// ⌘O / ⌘K — fuzzy "open note by name" overlay, styled as a floating rounded
/// palette. Empty query lists recently-opened notes; a `#`-prefixed query switches
/// to heading-jump mode over the current note's outline; a query that matches no
/// note name offers a create-on-miss row.
struct QuickSwitcherView: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var settings: AppSettings
    @State private var query = ""
    @State private var selected = 0
    /// Every note's name and path, prepared once when the palette opens. Matching
    /// raw strings re-lowercases and re-allocates per candidate, which on a
    /// couple of thousand notes costs ~12ms a keystroke; this costs ~0.4ms.
    @State private var index: [Indexed] = []
    /// The visible list, recomputed only when the query changes. It used to be a
    /// computed property read twice per body pass (the `ForEach` and the
    /// empty-state `overlay`), so every keystroke matched the whole vault twice.
    @State private var rows: [Row] = []

    private struct Indexed {
        let file: MarkdownFile
        let name: FuzzyMatch.Prepared
        let path: FuzzyMatch.Prepared
    }

    // MARK: Row model

    /// A scored file plus the fuzzy hits in its name/path (for highlighting).
    private struct Candidate {
        let file: MarkdownFile
        let nameMatch: FuzzyMatch.Result?
        let pathMatch: FuzzyMatch.Result?
    }

    private enum Row: Identifiable {
        case file(Candidate)
        case heading(OutlineItem, FuzzyMatch.Result?)
        case create(String)
        var id: String {
            switch self {
            case .file(let c):        return "f:" + c.file.id.path
            case .heading(let h, _):  return "h:\(h.charIndex)"
            case .create:             return "create"
            }
        }
    }

    private var isHeadingMode: Bool { query.hasPrefix("#") }
    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    // MARK: Ranking

    /// Files ranked by fuzzy score (name weighted above path), tie-broken by
    /// recency, then natural name order. Empty query → recents first (excluding the
    /// current note), then the rest alphabetically. Capped at 50 rows.
    private func buildIndex() {
        index = vault.files.map {
            Indexed(file: $0,
                    name: FuzzyMatch.Prepared($0.name),
                    path: FuzzyMatch.Prepared($0.relativePath))
        }
    }

    private func recompute() {
        rows = isHeadingMode
            ? headingCandidates.map { Row.heading($0.0, $0.1) }
            : fileCandidates.map(Row.file) + (showsCreate ? [Row.create(trimmedQuery)] : [])
    }

    private var fileCandidates: [Candidate] {
        if trimmedQuery.isEmpty {
            let recent = vault.recentFiles
                .compactMap { url in vault.files.first { $0.id == url } }
                .filter { $0.id != vault.selection }
            let recentIDs = Set(recent.map(\.id))
            let rest = vault.files.filter { !recentIDs.contains($0.id) && $0.id != vault.selection }
            return (recent + rest).prefix(50).map { Candidate(file: $0, nameMatch: nil, pathMatch: nil) }
        }
        let q = FuzzyMatch.queryCharacters(trimmedQuery)
        let scored: [(cand: Candidate, score: Int)] = index.compactMap { entry in
            // Reject on a cheap in-order character scan before scoring anything.
            let nameCould = entry.name.couldMatch(q), pathCould = entry.path.couldMatch(q)
            guard nameCould || pathCould else { return nil }
            let f = entry.file
            let nameM = nameCould ? FuzzyMatch.match(query: q, in: entry.name) : nil
            let pathM = pathCould ? FuzzyMatch.match(query: q, in: entry.path) : nil
            guard nameM != nil || pathM != nil else { return nil }
            // Name matches count double so a filename hit outranks a path-only hit.
            let score = max((nameM?.score ?? 0) * 2, pathM?.score ?? 0)
            return (Candidate(file: f, nameMatch: nameM, pathMatch: pathM), score)
        }
        let sorted = scored.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            let ra = recencyRank(a.cand.file.id), rb = recencyRank(b.cand.file.id)
            if ra != rb { return ra < rb }
            return a.cand.file.name.localizedStandardCompare(b.cand.file.name) == .orderedAscending
        }
        return sorted.prefix(50).map(\.cand)
    }

    private func recencyRank(_ url: URL) -> Int { vault.recentFiles.firstIndex(of: url) ?? .max }

    /// Headings of the current note, fuzzy-filtered by the query after the `#`.
    private var headingCandidates: [(OutlineItem, FuzzyMatch.Result?)] {
        let q = String(query.dropFirst()).trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return vault.outline.map { ($0, nil) } }
        return vault.outline
            .compactMap { item -> (OutlineItem, FuzzyMatch.Result, Int)? in
                guard let m = FuzzyMatch.match(query: q, in: item.title) else { return nil }
                return (item, m, m.score)
            }
            .sorted { $0.2 > $1.2 }
            .map { ($0.0, $0.1) }
    }

    /// Offer create-on-miss when the (file-mode) query names no existing note.
    private var showsCreate: Bool {
        guard !isHeadingMode, !trimmedQuery.isEmpty else { return false }
        return !vault.files.contains { $0.name.lowercased() == trimmedQuery.lowercased() }
    }

    // MARK: View

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: isHeadingMode ? "number" : "magnifyingglass").foregroundStyle(.secondary)
                PaletteTextField(text: $query,
                                 placeholder: isHeadingMode ? "Jump to heading…" : "Search files by name…  (# for headings)",
                                 onSubmit: { handleSubmit($0) },
                                 onMoveUp: { move(-1) }, onMoveDown: { move(1) })
                    .frame(height: 22)
                    .onChange(of: query) { selected = 0; recompute() }
            }
            .padding(16)
            Divider()
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                        rowView(row, selected: idx == selected)
                            .id(idx)
                            .onTapGesture { activate(row, newTab: commandHeld) }
                            .listRowSeparator(.hidden)
                            .listRowBackground(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(idx == selected ? settings.selectionFill : .clear)
                            )
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(8, for: .scrollContent)
                .animation(.easeOut(duration: 0.12), value: selected)
                .onChange(of: selected) { proxy.scrollTo(selected, anchor: .center) }
                .overlay { if rows.isEmpty { emptyState } }
            }
            Divider()
            footer
        }
        .frame(width: 620, height: 460)
        .paletteSurface()
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.return, phases: .down) { handleReturn($0.modifiers) }
        .task { buildIndex(); recompute() }
        .onChange(of: vault.files.count) { buildIndex(); recompute() }
        .onExitCommand { ui.showQuickSwitcher = false }
    }

    @ViewBuilder
    private func rowView(_ row: Row, selected: Bool) -> some View {
        switch row {
        case .file(let c):
            fileRow(c)
        case .heading(let item, let match):
            headingRow(item, match)
        case .create(let q):
            createRow(q)
        }
    }

    private func fileRow(_ c: Candidate) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(FuzzyMatch.highlighted(c.file.name, c.nameMatch, tint: settings.selectionTint)).lineLimit(1)
                if c.file.relativePath != "\(c.file.name).md" {
                    Text(FuzzyMatch.highlighted(c.file.relativePath, c.pathMatch, tint: settings.selectionTint))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
        }
        .rowChrome()
    }

    private func headingRow(_ item: OutlineItem, _ match: FuzzyMatch.Result?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "number").foregroundStyle(.secondary)
            Text(FuzzyMatch.highlighted(item.title, match, tint: settings.selectionTint)).lineLimit(1)
                // Indent deeper headings so the outline hierarchy reads at a glance.
                .padding(.leading, CGFloat(item.level - 1) * 14)
            Spacer()
        }
        .rowChrome()
    }

    private func createRow(_ q: String) -> some View {
        var label = AttributedString("Create ")
        var quoted = AttributedString("\"\(q)\"")
        quoted.inlinePresentationIntent = .stronglyEmphasized
        label += quoted
        return HStack(spacing: 8) {
            Image(systemName: "plus.circle").foregroundStyle(settings.selectionTint)
            Text(label)
            Spacer()
        }
        .rowChrome()
    }

    @ViewBuilder private var emptyState: some View {
        if isHeadingMode {
            Text(vault.outline.isEmpty ? "No headings in this note" : "No matching headings")
                .foregroundStyle(.secondary)
        } else {
            Text("No matching files").foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            hint("↵", "open"); hint("⌘↵", "new tab"); hint("⇧↵", "create"); hint("#", "headings")
            Spacer()
        }
        .font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private func hint(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(keys).font(.caption.monospaced())
            Text(label)
        }
    }

    // MARK: Highlighting


    // MARK: Actions

    /// Whether ⌘ is down for the click being handled — `onTapGesture` doesn't
    /// carry modifiers, so read them off the event the way the reading view's
    /// wikilink handler does.
    private var commandHeld: Bool {
        NSApp.currentEvent?.modifierFlags.contains(.command) ?? false
    }

    private func move(_ delta: Int) {
        guard !rows.isEmpty else { return }
        selected = min(max(selected + delta, 0), rows.count - 1)
    }

    /// AppKit modifier flags from PaletteTextField → the same return handling.
    private func handleSubmit(_ flags: NSEvent.ModifierFlags) {
        var mods: EventModifiers = []
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.command) { mods.insert(.command) }
        _ = handleReturn(mods)
    }

    /// ↵ opens/jumps in the current tab; ⌘↵ opens in a new tab; ⇧↵ creates from
    /// the query anywhere. The ⌘ split matches Notion (and the browser it models):
    /// navigating goes where you already are unless you ask for a new tab.
    private func handleReturn(_ modifiers: EventModifiers) -> KeyPress.Result {
        if modifiers.contains(.shift) {
            // Not in heading mode — a "#…" query is a jump target, not a note name.
            if !isHeadingMode, !trimmedQuery.isEmpty { createFromQuery() }
            return .handled
        }
        guard rows.indices.contains(selected) else { return .handled }
        activate(rows[selected], newTab: modifiers.contains(.command))
        return .handled
    }

    private func activate(_ row: Row, newTab: Bool) {
        switch row {
        case .file(let c):        vault.select(c.file.id, inNewTab: newTab)
        case .heading(let item, _): vault.scrollRequest = item.charIndex
        case .create(let q):      vault.createNote(named: q)
        }
        ui.showQuickSwitcher = false
    }

    private func createFromQuery() {
        vault.createNote(named: trimmedQuery)
        ui.showQuickSwitcher = false
    }
}

/// Shared padding/hit-area for a switcher row.
private extension View {
    func rowChrome() -> some View {
        self.padding(.vertical, 5).padding(.horizontal, 8).contentShape(Rectangle())
    }
}
