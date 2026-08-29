import SwiftUI

/// ⇧⌘O — pick a vault. Each one opens (or focuses) its own window, so switching
/// never closes the vault you were reading.
///
/// Mirrors `QuickSwitcherView`'s shape deliberately: same fuzzy match, same keys,
/// same chrome. The only new idea here is the row for a vault that isn't in
/// recents yet.
struct VaultSwitcherView: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openWindow) private var openWindow
    @State private var query = ""
    @State private var selected = 0

    private enum Row: Identifiable {
        case vault(URL, FuzzyMatch.Result?)
        case browse
        var id: String {
            switch self {
            case .vault(let url, _): return "v:" + url.path
            case .browse:            return "browse"
            }
        }
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    /// Recents, current vault first so the list reads as "where you are, and
    /// where else you've been".
    private var vaults: [(URL, FuzzyMatch.Result?)] {
        let all = vault.recentVaults.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !trimmed.isEmpty else { return all.map { ($0, nil) } }
        return all.compactMap { url in
            guard let m = FuzzyMatch.match(query: trimmed, in: url.lastPathComponent)
                    ?? FuzzyMatch.match(query: trimmed, in: url.path) else { return nil }
            return (url, m)
        }
        .sorted { ($0.1?.score ?? 0) > ($1.1?.score ?? 0) }
    }

    private var rows: [Row] {
        vaults.map { Row.vault($0.0, $0.1) } + [.browse]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "shippingbox").foregroundStyle(.secondary)
                PaletteTextField(text: $query,
                                 placeholder: "Switch vault…",
                                 onSubmit: { _ in activate() },
                                 onMoveUp: { move(-1) }, onMoveDown: { move(1) })
                    .frame(height: 22)
                    .onChange(of: query) { selected = 0 }
            }
            .padding(16)
            Divider()
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                        rowView(row, selected: idx == selected)
                            .id(idx)
                            .onTapGesture { selected = idx; activate() }
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
            }
            Divider()
            HStack(spacing: 10) {
                hint("↵", "open window"); hint("⌘↵", "browse…")
                Spacer()
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
        .frame(width: 560, height: 400)
        .paletteSurface()
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.return, phases: .down) { press in
            if press.modifiers.contains(.command) { browse() } else { activate() }
            return .handled
        }
        .onExitCommand { ui.showVaultSwitcher = false }
    }

    @ViewBuilder
    private func rowView(_ row: Row, selected: Bool) -> some View {
        switch row {
        case let .vault(url, match):
            let isCurrent = url.standardizedFileURL.path == vault.vaultURL?.standardizedFileURL.path
            HStack(spacing: 8) {
                Image(systemName: isCurrent ? "shippingbox.fill" : "shippingbox")
                    .foregroundStyle(isCurrent ? settings.selectionTint : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(highlighted(url.lastPathComponent, match)).lineLimit(1)
                    Text(url.deletingLastPathComponent().path.abbreviatingHome)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if isCurrent {
                    Text("this window").font(.caption).foregroundStyle(.secondary)
                }
            }
            .rowChrome()
        case .browse:
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.plus").foregroundStyle(settings.selectionTint)
                Text("Open Other Vault…")
                Spacer()
            }
            .rowChrome()
        }
    }

    private func hint(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(keys).font(.caption.monospaced())
            Text(label)
        }
    }

    private func highlighted(_ string: String, _ match: FuzzyMatch.Result?) -> AttributedString {
        guard let match, !match.matchedIndices.isEmpty else { return AttributedString(string) }
        let hits = Set(match.matchedIndices)
        var result = AttributedString()
        var i = string.startIndex
        while i < string.endIndex {
            var piece = AttributedString(String(string[i]))
            if hits.contains(i) {
                piece.inlinePresentationIntent = .stronglyEmphasized
                piece.foregroundColor = settings.selectionTint
            }
            result += piece
            i = string.index(after: i)
        }
        return result
    }

    // MARK: Actions

    private func move(_ delta: Int) {
        guard !rows.isEmpty else { return }
        selected = min(max(selected + delta, 0), rows.count - 1)
    }

    private func activate() {
        guard rows.indices.contains(selected) else { return }
        switch rows[selected] {
        case let .vault(url, _):
            ui.showVaultSwitcher = false
            // Opening by value focuses the window that already holds this vault
            // instead of making a second one.
            VaultWindows.open(VaultRef(url), using: openWindow)
        case .browse:
            browse()
        }
    }

    private func browse() {
        ui.showVaultSwitcher = false
        if let url = VaultPicker.choose() { VaultWindows.open(VaultRef(url), using: openWindow) }
    }
}

private extension View {
    func rowChrome() -> some View {
        padding(.vertical, 5).padding(.horizontal, 8).contentShape(Rectangle())
    }
}

extension String {
    /// `/Users/me/Projects` → `~/Projects`, for palette subtitles.
    var abbreviatingHome: String {
        let home = NSHomeDirectory()
        return hasPrefix(home) ? "~" + dropFirst(home.count) : self
    }
}
