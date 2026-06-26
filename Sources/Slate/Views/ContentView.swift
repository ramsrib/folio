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

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
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
        .background(WindowConfigurator(background: settings.nsWindowBackground))
        .overlay { paletteOverlay }
        .animation(.easeOut(duration: 0.14), value: paletteShown)
        .onChange(of: vault.selection) {
            ui.mode = vault.openInEditMode ? .edit : .read
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

    private var paletteShown: Bool {
        ui.showCommandPalette || ui.showQuickSwitcher || ui.showTags || ui.showShortcuts
    }

    @ViewBuilder
    private var paletteOverlay: some View {
        if paletteShown {
            ZStack {
                Color.black.opacity(0.001)        // invisible click-catcher
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { dismissPalettes() }
                Group {
                    if ui.showCommandPalette { CommandPaletteView() }
                    else if ui.showQuickSwitcher { QuickSwitcherView() }
                    else if ui.showTags { TagsView() }
                    else if ui.showShortcuts { ShortcutsView() }
                }
            }
            .transition(.opacity)
        }
    }

    private func dismissPalettes() {
        ui.showCommandPalette = false
        ui.showQuickSwitcher = false
        ui.showTags = false
        ui.showShortcuts = false
    }

    // MARK: Title bar — split into a sidebar title area + a content title area
    // (aligned with the columns below), filling the title-bar strip via
    // fullSizeContentView. Tabs live only in the content area and scroll.

    private var titleBar: some View {
        HStack(spacing: 0) {
            if showSidebar {
                sidebarTitleArea
                    .frame(width: sidebarWidth, height: 42)
                    .background(settings.sidebarBackground ?? Color(nsColor: .windowBackgroundColor))
                Divider()
            }
            contentTitleArea
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(settings.topBarBackground)
        }
        .frame(height: 42)
    }

    private var sidebarTitleArea: some View {
        ZStack {
            // Vault title centered in the sidebar column, growing symmetrically on
            // both sides. The 78pt horizontal clearance keeps it clear of the
            // traffic lights (left) and the trailing controls (right) when long.
            Text(vault.vaultURL?.lastPathComponent ?? "Slate")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 78)

            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Button { vault.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Reload Vault (⇧⌘R)").accessibilityLabel("Reload vault")
                    .disabled(vault.vaultURL == nil)
                toggleButton            // reload + toggle pinned to the trailing edge
            }
            .padding(.trailing, 10)
        }
    }

    private var contentTitleArea: some View {
        HStack(spacing: 8) {
            if !showSidebar { toggleButton }   // toggle relocates here when the sidebar is hidden
            TabBarView().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)   // tabs + trailing "+"
            actionButtons
        }
        .padding(.leading, showSidebar ? 12 : 78)   // clear traffic lights only when sidebar is off
        .padding(.trailing, 12)
    }

    private var toggleButton: some View {
        Button { withAnimation(.smooth(duration: 0.2)) { showSidebar.toggle() } } label: {
            Image(systemName: "sidebar.leading")
        }
        .buttonStyle(.borderless).help("Toggle Sidebar").accessibilityLabel("Toggle sidebar")
    }

    private var actionButtons: some View {
        HStack(spacing: 6) {
            Button { ui.showTags = true } label: { Image(systemName: "number") }
                .help("Browse Tags").accessibilityLabel("Browse tags").disabled(vault.vaultURL == nil)
            Button {
                withAnimation(.smooth(duration: 0.2)) { ui.mode = ui.mode == .read ? .edit : .read }
            } label: { Image(systemName: ui.mode == .read ? "pencil" : "eye") }
                .help(ui.mode == .read ? "Writing Mode (⌘E)" : "Reading Mode (⌘E)")
                .accessibilityLabel(ui.mode == .read ? "Switch to writing" : "Switch to reading")
                .disabled(vault.selection == nil)
        }
        .buttonStyle(.borderless)
        .imageScale(.large)
    }

    private var resizeDivider: some View {
        Divider()
            .overlay(
                Color.clear.frame(width: 8).contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(DragGesture()
                        .onChanged { v in
                            if dragStartWidth == nil { dragStartWidth = sidebarWidth }
                            sidebarWidth = min(max((dragStartWidth ?? sidebarWidth) + v.translation.width, 200), 480)
                        }
                        .onEnded { _ in dragStartWidth = nil })
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
                Button("Open Vault…") { vault.pickVault() }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            List {
                ForEach(visibleItems) { item in
                    SidebarRow(item: item, expanded: $expandedDirs,
                               selected: vault.selection == item.node.id,
                               onSelect: { vault.select(item.node.id) },
                               onToggle: { toggleDir(item.node.id) },
                               startRename: startRename)
                        .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.sidebar)
            .environment(\.defaultMinListRowHeight, 26)
            .scrollContentBackground(settings.sidebarBackground == nil ? .automatic : .hidden)
            .background(settings.sidebarBackground ?? Color.clear)
            .onChange(of: vault.vaultURL) { expandedDirs.removeAll() }
            .overlay {
                if vault.tree.isEmpty {
                    ContentUnavailableView("No notes", systemImage: "doc.text",
                        description: Text("No Markdown files found in this folder."))
                }
            }
        }
    }

    // MARK: Tree flattening (respecting expansion)

    private var visibleItems: [SidebarItem] {
        var rows: [SidebarItem] = []
        func walk(_ nodes: [VaultNode], _ depth: Int) {
            for n in nodes {
                rows.append(SidebarItem(node: n, depth: depth))
                if n.isDirectory, expandedDirs.contains(n.id), let c = n.children { walk(c, depth + 1) }
            }
        }
        walk(vault.tree, 0)
        return rows
    }

    private func toggleDir(_ id: URL) {
        if expandedDirs.contains(id) { expandedDirs.remove(id) } else { expandedDirs.insert(id) }
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
