import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var settings: AppSettings
    @State private var renameTarget: URL?
    @State private var renameText = ""
    @State private var expandedDirs: Set<URL> = []
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 290, max: 460)
                .toolbar(removing: .sidebarToggle)
                .toolbar { sidebarToolbar }
        } detail: {
            EditorPane()
        }
        .navigationTitle("")
        .background(WindowConfigurator(background: settings.nsWindowBackground))
        .toolbar { toolbarContent }
        .onChange(of: vault.selection) {
            ui.mode = vault.openInEditMode ? .edit : .read
            vault.openInEditMode = false
        }
        .sheet(isPresented: $ui.showQuickSwitcher) { QuickSwitcherView() }
        .sheet(isPresented: $ui.showCommandPalette) { CommandPaletteView() }
        .alert("Rename Note", isPresented: renamePresented) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Rename") {
                if let t = renameTarget { vault.rename(t, to: renameText) }
                renameTarget = nil
            }
        }
    }

    // MARK: Title-bar toolbar (vault name + tabs + actions)

    /// Lives in the sidebar's region of the title bar: vault name + sidebar toggle.
    @ToolbarContentBuilder
    private var sidebarToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Text(vault.vaultURL?.lastPathComponent ?? "Slate")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
            Button {
                withAnimation(.smooth(duration: 0.2)) {
                    columns = columns == .detailOnly ? .all : .detailOnly
                }
            } label: { Image(systemName: "sidebar.leading") }
            .help("Toggle sidebar")
        }
    }

    // MARK: Main title bar (tabs + actions)

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            if !vault.openTabs.isEmpty {
                TabBarView().frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { vault.newNote() } label: { Image(systemName: "square.and.pencil") }
                .help("New note").disabled(vault.vaultURL == nil)
            Button { vault.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .help("Reload vault").disabled(vault.vaultURL == nil)
            Button {
                withAnimation(.smooth(duration: 0.2)) { ui.mode = ui.mode == .read ? .edit : .read }
            } label: { Image(systemName: ui.mode == .read ? "pencil" : "eye") }
                .help(ui.mode == .read ? "Edit" : "Reading mode").disabled(vault.selection == nil)
        }
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
            List(selection: Binding(get: { vault.selection }, set: { vault.select($0) })) {
                ForEach(vault.tree) { node in
                    FileTreeRow(node: node, expanded: $expandedDirs, startRename: startRename)
                }
            }
            .listStyle(.sidebar)
            .onChange(of: vault.vaultURL) { expandedDirs.removeAll() }
            .overlay {
                if vault.tree.isEmpty {
                    ContentUnavailableView("No notes", systemImage: "doc.text",
                        description: Text("No Markdown files found in this folder."))
                }
            }
        }
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
