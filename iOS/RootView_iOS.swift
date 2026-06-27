import SwiftUI
import UniformTypeIdentifiers

/// iOS root: a folder browser for an opened vault (iCloud Drive / Files), pushing
/// to a note screen. Vaults are opened via the system folder picker and kept
/// across launches with a security-scoped bookmark (handled in VaultStore).
struct RootView_iOS: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var settings: AppSettings
    @State private var path: [MarkdownFile] = []
    @State private var showOpen = false
    @State private var showTags = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if vault.vaultURL == nil {
                    EmptyVaultView { showOpen = true }
                } else {
                    VaultBrowser()
                }
            }
            .navigationTitle(vault.vaultURL?.lastPathComponent ?? "Slate")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: MarkdownFile.self) { NoteScreen(file: $0) }
            .toolbar {
                if vault.vaultURL != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showTags = true } label: { Image(systemName: "number") }
                            .accessibilityLabel("Browse tags")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "textformat.size") }
                        .accessibilityLabel("Appearance")
                    Button { showOpen = true } label: { Image(systemName: "folder") }
                        .accessibilityLabel("Open vault")
                }
            }
        }
        .fileImporter(isPresented: $showOpen, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                _ = url.startAccessingSecurityScopedResource()
                path.removeAll()
                vault.setVault(url)
            }
        }
        .sheet(isPresented: $showTags) {
            TagsScreen { file in showTags = false; path.append(file) }
        }
        .sheet(isPresented: $showSettings) { SettingsScreen() }
    }
}

private struct EmptyVaultView: View {
    let onOpen: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label("No vault open", systemImage: "folder.badge.plus")
        } description: {
            Text("Open a folder of Markdown notes from iCloud Drive or Files.")
        } actions: {
            Button("Open Vault…", action: onOpen).buttonStyle(.borderedProminent)
        }
    }
}

/// The vault's folder tree as a collapsible list, with name search across all notes.
private struct VaultBrowser: View {
    @EnvironmentObject private var vault: VaultStore
    @State private var expanded: Set<URL> = []
    @State private var query = ""

    var body: some View {
        List {
            if query.isEmpty {
                ForEach(flattened(vault.tree, depth: 0), id: \.node.id) { row($0) }
            } else {
                ForEach(searchResults, id: \.id) { file in
                    NavigationLink(value: file) {
                        Label(file.name, systemImage: "doc.text")
                    }
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search notes")
        .refreshable { vault.refresh() }
        .overlay {
            if vault.tree.isEmpty {
                ContentUnavailableView("No notes", systemImage: "doc.text",
                    description: Text("No Markdown files found in this folder."))
            }
        }
    }

    private struct Flat { let node: VaultNode; let depth: Int }

    private func flattened(_ nodes: [VaultNode], depth: Int) -> [Flat] {
        var out: [Flat] = []
        for n in nodes {
            out.append(Flat(node: n, depth: depth))
            if n.isDirectory, expanded.contains(n.id), let children = n.children {
                out.append(contentsOf: flattened(children, depth: depth + 1))
            }
        }
        return out
    }

    private var searchResults: [MarkdownFile] {
        let q = query.lowercased()
        return vault.files.filter { $0.name.lowercased().contains(q) }
    }

    @ViewBuilder
    private func row(_ item: Flat) -> some View {
        let n = item.node
        let indent = CGFloat(item.depth) * 14
        if n.isDirectory {
            Button {
                if expanded.contains(n.id) { expanded.remove(n.id) } else { expanded.insert(n.id) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded.contains(n.id) ? "chevron.down" : "chevron.right")
                        .font(.caption2).foregroundStyle(.secondary).frame(width: 12)
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    Text(n.name).foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.leading, indent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else if let root = vault.vaultURL {
            NavigationLink(value: MarkdownFile(url: n.id, vaultRoot: root)) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text").foregroundStyle(.secondary)
                    Text(n.name)
                }
                .padding(.leading, indent + 18)
            }
        }
    }
}
