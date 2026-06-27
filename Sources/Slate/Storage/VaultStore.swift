import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

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
    @Published private(set) var openTabs: [URL] = []   // open notes, in tab order
    @Published private(set) var recentVaults: [URL] = []
    /// Set by create actions so the next selection opens in edit mode (navigation
    /// otherwise opens in reading mode). Consumed by the view on selection change.
    var openInEditMode = false

    var allNoteNames: [String] { files.map(\.name) }

    private let vaultPathKey = "slate.vaultPath"
    private let bookmarkKey = "slate.vaultBookmark"   // iOS: security-scoped bookmark
    private let tabsKey = "slate.tabsByVault"      // [vaultPath: [filePath]]
    private let activeKey = "slate.activeByVault"  // [vaultPath: filePath]
    private let recentKey = "slate.recentVaults"   // [vaultPath]
    private let mdExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]
    /// Dependency/build directories never worth scanning (so pointing a vault at a
    /// code project doesn't crawl node_modules and index package READMEs). Hidden
    /// dirs (.git, .build, .next, .venv, …) are already skipped via skipsHiddenFiles.
    private let ignoredDirs: Set<String> = [
        "node_modules", "vendor", "Pods", "bower_components", "__pycache__",
        "venv", "build", "dist", "out", "target", "DerivedData", "coverage",
    ]
    private var loadedURL: URL?
    private var diskContent = ""   // last content known to be on disk (dirty check)
    private var saveTask: Task<Void, Never>?
    private var watcher: VaultWatcher?
    private var recentlyClosed: [URL] = []   // stack for "reopen closed tab"

    // Link index
    private var noteByName: [String: [URL]] = [:]     // lowercased basename -> urls
    private var backlinkMap: [URL: [Backlink]] = [:]  // target note -> inbound links
    private typealias LinkRef = (inner: String, context: String)
    private var linkCache: [URL: (mtime: Date, refs: [LinkRef], tags: [String])] = [:]  // mtime-keyed cache
    @Published private(set) var tagsIndex: [String: [URL]] = [:]   // tag -> notes
    private static let tagRegex = try! NSRegularExpression(pattern: "(?<!\\S)#([A-Za-z0-9_][A-Za-z0-9_/-]*)")

    var allTags: [(tag: String, count: Int)] {
        tagsIndex.map { (tag: $0.key, count: $0.value.count) }.sorted {
            $0.count != $1.count ? $0.count > $1.count
                : $0.tag.localizedCaseInsensitiveCompare($1.tag) == .orderedAscending
        }
    }

    func notes(forTag tag: String) -> [MarkdownFile] {
        let urls = Set(tagsIndex[tag] ?? [])
        return files.filter { urls.contains($0.url) }
    }

    private static let wikiRegex = try! NSRegularExpression(pattern: "\\[\\[([^\\]]+)\\]\\]")
    private static let headingRegex = try! NSRegularExpression(
        pattern: "^(#{1,6})\\s+(.+)$", options: [.anchorsMatchLines])

    init() {
        recentVaults = (UserDefaults.standard.array(forKey: recentKey) as? [String] ?? [])
            .map { URL(fileURLWithPath: $0) }
        restoreVault()
    }

    // MARK: - Vault selection

    func pickVault() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Vault"
        panel.message = "Choose a folder of Markdown notes"
        if panel.runModal() == .OK, let url = panel.url { setVault(url) }
        #endif
        // iOS opens vaults via UIDocumentPicker from the app layer → setVault(_:).
    }

    func setVault(_ url: URL) {
        flushSave()
        vaultURL = url
        UserDefaults.standard.set(url.path, forKey: vaultPathKey)
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        // iOS: persist a security-scoped bookmark so we can reopen the (often
        // iCloud Drive) folder across launches without re-prompting.
        if let data = try? url.bookmarkData() {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }
        #endif
        addRecent(url)
        selection = nil; content = ""; loadedURL = nil
        outline = []; backlinks = []; openTabs = []
        refresh()
        startWatching()
        restoreSession()
    }

    private func addRecent(_ url: URL) {
        recentVaults.removeAll { $0.path == url.path }
        recentVaults.insert(url, at: 0)
        recentVaults = Array(recentVaults.prefix(10)).filter { FileManager.default.fileExists(atPath: $0.path) }
        UserDefaults.standard.set(recentVaults.map(\.path), forKey: recentKey)
    }

    func clearRecentVaults() {
        recentVaults = []
        UserDefaults.standard.removeObject(forKey: recentKey)
    }

    private func restoreVault() {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        // iOS: resolve the security-scoped bookmark and begin access before reading.
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else { return }
        _ = url.startAccessingSecurityScopedResource()
        vaultURL = url
        addRecent(url)
        refresh()
        startWatching()           // no-op on iOS
        restoreSession()
        #else
        guard let path = UserDefaults.standard.string(forKey: vaultPathKey) else { return }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        vaultURL = url
        addRecent(url)
        refresh()
        startWatching()
        restoreSession()
        #endif
    }

    // MARK: - Session (tabs) persistence

    /// Restore the tabs + active note saved for this vault.
    private func restoreSession() {
        guard let root = vaultURL else { return }
        let byPath = Dictionary(files.map { ($0.id.path, $0.id) }, uniquingKeysWith: { a, _ in a })
        let savedTabs = (UserDefaults.standard.dictionary(forKey: tabsKey) as? [String: [String]])?[root.path] ?? []
        openTabs = savedTabs.compactMap { byPath[$0] }
        let activePath = (UserDefaults.standard.dictionary(forKey: activeKey) as? [String: String])?[root.path]
        if let activePath, let active = byPath[activePath] {
            select(active)
        } else if let first = openTabs.first {
            select(first)
        }
    }

    private func persistSession() {
        guard let root = vaultURL else { return }
        var tabs = UserDefaults.standard.dictionary(forKey: tabsKey) as? [String: [String]] ?? [:]
        tabs[root.path] = openTabs.map(\.path)
        UserDefaults.standard.set(tabs, forKey: tabsKey)
        var active = UserDefaults.standard.dictionary(forKey: activeKey) as? [String: String] ?? [:]
        active[root.path] = selection?.path
        UserDefaults.standard.set(active, forKey: activeKey)
    }

    /// Close a tab; if it was active, activate a neighbor (or clear if last).
    func closeTab(_ url: URL) {
        guard let idx = openTabs.firstIndex(of: url) else { return }
        let wasActive = selection == url
        openTabs.remove(at: idx)
        recentlyClosed.append(url); trimClosed()
        if wasActive {
            if loadedURL == url { saveTask?.cancel(); saveTask = nil }
            flushSave()
            selection = nil; loadedURL = nil
            if !openTabs.isEmpty {
                select(openTabs[min(idx, openTabs.count - 1)])
            } else {
                content = ""; outline = []; backlinks = []
            }
        }
        persistSession()
    }

    /// Drag-reorder: move `src` to `dst`'s position.
    func reorderTab(from src: URL, to dst: URL) {
        guard let from = openTabs.firstIndex(of: src),
              let to = openTabs.firstIndex(of: dst), from != to else { return }
        openTabs.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        persistSession()
    }

    func closeOtherTabs(keeping url: URL) {
        recentlyClosed.append(contentsOf: openTabs.filter { $0 != url }); trimClosed()
        openTabs = openTabs.contains(url) ? [url] : []
        if selection != url { select(url) } else { persistSession() }
    }

    func closeAllTabs() {
        recentlyClosed.append(contentsOf: openTabs); trimClosed()
        flushSave()
        openTabs = []
        selection = nil; loadedURL = nil; content = ""; outline = []; backlinks = []
        persistSession()
    }

    /// Re-open the most recently closed tab whose file still exists (⌘⇧T).
    func reopenClosedTab() {
        while let url = recentlyClosed.popLast() {
            if files.contains(where: { $0.id == url }) { select(url); return }
        }
    }

    /// Cycle the active tab (+1 next, -1 previous), wrapping around.
    func cycleTab(_ delta: Int) {
        guard let sel = selection, let idx = openTabs.firstIndex(of: sel), !openTabs.isEmpty else { return }
        select(openTabs[(idx + delta + openTabs.count) % openTabs.count])
    }

    private func trimClosed() { if recentlyClosed.count > 20 { recentlyClosed.removeFirst(recentlyClosed.count - 20) } }

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
        maybeReloadOpenNote()
    }

    /// If the open note changed on disk (cloud sync / another app / the iOS app)
    /// and we have no pending local save, pull the new content in. Skipping when
    /// a save is pending preserves unsaved local edits.
    private func maybeReloadOpenNote() {
        guard let url = loadedURL, saveTask == nil else { return }
        guard let disk = try? String(contentsOf: url, encoding: .utf8), disk != content else { return }
        content = disk
        diskContent = disk
        updateOutline()
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
                if ignoredDirs.contains(url.lastPathComponent) { continue }   // skip node_modules etc.
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

    /// Incremental link index: only re-reads files whose modification date
    /// changed since last scan; unchanged files reuse cached wikilink refs.
    private func rebuildLinkIndex() {
        noteByName = [:]
        backlinkMap = [:]
        for f in files { noteByName[f.name.lowercased(), default: []].append(f.url) }

        var tags: [String: [URL]] = [:]
        for f in files {
            let mtime = (try? f.url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            let info: (refs: [LinkRef], tags: [String])
            if let cached = linkCache[f.url], cached.mtime == mtime {
                info = (cached.refs, cached.tags)
            } else {
                info = extractInfo(f.url)
                linkCache[f.url] = (mtime, info.refs, info.tags)
            }
            for ref in info.refs where resolve(ref.inner) != nil {
                let dest = resolve(ref.inner)!
                backlinkMap[dest, default: []].append(
                    Backlink(source: f.url, sourceName: f.name, context: ref.context))
            }
            for tag in info.tags { tags[tag, default: []].append(f.url) }
        }
        tagsIndex = tags
        let current = Set(files.map(\.url))               // drop cache for deleted files
        linkCache = linkCache.filter { current.contains($0.key) }
    }

    private func extractInfo(_ url: URL) -> (refs: [LinkRef], tags: [String]) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return ([], []) }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var refs: [LinkRef] = []
        Self.wikiRegex.enumerateMatches(in: text, range: full) { m, _, _ in
            guard let m else { return }
            refs.append((
                inner: ns.substring(with: m.range(at: 1)),
                context: ns.substring(with: ns.lineRange(for: m.range))
                    .trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        var tags = Set<String>()
        Self.tagRegex.enumerateMatches(in: text, range: full) { m, _, _ in
            guard let m else { return }
            tags.insert(ns.substring(with: m.range(at: 1)))
        }
        tags.formUnion(frontmatterTags(text))
        return (refs, Array(tags))
    }

    private func frontmatterTags(_ text: String) -> [String] {
        let lines = text.components(separatedBy: "\n")
        guard lines.first == "---" else { return [] }
        var out: [String] = []
        var inTags = false
        var i = 1
        while i < lines.count, lines[i] != "---" {
            let raw = lines[i]
            let t = raw.trimmingCharacters(in: .whitespaces)
            if inTags {
                if t.hasPrefix("-") { out.append(t.dropFirst().trimmingCharacters(in: .whitespaces)) }
                else if !(raw.first == " " || raw.first == "\t") { inTags = false }
            }
            if t.hasPrefix("tags:") {
                let val = t.dropFirst("tags:".count).trimmingCharacters(in: .whitespaces)
                if val.hasPrefix("[") {
                    out.append(contentsOf: val.dropFirst().dropLast()
                        .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
                } else if val.isEmpty { inTags = true }
                else { out.append(val) }
            }
            i += 1
        }
        return out.filter { !$0.isEmpty }
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
        // Ignore nil/folder/duplicate selections so a folder click never blanks
        // the open note (folders toggle expansion in the explorer instead).
        guard let id, files.contains(where: { $0.id == id }), id != selection else { return }
        flushSave()
        selection = id
        if !openTabs.contains(id) { openTabs.append(id) }   // open file → ensure a tab
        content = (try? String(contentsOf: id, encoding: .utf8)) ?? ""
        diskContent = content
        loadedURL = id
        savedAt = nil
        updateOutline()
        updateBacklinks()
        persistSession()
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
        openInEditMode = true        // followed an unresolved link → new note to write
        select(url)
    }

    /// Called by the editor on every edit.
    func contentEdited() {
        updateOutline()
        scheduleSave()
    }

    /// Toggle a task checkbox character (' ' <-> 'x') at a content offset — used
    /// by Reading mode's tappable checkboxes.
    func toggleTask(atContentIndex idx: Int) {
        let ns = content as NSString
        guard idx >= 0, idx < ns.length else { return }
        let current = ns.substring(with: NSRange(location: idx, length: 1)).lowercased()
        let new = current == "x" ? " " : "x"
        content = ns.replacingCharacters(in: NSRange(location: idx, length: 1), with: new)
        contentEdited()
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
            self?.diskContent = text
            self?.savedAt = Date()
            self?.saveTask = nil      // clear so external-change reload can run again
        }
    }

    func flushSave() {
        saveTask?.cancel(); saveTask = nil
        guard let url = loadedURL, content != diskContent else { return }   // skip if unchanged
        try? content.write(to: url, atomically: true, encoding: .utf8)
        diskContent = content
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
        openInEditMode = true        // new note → start writing
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
            if let i = openTabs.firstIndex(of: id) { openTabs[i] = dest }   // keep tab on rename
            if let open = loadedURL, changed.contains(open) {
                content = (try? String(contentsOf: open, encoding: .utf8)) ?? content
            }
            refresh()
            updateOutline()
            persistSession()
        } catch {
            #if os(macOS)
            NSSound.beep()
            #endif
        }
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
        let wasActive = selection == id
        let idx = openTabs.firstIndex(of: id)
        openTabs.removeAll { $0 == id }
        refresh()
        if wasActive {
            selection = nil
            if let idx, !openTabs.isEmpty {
                select(openTabs[min(idx, openTabs.count - 1)])
            } else {
                content = ""; outline = []; backlinks = []
            }
        }
        persistSession()
    }
}
