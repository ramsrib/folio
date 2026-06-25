import Foundation
import SwiftUI
import AppKit

/// Owns the open vault (a folder of Markdown files), the folder tree, and the
/// currently-open note's text. The on-disk file is always the source of truth;
/// edits are written back (debounced) as plain UTF-8, byte-for-byte lossless.
@MainActor
final class VaultStore: ObservableObject {
    @Published var vaultURL: URL?
    @Published private(set) var tree: [VaultNode] = []
    @Published private(set) var files: [MarkdownFile] = []     // flat, for lookup
    @Published var selection: MarkdownFile.ID?
    @Published var content: String = ""
    @Published private(set) var savedAt: Date?

    private let vaultPathKey = "slate.vaultPath"
    private let mdExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]
    private var loadedURL: URL?
    private var saveTask: Task<Void, Never>?
    private var watcher: VaultWatcher?

    init() { restoreVault() }

    // MARK: - Vault selection

    func pickVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Vault"
        panel.message = "Choose a folder of Markdown notes"
        if panel.runModal() == .OK, let url = panel.url { setVault(url) }
    }

    func setVault(_ url: URL) {
        flushSave()
        vaultURL = url
        UserDefaults.standard.set(url.path, forKey: vaultPathKey)
        selection = nil
        content = ""
        loadedURL = nil
        refresh()
        startWatching()
    }

    private func restoreVault() {
        guard let path = UserDefaults.standard.string(forKey: vaultPathKey) else { return }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        vaultURL = url
        refresh()
        startWatching()
    }

    private func startWatching() {
        watcher = nil
        guard let root = vaultURL else { return }
        watcher = VaultWatcher(path: root.path) { [weak self] in self?.refresh() }
    }

    // MARK: - File listing (tree + flat)

    func refresh() {
        guard let root = vaultURL else { tree = []; files = []; return }
        var flat: [MarkdownFile] = []
        tree = buildTree(root, root: root, flat: &flat)
        files = flat.sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
    }

    private func buildTree(_ dir: URL, root: URL, flat: inout [MarkdownFile]) -> [VaultNode] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        else { return [] }

        var nodes: [VaultNode] = []
        for url in entries {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                let children = buildTree(url, root: root, flat: &flat)
                if !children.isEmpty {   // prune folders with no Markdown inside
                    nodes.append(VaultNode(id: url, name: url.lastPathComponent,
                                           isDirectory: true, children: children))
                }
            } else if mdExtensions.contains(url.pathExtension.lowercased()) {
                let file = MarkdownFile(url: url, vaultRoot: root)
                flat.append(file)
                nodes.append(VaultNode(id: url, name: file.name, isDirectory: false, children: nil))
            }
        }
        return nodes.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory && !b.isDirectory }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    // MARK: - Open / edit / save

    func select(_ id: MarkdownFile.ID?) {
        flushSave()
        // Ignore selection of directories (folders aren't notes).
        guard let id, files.contains(where: { $0.id == id }) else {
            selection = nil; content = ""; loadedURL = nil; return
        }
        selection = id
        content = (try? String(contentsOf: id, encoding: .utf8)) ?? ""
        loadedURL = id
        savedAt = nil
    }

    /// Debounced autosave — called on every edit.
    func scheduleSave() {
        guard loadedURL != nil else { return }
        saveTask?.cancel()
        let url = loadedURL
        let text = content
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            if Task.isCancelled { return }
            guard let url else { return }
            try? text.write(to: url, atomically: true, encoding: .utf8)
            self?.savedAt = Date()
        }
    }

    /// Flush any pending save immediately (on selection / vault change).
    func flushSave() {
        saveTask?.cancel()
        saveTask = nil
        guard let url = loadedURL else { return }
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - CRUD

    /// Create a new note. Placed in the folder of the current selection, else the root.
    func newNote() {
        guard let root = vaultURL else { return }
        let dir: URL = {
            if let sel = selection { return sel.deletingLastPathComponent() }
            return root
        }()
        let fm = FileManager.default
        var name = "Untitled.md"
        var n = 1
        while fm.fileExists(atPath: dir.appendingPathComponent(name).path) {
            n += 1; name = "Untitled \(n).md"
        }
        let url = dir.appendingPathComponent(name)
        try? "".write(to: url, atomically: true, encoding: .utf8)
        refresh()
        select(url)
    }

    func rename(_ id: URL, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var final = trimmed
        if !mdExtensions.contains((final as NSString).pathExtension.lowercased()) { final += ".md" }
        let dest = id.deletingLastPathComponent().appendingPathComponent(final)
        guard dest != id else { return }
        do {
            try FileManager.default.moveItem(at: id, to: dest)
            if selection == id { selection = dest; loadedURL = dest }
            refresh()
        } catch { NSSound.beep() }
    }

    func delete(_ id: URL) {
        if loadedURL == id { saveTask?.cancel(); saveTask = nil; loadedURL = nil }
        try? FileManager.default.trashItem(at: id, resultingItemURL: nil)
        if selection == id { selection = nil; content = "" }
        refresh()
    }
}
