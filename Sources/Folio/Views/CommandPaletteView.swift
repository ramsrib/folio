import SwiftUI
import AppKit

struct AppCommand: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let run: () -> Void
}

/// ⌘P — fuzzy command palette, styled as a floating rounded palette. The registry
/// below is the single source of truth for runnable commands; it must stay in sync
/// with the menus in `FolioApp.swift` (every menu action should have a command here,
/// and shortcut strings should match). Matching + highlighting use the shared
/// `FuzzyMatch`, same as the quick switcher.
struct CommandPaletteView: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var settings: AppSettings
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    /// Every command the app exposes. Selection-dependent entries (Reveal, Copy
    /// Path, Trash, Close Tab) appear only when a note is open; recent vaults expand
    /// into "Switch Vault:" rows; themes into "Set Theme:" rows.
    private var commands: [AppCommand] {
        var c: [AppCommand] = [
            AppCommand(title: "New Note", subtitle: "⌘N") { vault.newNote() },
            AppCommand(title: "Open Vault…", subtitle: "⇧⌘O") { vault.pickVault() },
        ]
        for url in vault.recentVaults where url != vault.vaultURL {
            c.append(AppCommand(title: "Switch Vault: \(url.lastPathComponent)", subtitle: nil) { vault.setVault(url) })
        }
        c.append(AppCommand(title: "Reload Vault", subtitle: "⇧⌘R") { vault.refresh() })
        if let sel = vault.selection {
            c.append(AppCommand(title: "Close Tab", subtitle: "⌘W") { vault.closeTab(sel) })
        }
        c.append(AppCommand(title: "Reopen Closed Tab", subtitle: "⇧⌘T") { vault.reopenClosedTab() })
        c.append(AppCommand(title: "Next Tab", subtitle: "⌃⇥") { vault.cycleTab(1) })
        c.append(AppCommand(title: "Previous Tab", subtitle: "⌃⇧⇥") { vault.cycleTab(-1) })
        c.append(AppCommand(title: "Back", subtitle: "⌘[") { vault.goBack() })
        c.append(AppCommand(title: "Forward", subtitle: "⌘]") { vault.goForward() })
        c.append(AppCommand(title: "Toggle Sidebar", subtitle: "⌃⌘S") { ui.toggleSidebar &+= 1 })
        c.append(AppCommand(title: ui.mode == .read ? "Writing Mode" : "Reading Mode", subtitle: "⌘E") {
            ui.mode = ui.mode == .read ? .edit : .read })
        c.append(AppCommand(title: "Search Files…", subtitle: "⌘K") { ui.showQuickSwitcher = true })
        c.append(AppCommand(title: "Search in Vault…", subtitle: "⇧⌘F") { ui.showSearch = true })
        c.append(AppCommand(title: "Browse Tags", subtitle: "⇧⌘Y") { ui.showTags = true })
        c.append(AppCommand(title: "Filter Files", subtitle: nil) { ui.sidebarFilterFocus &+= 1 })
        for theme in AppTheme.allCases {
            c.append(AppCommand(title: "Set Theme: \(theme.label)", subtitle: nil) { settings.theme = theme })
        }
        c.append(AppCommand(title: "Bigger Text", subtitle: "⌘+") { settings.biggerText() })
        c.append(AppCommand(title: "Smaller Text", subtitle: "⌘−") { settings.smallerText() })
        c.append(AppCommand(title: "Reset Text Size", subtitle: "⌘0") { settings.resetTextSize() })
        if let sel = vault.selection {
            c.append(AppCommand(title: "Reveal in Finder", subtitle: nil) {
                NSWorkspace.shared.activateFileViewerSelecting([sel]) })
            c.append(AppCommand(title: "Copy Relative Path", subtitle: nil) { [vault] in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(vault.relativePath(for: sel), forType: .string) })
            c.append(AppCommand(title: "Copy Absolute Path", subtitle: nil) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(sel.path, forType: .string) })
            c.append(AppCommand(title: "Copy Wikilink", subtitle: nil) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("[[\((sel.lastPathComponent as NSString).deletingPathExtension)]]", forType: .string) })
            c.append(AppCommand(title: "Copy Folio Link", subtitle: nil) { [vault] in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(vault.folioLink(for: sel), forType: .string) })
            c.append(AppCommand(title: "Move Note to Trash", subtitle: nil) { vault.delete(sel) })
        }
        c.append(AppCommand(title: "Keyboard Shortcuts", subtitle: "⌘/") { ui.showShortcuts = true })
        return c
    }

    /// Fuzzy-ranked commands; empty query keeps registry order.
    private var results: [(cmd: AppCommand, match: FuzzyMatch.Result?)] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return commands.map { ($0, nil) } }
        return commands
            .compactMap { cmd -> (AppCommand, FuzzyMatch.Result)? in
                guard let m = FuzzyMatch.match(query: q, in: cmd.title) else { return nil }
                return (cmd, m)
            }
            .sorted { $0.1.score > $1.1.score }
            .map { ($0.0, $0.1) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "command").foregroundStyle(.secondary)
                TextField("Run a command…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .autocorrectionDisabled(true)
                    .onChange(of: query) { selected = 0 }
                    .onSubmit(runSelected)
            }
            .padding(16)
            Divider()
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(results.enumerated()), id: \.element.cmd.id) { idx, entry in
                        HStack {
                            Text(highlighted(entry.cmd.title, entry.match))
                            Spacer()
                            if let s = entry.cmd.subtitle {
                                Text(s).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                        .id(idx)
                        .onTapGesture { run(entry.cmd) }
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
        }
        .frame(width: 560, height: 420)
        .paletteSurface()
        .onAppear { focused = true; tamePaletteFieldEditor() }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.return) { runSelected(); return .handled }
        .onExitCommand { ui.showCommandPalette = false }
    }

    /// Emphasize the fuzzy-matched characters (bold + accent).
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

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selected = min(max(selected + delta, 0), results.count - 1)
    }

    private func runSelected() {
        guard results.indices.contains(selected) else { return }
        run(results[selected].cmd)
    }

    private func run(_ cmd: AppCommand) {
        ui.showCommandPalette = false
        cmd.run()
    }
}
