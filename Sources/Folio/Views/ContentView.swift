import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var settings: AppSettings
    @State private var renameTarget: URL?
    @State private var renameText = ""
    @State private var expandedDirs: Set<URL> = []
    @State private var showSidebar = true
    @State private var sidebarWidth: CGFloat = 280
    @State private var dragStartWidth: CGFloat?
    @State private var filter = ""
    /// The filter field is collapsed by default — a permanently mounted TextField
    /// grabs first-responder at launch and competes with the palettes for focus.
    /// Revealed by the sidebar's magnifier icon, ⇧⌘K, or the command palette.
    @State private var showFilter = false
    @State private var vaultNameHovered = false
    @Environment(\.windowCoordinator) private var coordinator
    /// For manual double-click detection on the title bar (see `sidebarTitleArea`).
    @State private var lastTitleClick = Date.distantPast
    @FocusState private var filterFocused: Bool

    private let expandedKey = "folio.expandedByVault"   // [vaultPath: [dirPath]]
    private var filterActive: Bool { !filter.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            // Divider drawn as an overlay on the title bar's bottom edge (not a
            // separate row) so it sits on the bar's own background — otherwise, in
            // the see-through Frosted window, that 1pt seam shows the desktop.
            titleBar
                .overlay(alignment: .bottom) { Divider() }
            HStack(spacing: 0) {
                if showSidebar {
                    sidebar.frame(width: sidebarWidth)
                    resizeDivider
                }
                EditorPane()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea(.container, edges: .top)   // let the title-bar row reach the traffic-light line
        .background(WindowConfigurator(background: settings.nsWindowBackground,
                                       translucent: settings.windowIsTranslucent))
        .background { navigationShortcuts }
        .background { GestureMonitor(vault: vault, settings: settings, ui: ui) }   // trackpad swipe/pinch
        .onChange(of: ui.toggleSidebar) { withAnimation(.smooth(duration: 0.2)) { showSidebar.toggle() } }
        // Root-level: if the sidebar is hidden its subtree (and the reveal handler
        // in it) isn't mounted — show it first; the tree's onAppear finishes the job.
        .onChange(of: vault.sidebarRevealRequest) {
            if vault.sidebarRevealRequest != nil, !showSidebar {
                withAnimation(.smooth(duration: 0.2)) { showSidebar = true }
            }
        }
        // Handled at the root (not inside the sidebar subtree): when the sidebar is
        // hidden its views aren't mounted, so a handler there would never fire —
        // reveal the sidebar and the collapsed field first, then focus it once it
        // exists in the hierarchy.
        .onChange(of: ui.sidebarFilterFocus) {
            withAnimation(.smooth(duration: 0.2)) {
                if !showSidebar { showSidebar = true }
                showFilter = true
            }
            DispatchQueue.main.async { filterFocused = true }
        }
        .overlay { paletteOverlay }
        .animation(.easeOut(duration: 0.14), value: paletteShown)
        .onChange(of: vault.selection) {
            // Only assign when the mode actually changes: setting a @Published
            // property fires objectWillChange even for same-value writes, which
            // re-rendered the whole window a second time on every tab switch.
            let target: EditorMode = vault.openInEditMode ? .edit : .read
            if ui.mode != target { ui.mode = target }
            vault.openInEditMode = false
        }
        .alert("Rename Note", isPresented: renamePresented) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Rename") {
                if let t = renameTarget { vault.rename(t, to: renameText) }
                renameTarget = nil
            }
        }
    }

    // MARK: Command palettes — in-window overlays (not sheets), so there's no
    // sheet window to flash white on first present. A transparent backdrop
    // catches clicks outside the palette to dismiss it; Esc still works via each
    // palette's own onExitCommand.

    private var paletteShown: Bool { ui.anyPaletteShown }

    @ViewBuilder
    private var paletteOverlay: some View {
        if paletteShown {
            ZStack {
                Color.black.opacity(0.001)        // invisible click-catcher
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { ui.dismissPalettes() }
                Group {
                    if ui.showCommandPalette { CommandPaletteView() }
                    else if ui.showQuickSwitcher { QuickSwitcherView() }
                    else if ui.showSearch { SearchPaletteView() }
                    else if ui.showVaultSwitcher { VaultSwitcherView() }
                    else if ui.showTags { TagsView() }
                    else if ui.showShortcuts { ShortcutsView() }
                    else if ui.showSettings { SettingsView() }
                }
            }
            .transition(.opacity)
        }
    }

    /// Invisible buttons carrying the keyboard shortcuts that have no discoverable
    /// menu item of their own: ⌘O (quick switcher, alongside ⌘K), the ⌘⌥←/→ history
    /// combos (Back/Forward also live in the menu as ⌘[ / ⌘]), and ⌘1…⌘8 / ⌘9 tab
    /// access. Kept out of the menus so the menus stay tidy; documented in
    /// ShortcutsView instead. Mirrors EditorPane.findShortcuts.
    private var navigationShortcuts: some View {
        ZStack {
            Button("") { ui.showQuickSwitcher = true }.keyboardShortcut("o", modifiers: .command)
            Button("") { vault.goBack() }.keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Button("") { vault.goForward() }.keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            ForEach(1...8, id: \.self) { n in
                Button("") { vault.activateTab(n - 1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
            }
            Button("") { vault.activateLastTab() }.keyboardShortcut("9", modifiers: .command)
        }
        .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
    }

    // MARK: Title bar — split into a sidebar title area + a content title area
    // (aligned with the columns below), filling the title-bar strip via
    // fullSizeContentView. Tabs live only in the content area and scroll.

    private var titleBar: some View {
        HStack(spacing: 0) {
            if showSidebar {
                sidebarTitleArea
                    .frame(width: sidebarWidth, height: 42)
                    .background(sidebarBackdrop)
                Divider()
            }
            contentTitleArea
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(settings.topBarBackground)
        }
        .frame(height: 42)
        // The custom title-bar strip is the window's (only) drag handle, like a
        // native toolbar. Buttons and the tab strip's own onDrag still win —
        // child interactions take precedence over this parent gesture.
        // (The zoom double-click deliberately does NOT live here: a count-2
        // recognizer over the tab strip delays every tab click by the
        // double-click interval. It's on the sidebar title area instead.)
        .gesture(WindowDragGesture())
    }

    /// Perform the system-configured title-bar double-click action ("Double-click
    /// a window's title bar to…" in System Settings ▸ Desktop & Dock).
    private func titleBarDoubleClicked() {
        guard let window = NSApp.keyWindow else { return }
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize": window.performMiniaturize(nil)
        case "None":     break
        default:         window.performZoom(nil)   // "Fill"/"Zoom" — the default
        }
    }

    private var sidebarTitleArea: some View {
        ZStack {
            // Vault title centered in the sidebar column, growing symmetrically on
            // both sides. The 78pt horizontal clearance keeps it clear of the
            // traffic lights (left) and the trailing controls (right) when long.
            // The vault name drops a native menu (Obsidian's shape): anchored to
            // the control you clicked, standard chrome, instant.
            //
            // Deliberately independent of ⇧⌘O's searchable palette rather than a
            // route into it — a click on a named control and a global shortcut are
            // different gestures, and each gets the presentation that suits it.
            Menu {
                ForEach(vault.recentVaults.filter { FileManager.default.fileExists(atPath: $0.path) },
                        id: \.self) { url in
                    Button {
                        coordinator?.open(VaultRef(url))
                    } label: {
                        if url.standardizedFileURL.path == vault.vaultURL?.standardizedFileURL.path {
                            Label(url.lastPathComponent, systemImage: "checkmark")
                        } else {
                            Text(url.lastPathComponent)
                        }
                    }
                }
                Divider()
                Button("Open Other Vault…") {
                    if let url = VaultPicker.choose() { coordinator?.open(VaultRef(url)) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(vault.vaultURL?.lastPathComponent ?? "Folio")
                        .lineLimit(1).truncationMode(.tail)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(vaultNameHovered ? .secondary : .tertiary)
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(vaultNameHovered ? .primary : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(vaultNameHovered ? Color.primary.opacity(0.07) : .clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Switch Vault (⇧⌘O)")
            .accessibilityLabel("Switch vault")
            .onHover { vaultNameHovered = $0 }
            .pointerStyle(.link)
            .animation(.easeOut(duration: 0.12), value: vaultNameHovered)
            .buttonStyle(.plain)
            .help("Switch Vault (⇧⌘O)")
            .accessibilityLabel("Switch vault")
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 78)

            HStack(spacing: 6) {
                Spacer(minLength: 0)
                // Filter lives behind an icon (Finder-style), not a always-visible
                // field: a mounted TextField steals first-responder at launch and
                // fights the palettes for focus.
                Button {
                    if showFilter { clearFilter() } else { ui.sidebarFilterFocus &+= 1 }
                } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.borderless).help("Filter Files (⇧⌘K)").accessibilityLabel("Filter files")
                    .foregroundStyle(showFilter ? settings.selectionTint : Color.secondary)
                    .disabled(vault.vaultURL == nil)
                Button { vault.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Reload Vault (⇧⌘R)").accessibilityLabel("Reload vault")
                    .disabled(vault.vaultURL == nil)
                toggleButton            // filter + reload + toggle pinned to the trailing edge
            }
            .padding(.trailing, 10)
        }
        // Native title-bar double-click (zoom/minimize per System Settings) —
        // the hidden real title bar means AppKit never sees it.
        //
        // Detected by timestamp rather than `.onTapGesture(count: 2)`: a count-2
        // recognizer holds *every* click in this area for the double-click
        // interval to disambiguate, which made the vault-name button feel like it
        // lagged half a second before opening. See ARCHITECTURE.md, trap 1.
        .onTapGesture {
            let now = Date()
            if now.timeIntervalSince(lastTitleClick) < NSEvent.doubleClickInterval {
                lastTitleClick = .distantPast
                titleBarDoubleClicked()
            } else {
                lastTitleClick = now
            }
        }
    }

    private var contentTitleArea: some View {
        HStack(spacing: 8) {
            if !showSidebar { toggleButton }   // toggle relocates here when the sidebar is hidden
            historyChevrons
            TabBarView().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)   // tabs + trailing "+"
            actionButtons
        }
        .padding(.leading, showSidebar ? 12 : 78)   // clear traffic lights only when sidebar is off
        .padding(.trailing, 12)
    }

    /// ‹ › back/forward buttons next to the tabs; disabled when their stack is empty.
    private var historyChevrons: some View {
        HStack(spacing: 2) {
            Button { vault.goBack() } label: { Image(systemName: "chevron.left") }
                .help("Back (⌘[)").accessibilityLabel("Back").disabled(!vault.canGoBack)
            Button { vault.goForward() } label: { Image(systemName: "chevron.right") }
                .help("Forward (⌘])").accessibilityLabel("Forward").disabled(!vault.canGoForward)
        }
        .buttonStyle(.borderless)
        .font(.system(size: 13, weight: .semibold))
    }

    /// Sidebar/backdrop fill: native vibrancy in the Frosted theme, otherwise the
    /// theme's sidebar tint (or clear → the window color shows through).
    @ViewBuilder private var sidebarBackdrop: some View {
        if settings.usesVibrantSidebar {
            VisualEffectView(material: .sidebar, blending: .behindWindow)
        } else {
            settings.sidebarBackground ?? Color.clear
        }
    }

    private var toggleButton: some View {
        Button { withAnimation(.smooth(duration: 0.2)) { showSidebar.toggle() } } label: {
            Image(systemName: "sidebar.leading")
        }
        .buttonStyle(.borderless)
        .keyboardShortcut("s", modifiers: [.command, .control])   // macOS-standard Show/Hide Sidebar
        .help("Toggle Sidebar (⌃⌘S)").accessibilityLabel("Toggle sidebar")
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button { ui.showTags = true } label: { Image(systemName: "number") }
                .buttonStyle(.borderless).imageScale(.large)
                .help("Browse Tags").accessibilityLabel("Browse tags").disabled(vault.vaultURL == nil)
            modeSwitch
        }
    }

    /// Read | Write mode switch as two fixed segments, never a morphing toggle
    /// icon: the highlighted segment *is* the current mode, the other one is the
    /// available action. (A single swapping icon always shows the mode you're not
    /// in, which half of users read as the current state — the ambiguity this
    /// replaced.)
    private var modeSwitch: some View {
        HStack(spacing: 2) {
            modeSegment("book", mode: .read, help: "Reading mode (⌘E toggles, Esc returns)")
            modeSegment("pencil.line", mode: .edit, help: "Writing mode (⌘E toggles)")
        }
        .padding(2)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .disabled(vault.selection == nil)
        .opacity(vault.selection == nil ? 0.4 : 1)
    }

    private func modeSegment(_ icon: String, mode: EditorMode, help: String) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.2)) { ui.mode = mode }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(ui.mode == mode ? settings.selectionFill : .clear,
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .foregroundStyle(ui.mode == mode ? settings.selectionTint : Color.secondary)
        .help(help)
        .accessibilityLabel(mode == .read ? "Reading mode" : "Writing mode")
        .accessibilityAddTraits(ui.mode == mode ? [.isSelected] : [])
    }

    private var resizeDivider: some View {
        Divider()
            .background(Color(nsColor: .windowBackgroundColor))   // opaque: the Frosted window is see-through
            .overlay(
                // AppKit-backed: a SwiftUI DragGesture here loses to the
                // movable-by-background window and drags the whole window.
                SidebarResizeHandle(
                    onDrag: { delta in
                        if dragStartWidth == nil { dragStartWidth = sidebarWidth }
                        sidebarWidth = min(max((dragStartWidth ?? sidebarWidth) + delta, 200), 480)
                    },
                    onEnd: { dragStartWidth = nil })
                    .frame(width: 8)
            )
    }

    // MARK: Sidebar

    @ViewBuilder
    private var sidebar: some View {
        if vault.vaultURL == nil {
            ContentUnavailableView {
                Label("No vault open", systemImage: "folder.badge.questionmark")
            } description: {
                Text("Open a folder of Markdown notes to get started.")
            } actions: {
                Button("Open Vault…") { ui.showVaultSwitcher = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            VStack(spacing: 0) {
                if showFilter {
                    filterField
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                fileTree
            }
            .background(sidebarBackdrop)
            .onAppear { restoreExpansion() }        // initial launch (onChange won't fire)
            .onChange(of: vault.vaultURL) { clearFilter(); restoreExpansion() }
        }
    }

    /// Slim, calm filter field pinned above the tree. Substring-matches file names.
    private var filterField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
            TextField("Filter", text: $filter)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($filterFocused)
                .autocorrectionDisabled(true)
                .onExitCommand { clearFilter() }
            if !filter.isEmpty {
                Button { clearFilter() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear filter")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 4)
    }

    // A plain ScrollView + LazyVStack (not List): SwiftUI's List draws an
    // uncustomizable blue context-menu highlight ring around the right-clicked row.
    // We already provide our own selection/hover backgrounds and row chrome, so
    // nothing is lost by dropping List.
    private var fileTree: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(visibleItems) { item in
                        SidebarRow(item: item, expanded: $expandedDirs,
                                   selected: vault.selection == item.node.id,
                                   forceExpanded: filterActive && item.node.isDirectory,
                                   // ⌘-click opens in a new tab (Obsidian/browser convention).
                                   onSelect: { vault.select(item.node.id, inNewTab: cmdHeld) },
                                   onOpenOwnTab: { vault.openInOwnTab(item.node.id) },
                                   onToggle: { toggleDir(item.node.id) },
                                   startRename: startRename)
                            .id(item.node.id)          // reveal target for scroll-to
                            .padding(.horizontal, 6)
                    }
                }
                .padding(.vertical, 6)
            }
            .background(ThinScrollers())   // thin, auto-hiding overlay scroller
            .onChange(of: vault.selection) { revealSelection(proxy) }
            // Folder links in a note reveal the folder here instead of Finder.
            .onChange(of: vault.sidebarRevealRequest) { revealRequestedFolder(proxy) }
            .onAppear { revealRequestedFolder(proxy) }   // sidebar may mount after the request
            .overlay {
                if vault.tree.isEmpty {
                    ContentUnavailableView("No notes", systemImage: "doc.text",
                        description: Text("No Markdown files found in this folder."))
                } else if filterActive && visibleItems.isEmpty {
                    ContentUnavailableView("No matches", systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("No file names match “\(filter)”."))
                }
            }
        }
    }

    /// Clear and fully collapse the filter (Esc, the ⨯ button, or the magnifier
    /// toggling off) — dismissing it always returns the field to hidden, so the
    /// sidebar never keeps an idle first-responder around.
    private func clearFilter() {
        filter = ""
        filterFocused = false
        withAnimation(.smooth(duration: 0.2)) { showFilter = false }
    }

    // MARK: Tree flattening (respecting expansion)

    private var visibleItems: [SidebarItem] {
        // The filter matches word-wise: every whitespace-separated word must appear
        // somewhere in the file name (any order), so "migration strategy" finds
        // "migration-strategy.md". Kept substring-per-word (not fuzzy) on purpose —
        // a tree filter should narrow decisively, not keep loose subsequence hits.
        let words = filter.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        var rows: [SidebarItem] = []
        if words.isEmpty {
            func walk(_ nodes: [VaultNode], _ depth: Int) {
                for n in nodes {
                    rows.append(SidebarItem(node: n, depth: depth))
                    if n.isDirectory, expandedDirs.contains(n.id), let c = n.children { walk(c, depth + 1) }
                }
            }
            walk(vault.tree, 0)
        } else {
            appendFiltered(vault.tree, depth: 0, words: words, into: &rows)
        }
        return rows
    }

    /// Filtered flattening: keep files whose name contains every filter word, plus
    /// every ancestor folder on the path to them (shown regardless of expansion).
    @discardableResult
    private func appendFiltered(_ nodes: [VaultNode], depth: Int, words: [String],
                                into rows: inout [SidebarItem]) -> Bool {
        var any = false
        for n in nodes {
            if n.isDirectory, let c = n.children {
                var childRows: [SidebarItem] = []
                if appendFiltered(c, depth: depth + 1, words: words, into: &childRows) {
                    rows.append(SidebarItem(node: n, depth: depth))
                    rows.append(contentsOf: childRows)
                    any = true
                }
            } else if !n.isDirectory {
                let name = n.name.lowercased()
                if words.allSatisfy({ name.contains($0) }) {
                    rows.append(SidebarItem(node: n, depth: depth))
                    any = true
                }
            }
        }
        return any
    }

    private func toggleDir(_ id: URL) {
        if expandedDirs.contains(id) { expandedDirs.remove(id) } else { expandedDirs.insert(id) }
        persistExpansion()
    }

    /// Whether ⌘ is down during the current event (used to route clicks to a new tab).
    private var cmdHeld: Bool { NSApp.currentEvent?.modifierFlags.contains(.command) ?? false }

    // MARK: Reveal + persist expansion

    /// Expand every ancestor folder of the current selection and scroll to its row.
    /// Ancestors are expanded even while a filter is active — otherwise clearing
    /// the filter would leave the just-selected note hidden in a collapsed folder;
    /// only the scroll is skipped (the filtered list is already flat).
    private func revealSelection(_ proxy: ScrollViewProxy) {
        guard let sel = vault.selection else { return }
        for dir in ancestors(of: sel) { expandedDirs.insert(dir) }
        persistExpansion()
        guard !filterActive else { return }
        // Scroll after the newly-expanded rows exist in the lazy stack. Not
        // animated: this fires on every tab switch, and an animated sidebar
        // scroll compounding with the content swap read as switch lag.
        DispatchQueue.main.async { proxy.scrollTo(sel, anchor: .center) }
    }

    /// Reveal a folder a Markdown link pointed at: expand its ancestors and the
    /// folder itself, scroll its row into view, and consume the request. Split
    /// from `revealSelection` because the target is a directory, not a note.
    private func revealRequestedFolder(_ proxy: ScrollViewProxy) {
        guard let target = vault.sidebarRevealRequest else { return }
        vault.sidebarRevealRequest = nil
        clearFilter()                                    // the filtered flat list hides folders
        for dir in ancestors(of: target) { expandedDirs.insert(dir) }
        expandedDirs.insert(target)                      // show its contents, not just its row
        persistExpansion()
        DispatchQueue.main.async { proxy.scrollTo(target, anchor: .center) }
    }

    /// Directory node IDs on the path from a tree root down to `target` — taken from
    /// the actual tree nodes so they match the URLs `expandedDirs` is tested against.
    private func ancestors(of target: URL) -> [URL] {
        var result: [URL] = []
        func walk(_ nodes: [VaultNode]) {
            for n in nodes where n.isDirectory {
                if target.path.hasPrefix(n.id.path + "/") {
                    result.append(n.id)
                    if let c = n.children { walk(c) }
                    return
                }
            }
        }
        walk(vault.tree)
        return result
    }

    private func allDirNodeIDs(_ nodes: [VaultNode]) -> [URL] {
        var out: [URL] = []
        for n in nodes where n.isDirectory {
            out.append(n.id)
            if let c = n.children { out.append(contentsOf: allDirNodeIDs(c)) }
        }
        return out
    }

    private func restoreExpansion() {
        guard let root = vault.vaultURL else { expandedDirs = []; return }
        let saved = Set((UserDefaults.standard.dictionary(forKey: expandedKey) as? [String: [String]])?[root.path] ?? [])
        // Match saved paths back to actual tree-node URLs so Set membership (which
        // the flattener tests with node.id) lines up exactly.
        expandedDirs = Set(allDirNodeIDs(vault.tree).filter { saved.contains($0.path) })
    }

    private func persistExpansion() {
        guard let root = vault.vaultURL else { return }
        var all = UserDefaults.standard.dictionary(forKey: expandedKey) as? [String: [String]] ?? [:]
        all[root.path] = expandedDirs.map(\.path)
        UserDefaults.standard.set(all, forKey: expandedKey)
    }

    // MARK: Rename

    private var renamePresented: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    private func startRename(_ url: URL) {
        renameText = url.lastPathComponent
        renameTarget = url
    }
}
