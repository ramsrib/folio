import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var ui: UIState
    @State private var renameTarget: URL?
    @State private var renameText = ""

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 290, max: 460)
        } detail: {
            EditorPane()
        }
        .navigationTitle(vault.vaultURL?.lastPathComponent ?? "Slate")
        .toolbar { toolbarContent }
        .inspector(isPresented: $ui.showInspector) {
            InspectorView()
                .inspectorColumnWidth(min: 220, ideal: 280, max: 420)
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
                OutlineGroup(vault.tree, children: \.children) { node in
                    row(for: node)
                }
            }
            .overlay {
                if vault.tree.isEmpty {
                    ContentUnavailableView("No notes", systemImage: "doc.text",
                        description: Text("No Markdown files found in this folder."))
                }
            }
        }
    }

    @ViewBuilder
    private func row(for node: VaultNode) -> some View {
        if node.isDirectory {
            Label(node.name, systemImage: "folder")
                .foregroundStyle(.secondary)
                .selectionDisabled()
        } else {
            Label(node.name, systemImage: "doc.text")
                .lineLimit(1)
                .tag(node.id)
                .contextMenu {
                    Button("Rename…") { startRename(node.id) }
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([node.id])
                    }
                    Divider()
                    Button("Move to Trash", role: .destructive) { vault.delete(node.id) }
                }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { vault.newNote() } label: { Image(systemName: "square.and.pencil") }
                .help("New note")
                .disabled(vault.vaultURL == nil)
            Button { vault.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .help("Reload vault")
                .disabled(vault.vaultURL == nil)
            Button { ui.showInspector.toggle() } label: { Image(systemName: "sidebar.right") }
                .help("Toggle inspector")
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
