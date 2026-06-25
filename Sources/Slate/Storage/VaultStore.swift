import Foundation
import SwiftUI
import AppKit

/// Owns the open vault (a folder of Markdown files), the folder tree, the link
/// index, and the currently-open note's text. The on-disk file is always the
/// source of truth; edits are written back (debounced) as plain UTF-8, lossless.
@MainActor
final class VaultStore: ObservableObject {
    @Published var vaultURL: URL?
    @Published private(set) var tree: [VaultNode] = []
    @Published private(set) var files: [MarkdownFile] = []     // flat, for lookup
    @Published var selection: MarkdownFile.ID?
    @Published var content: String = ""
    @Published private(set) var savedAt: Date?
    @Published private(set) var outline: [OutlineItem] = []
    @Published private(set) var backlinks: [Backlink] = []
    @Published var scrollRequest: Int?   // character offset for the editor to scroll to

    var allNoteNames: [String] { files.map(\.name) }

    private let vaultPathKey = "slate.vaultPath"
    private let mdExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]
    private var loadedURL: URL?
    private var saveTask: Task<Void, Never>?
    private var watcher: VaultWatcher?

    // Link index
    private var noteByName: [String: [URL]] = [:]     // lowercased basename -> urls
    private var backlinkMap: [URL: [Backlink]] = [:]  // target note -> inbound links

    private static let wikiRegex = try! NSRegularExpression(pattern: "\\[\\[([^\\]]+)\\]\\]")
    private static let headingRegex = try! NSRegularExpression(
        pattern: "^(#{1,6})\\s+(.+)$", options: [.anchorsMatchLines])

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
        selection = nil; content = ""; loadedURL = nil
        outline = []; backlinks = []
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

    // MARK: - File listing (tree + flat) + link index

    func refresh() {
        guard let root = vaultURL else { tree = []; files = []; return }
        var flat: [MarkdownFile] = []
        tree = buildTree(root, root: root, flat: &flat)
        files = flat.sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
        rebuildLinkIndex()
        updateBacklinks()
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
                if !children.isEmpty {
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

    private func rebuildLinkIndex() {
        noteByName = [:]
        backlinkMap = [:]
        for f in files { noteByName[f.name.lowercased(), default: []].append(f.url) }
        for f in files {
            guard let text = try? String(contentsOf: f.url, encoding: .utf8) else { continue }
            let ns = text as NSString
            Self.wikiRegex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                guard let m else { return }
                let inner = ns.substring(with: m.range(at: 1))
                guard let dest = resolve(inner) else { return }   // unresolved → no backlink
                let line = ns.substring(with: ns.lineRange(for: m.range))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                backlinkMap[dest, default: []].append(
                    Backlink(source: f.url, sourceName: f.name, context: line))
            }
        }
    }

    // MARK: - Link resolution

    private func normalizeTarget(_ s: String) -> String {
        var t = s
        if let bar = t.firstIndex(of: "|") { t = String(t[..<bar]) }
        if let hash = t.firstIndex(of: "#") { t = String(t[..<hash]) }
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// Resolve a wikilink target (basename, path, or with alias/heading) to a file.
    func resolve(_ target: String) -> URL? {
        let base = normalizeTarget(target)
        guard !base.isEmpty else { return nil }
        if base.contains("/"), let root = vaultURL {
            let path = base.hasSuffix(".md") ? base : base + ".md"
            let candidate = root.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        let key = ((base as NSString).lastPathComponent as NSString)
            .deletingPathExtension.lowercased()
        return noteByName[key]?.first
    }

    // MARK: - Open / edit / save

    func select(_ id: MarkdownFile.ID?) {
        flushSave()
        guard let id, files.contains(where: { $0.id == id }) else {
            selection = nil; content = ""; loadedURL = nil
            outline = []; backlinks = []; return
        }
        selection = id
        content = (try? String(contentsOf: id, encoding: .utf8)) ?? ""
        loadedURL = id
        savedAt = nil
        updateOutline()
        updateBacklinks()
    }

    /// Open a wikilink target — navigate if it resolves, else create the note.
    func openWikilink(_ target: String) {
        if let dest = resolve(target) { select(dest); return }
        guard let root = vaultURL else { return }
        let base = normalizeTarget(target)
        guard !base.isEmpty else { return }
        let dir = selection?.deletingLastPathComponent() ?? root
        let fileName = ((base.hasSuffix(".md") ? base : base + ".md") as NSString).lastPathComponent
        let url = dir.appendingPathComponent(fileName)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? "# \(base)\n".write(to: url, atomically: true, encoding: .utf8)
        }
        refresh()
        select(url)
    }

    /// Called by the editor on every edit.
    func contentEdited() {
        updateOutline()
        scheduleSave()
    }

    private func updateOutline() {
        let ns = content as NSString
        var items: [OutlineItem] = []
        Self.headingRegex.enumerateMatches(in: content, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            items.append(OutlineItem(
                level: m.range(at: 1).length,
                title: ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces),
                charIndex: m.range.location))
        }
        outline = items
    }

    private func updateBacklinks() {
        backlinks = selection.flatMap { backlinkMap[$0] } ?? []
    }

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

    func flushSave() {
        saveTask?.cancel(); saveTask = nil
        guard let url = loadedURL else { return }
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - CRUD

    func newNote() {
        guard let root = vaultURL else { return }
        let dir = selection?.deletingLastPathComponent() ?? root
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
        var fileName = trimmed
        if !mdExtensions.contains((fileName as NSString).pathExtension.lowercased()) { fileName += ".md" }
        let dest = id.deletingLastPathComponent().appendingPathComponent(fileName)
        guard dest != id else { return }
        do {
            try FileManager.default.moveItem(at: id, to: dest)
            let oldBase = (id.lastPathComponent as NSString).deletingPathExtension
            let newBase = (dest.lastPathComponent as NSString).deletingPathExtension
            let changed = updateLinks(oldBase: oldBase, newBase: newBase)
            if selection == id { selection = dest; loadedURL = dest }
            if let open = loadedURL, changed.contains(open) {
                content = (try? String(contentsOf: open, encoding: .utf8)) ?? content
            }
            refresh()
            updateOutline()
        } catch { NSSound.beep() }
    }

    /// Rewrite `[[oldBase]]`, `[[oldBase|…]]`, `[[oldBase#…]]` to use `newBase`
    /// across the whole vault. Returns the set of files actually changed.
    @discardableResult
    private func updateLinks(oldBase: String, newBase: String) -> Set<URL> {
        guard oldBase.caseInsensitiveCompare(newBase) != .orderedSame else { return [] }
        let pattern = "(\\[\\[)" + NSRegularExpression.escapedPattern(for: oldBase) + "(\\||#|\\]\\])"
        guard let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let template = "$1" + NSRegularExpression.escapedTemplate(for: newBase) + "$2"
        var changed: Set<URL> = []
        for f in files {
            guard let text = try? String(contentsOf: f.url, encoding: .utf8) else { continue }
            let range = NSRange(location: 0, length: (text as NSString).length)
            guard rx.firstMatch(in: text, range: range) != nil else { continue }
            let updated = rx.stringByReplacingMatches(in: text, range: range, withTemplate: template)
            if updated != text {
                try? updated.write(to: f.url, atomically: true, encoding: .utf8)
                changed.insert(f.url)
            }
        }
        return changed
    }

    func delete(_ id: URL) {
        if loadedURL == id { saveTask?.cancel(); saveTask = nil; loadedURL = nil }
        try? FileManager.default.trashItem(at: id, resultingItemURL: nil)
        if selection == id { selection = nil; content = ""; outline = []; backlinks = [] }
        refresh()
    }
}
