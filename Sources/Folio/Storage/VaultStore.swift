import Foundation
import SwiftUI
import os
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
    /// Most-recently-opened notes for this vault, most-recent-first, deduped. Feeds
    /// the quick switcher's recency ranking + empty-state list.
    @Published private(set) var recentFiles: [URL] = []
    /// Back/forward navigation availability (drives the toolbar chevrons + menu).
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    /// Bumped on every `refresh()` (external change, rename, create, delete) so
    /// views that show derived-from-disk data (e.g. the open search palette) know
    /// to recompute even when the file *count* didn't change.
    @Published private(set) var revision = 0
    /// Set by create actions so the next selection opens in edit mode (navigation
    /// otherwise opens in reading mode). Consumed by the view on selection change.
    var openInEditMode = false

    var allNoteNames: [String] { files.map(\.name) }

    private let vaultPathKey = "folio.vaultPath"
    private let bookmarkKey = "folio.vaultBookmark"   // iOS: security-scoped bookmark
    private let tabsKey = "folio.tabsByVault"      // [vaultPath: [filePath]]
    private let activeKey = "folio.activeByVault"  // [vaultPath: filePath]
    private let recentKey = "folio.recentVaults"   // [vaultPath]
    private let recentFilesKey = "folio.recentsByVault"  // [vaultPath: [filePath]]
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

    // Back/forward history. A single global stack (not per-tab) for v1 — simple and
    // predictable: it mirrors the order you visited notes in, regardless of which
    // tab they landed in. `isNavigatingHistory` suppresses the push while replaying
    // so goBack/goForward don't record themselves.
    private var backStack: [URL] = []
    private var forwardStack: [URL] = []
    private var isNavigatingHistory = false
    private let historyCap = 100

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
        recentFiles = []
        backStack = []; forwardStack = []; updateHistoryFlags()
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
        // Restore recency (drop entries whose file no longer exists) so the quick
        // switcher's empty-state list survives relaunches.
        let savedRecents = (UserDefaults.standard.dictionary(forKey: recentFilesKey) as? [String: [String]])?[root.path] ?? []
        recentFiles = savedRecents.compactMap { byPath[$0] }
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

    private func persistRecents() {
        guard let root = vaultURL else { return }
        var all = UserDefaults.standard.dictionary(forKey: recentFilesKey) as? [String: [String]] ?? [:]
        all[root.path] = recentFiles.map(\.path)
        UserDefaults.standard.set(all, forKey: recentFilesKey)
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

    /// Vault-relative path for any file/folder in the vault (what Obsidian's
    /// "copy path" gives you); falls back to the absolute path outside the vault.
    func relativePath(for url: URL) -> String {
        guard let root = vaultURL?.path, url.path.hasPrefix(root + "/") else { return url.path }
        return String(url.path.dropFirst(root.count + 1))
    }

    /// Close every tab after `url` (browser convention), keeping `url` active if
    /// the previously active tab was among the closed.
    func closeTabsToTheRight(of url: URL) {
        guard let idx = openTabs.firstIndex(of: url), idx + 1 < openTabs.count else { return }
        recentlyClosed.append(contentsOf: openTabs[(idx + 1)...]); trimClosed()
        let closedActive = selection.map { openTabs[(idx + 1)...].contains($0) } ?? false
        openTabs.removeSubrange((idx + 1)...)
        if closedActive { select(url) } else { persistSession() }
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
            if files.contains(where: { $0.id == url }) { select(url, inNewTab: true); return }
        }
    }

    /// Cycle the active tab (+1 next, -1 previous), wrapping around.
    func cycleTab(_ delta: Int) {
        guard let sel = selection, let idx = openTabs.firstIndex(of: sel), !openTabs.isEmpty else { return }
        select(openTabs[(idx + delta + openTabs.count) % openTabs.count])
    }

    /// Activate the Nth tab (0-based) — for ⌘1…⌘8. No-op if out of range.
    func activateTab(_ index: Int) {
        guard openTabs.indices.contains(index) else { return }
        select(openTabs[index])
    }

    /// Activate the last tab — ⌘9, the browser convention (jump to end, not #9).
    func activateLastTab() {
        if let last = openTabs.last { select(last) }
    }

    private func trimClosed() { if recentlyClosed.count > 20 { recentlyClosed.removeFirst(recentlyClosed.count - 20) } }

    private func startWatching() {
        watcher = nil
        guard let root = vaultURL else { return }
        watcher = VaultWatcher(path: root.path) { [weak self] in self?.enqueueWatcherEvents($0) }
    }

    /// Watcher events arrive in bursts (git pull, an agent writing a batch of
    /// files). Accumulate them and process once per lull — and then, like
    /// Obsidian, patch the index *per changed file* instead of rescanning the
    /// vault, falling back to a full rescan only for structural changes.
    /// User-initiated actions still call `refresh()` directly.
    private var refreshDebounce: Task<Void, Never>?
    private var pendingEvents: [VaultEvent] = []

    private func enqueueWatcherEvents(_ events: [VaultEvent]) {
        pendingEvents.append(contentsOf: events)
        refreshDebounce?.cancel()
        refreshDebounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
            self?.drainWatcherEvents()
        }
    }

    private func drainWatcherEvents() {
        let events = pendingEvents
        pendingEvents = []
        guard !events.isEmpty else { return }

        switch classify(events) {
        case .nothing:
            break   // e.g. only attachment/tmp-file churn — the index doesn't care
        case .fullRescan(let reason):
            Self.perfLog.debug("watcher: \(events.count) events → full rescan (\(reason))")
            refresh()
        case .reindex(let urls):
            let t0 = ContinuousClock.now
            for url in urls { reindexNote(url) }
            updateBacklinks()
            revision &+= 1
            Self.perfLog.debug("watcher: reindexed \(urls.count) note(s) in \((ContinuousClock.now - t0).ms)ms")
        }
    }

    private enum WatcherAction {
        case nothing
        case reindex(Set<URL>)
        case fullRescan(String)
    }

    /// Decide whether a burst of events can be handled by patching individual
    /// notes. Conservative: anything that might change the *set* of notes —
    /// directory events, coalescing overflow, a note appearing or disappearing
    /// (creates, deletes, and the rename half we can't pair) — falls back to a
    /// full rescan. Content-only changes to known notes are patched in place.
    private func classify(_ events: [VaultEvent]) -> WatcherAction {
        var changed: Set<URL> = []
        let known = Set(files.map(\.id.path))
        for e in events {
            if e.isStructural { return .fullRescan("structural change") }
            guard e.isFile else { return .fullRescan("non-file event") }
            let url = URL(fileURLWithPath: e.path)
            // Non-note files (attachments, .tmp) don't participate in the tree
            // or the index — ignore them entirely.
            guard mdExtensions.contains(url.pathExtension.lowercased()) else { continue }
            let exists = FileManager.default.fileExists(atPath: e.path)
            if !known.contains(url.path) { return .fullRescan(exists ? "new note" : "unknown note event") }
            if !exists { return .fullRescan("note removed or renamed away") }
            changed.insert(url)
        }
        // Above ~16 notes a rescan is cheaper than 16 backlink-map splices.
        if changed.count > 16 { return .fullRescan("large batch (\(changed.count) notes)") }
        return changed.isEmpty ? .nothing : .reindex(changed)
    }

    /// Re-index a single changed note in place — the targeted alternative to a
    /// full rescan. Refreshes its cached wikilink refs + tags, splices its old
    /// contributions out of the backlink/tag maps, and adds the new ones. The
    /// note's *name* can't have changed (renames classify as structural), so
    /// `noteByName` and the tree are untouched.
    private func reindexNote(_ url: URL) {
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate) ?? .distantPast
        if let cached = linkCache[url], cached.mtime == mtime {
            if url == loadedURL { maybeReloadOpenNote() }
            return   // duplicate/echoed event — content already indexed
        }
        let info = extractInfo(url)
        linkCache[url] = (mtime, info.refs, info.tags)

        let name = (url.lastPathComponent as NSString).deletingPathExtension
        for (target, links) in backlinkMap {
            let kept = links.filter { $0.source != url }
            if kept.count != links.count { backlinkMap[target] = kept }
        }
        for ref in info.refs where resolve(ref.inner) != nil {
            backlinkMap[resolve(ref.inner)!, default: []].append(
                Backlink(source: url, sourceName: name, context: ref.context))
        }

        var tags = tagsIndex
        for (tag, urls) in tags {
            let kept = urls.filter { $0 != url }
            if kept.count != urls.count { tags[tag] = kept.isEmpty ? nil : kept }
        }
        for tag in info.tags { tags[tag, default: []].append(url) }
        tagsIndex = tags

        if url == loadedURL { maybeReloadOpenNote() }
    }

    // MARK: - File listing (tree + flat) + link index

    /// Perf log for the scan/index path. Follow live with:
    ///   log stream --level debug --predicate 'subsystem == "com.sriramb.folio"'
    private static let perfLog = Logger(subsystem: "com.sriramb.folio", category: "perf")

    func refresh() {
        guard let root = vaultURL else { tree = []; files = []; return }
        let t0 = ContinuousClock.now
        var flat: [MarkdownFile] = []
        tree = buildTree(root, root: root, flat: &flat)
        files = flat.sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
        let tTree = ContinuousClock.now
        rebuildLinkIndex()
        let tIndex = ContinuousClock.now
        updateBacklinks()
        maybeReloadOpenNote()
        revision &+= 1

        let treeMs = (tTree - t0).ms, indexMs = (tIndex - tTree).ms
        let totalMs = (ContinuousClock.now - t0).ms
        // Always visible at debug level; escalates when a refresh is slow enough
        // to matter (this all runs on the main thread today).
        if totalMs > 100 {
            Self.perfLog.notice("slow refresh: \(totalMs)ms (tree \(treeMs)ms, index \(indexMs)ms, \(self.files.count) files)")
        } else {
            Self.perfLog.debug("refresh: \(totalMs)ms (tree \(treeMs)ms, index \(indexMs)ms, \(self.files.count) files)")
        }
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

    /// Open a note. Tab behavior (the Obsidian model):
    ///  - already open in a tab → just activate that tab (never a duplicate);
    ///  - `inNewTab` set, or nothing open yet → append a new tab;
    ///  - otherwise → replace the *active* tab's URL in place, so a stream of opens
    ///    leaves one tab trail instead of one tab per file.
    func select(_ id: MarkdownFile.ID?, inNewTab: Bool = false) {
        // Ignore nil/folder/duplicate selections so a folder click never blanks
        // the open note (folders toggle expansion in the explorer instead).
        guard let id, files.contains(where: { $0.id == id }), id != selection else { return }
        flushSave()

        // History: record where we're leaving from (unless this *is* a replay), and
        // clear the forward stack — a fresh navigation forks the timeline.
        if !isNavigatingHistory, let prev = selection {
            backStack.append(prev)
            if backStack.count > historyCap { backStack.removeFirst(backStack.count - historyCap) }
            forwardStack.removeAll()
        }

        // Tab placement.
        lastTabReplacement = nil
        if openTabs.firstIndex(of: id) == nil {
            if inNewTab || openTabs.isEmpty {
                openTabs.append(id)
            } else if let active = selection, let idx = openTabs.firstIndex(of: active) {
                openTabs[idx] = id                          // replace active tab in place
                lastTabReplacement = (evicted: active, by: id)
            } else {
                openTabs.append(id)                         // no active tab → append
            }
        }

        selection = id
        content = (try? String(contentsOf: id, encoding: .utf8)) ?? ""
        diskContent = content
        loadedURL = id
        savedAt = nil
        noteOpened(id)
        updateOutline()
        updateBacklinks()
        updateHistoryFlags()
        persistSession()
    }

    /// The most recent in-place tab replacement (single-click navigation evicting
    /// the previous note from the active tab). Lets a *double*-click undo it: the
    /// second click arrives after the first already replaced the tab, and
    /// `openInOwnTab` uses this to give the evicted note its tab back.
    private var lastTabReplacement: (evicted: URL, by: URL)?

    /// Sidebar double-click: "keep both". The first click of the double already
    /// navigated the current tab here (evicting what was being read); restore the
    /// evicted note to its tab and give this note its own tab beside it — VS Code's
    /// double-click-to-keep-open, adapted to our navigate-in-current-tab model.
    /// If nothing was evicted (note was already in a tab), this is a no-op.
    func openInOwnTab(_ id: URL) {
        guard let swap = lastTabReplacement, swap.by == id,
              selection == id,
              let idx = openTabs.firstIndex(of: id),
              !openTabs.contains(swap.evicted),
              files.contains(where: { $0.id == swap.evicted })
        else { select(id, inNewTab: true); return }   // covers "not open at all" too
        openTabs[idx] = swap.evicted            // the note being read keeps its tab…
        openTabs.insert(id, at: idx + 1)        // …and the new note gets its own
        lastTabReplacement = nil
        persistSession()
    }

    /// Record a note as most-recently-opened (deduped, capped, persisted per vault).
    private func noteOpened(_ url: URL) {
        recentFiles.removeAll { $0 == url }
        recentFiles.insert(url, at: 0)
        if recentFiles.count > 50 { recentFiles.removeLast(recentFiles.count - 50) }
        persistRecents()
    }

    private func updateHistoryFlags() {
        if canGoBack != !backStack.isEmpty { canGoBack = !backStack.isEmpty }
        if canGoForward != !forwardStack.isEmpty { canGoForward = !forwardStack.isEmpty }
    }

    /// Go back to the previous note, pushing the current one onto forward. Skips
    /// entries whose file has since been deleted; navigates in the current tab.
    func goBack() {
        guard let target = popExistingURL(&backStack) else { updateHistoryFlags(); return }
        if let cur = selection {
            forwardStack.append(cur)
            if forwardStack.count > historyCap { forwardStack.removeFirst(forwardStack.count - historyCap) }
        }
        navigateHistory(to: target)
    }

    /// Replay a forward step (undo a goBack), pushing the current note onto back.
    func goForward() {
        guard let target = popExistingURL(&forwardStack) else { updateHistoryFlags(); return }
        if let cur = selection {
            backStack.append(cur)
            if backStack.count > historyCap { backStack.removeFirst(backStack.count - historyCap) }
        }
        navigateHistory(to: target)
    }

    /// Pop the most recent entry that still points at an existing note (and isn't
    /// the current selection), discarding stale ones along the way.
    private func popExistingURL(_ stack: inout [URL]) -> URL? {
        while let url = stack.popLast() {
            if url != selection, files.contains(where: { $0.id == url }),
               FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    private func navigateHistory(to url: URL) {
        isNavigatingHistory = true
        select(url)                 // won't touch the stacks while the flag is set
        isNavigatingHistory = false
        updateHistoryFlags()
    }

    /// Open a wikilink target — navigate if it resolves, else create the note.
    /// `inNewTab` carries a ⌘-click through from the click site.
    func openWikilink(_ target: String, inNewTab: Bool = false) {
        if let dest = resolve(target) { select(dest, inNewTab: inNewTab); return }
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
        select(url, inNewTab: true)  // creation is explicit → don't evict the current read
    }

    // MARK: - External open (Finder / CLI / folio:// deep links)

    /// Parsed `folio://open?vault=…&file=…` link. Pure value (no filesystem
    /// access) so the parse step is trivially testable in isolation; the caller
    /// resolves the paths against the running vault.
    struct FolioLink: Equatable {
        var vault: String?   // absolute directory path, percent-decoded
        var file: String?    // vault-relative when `vault` is set, else absolute
    }

    /// Parse a `folio://open?…` URL. Returns nil for anything else. `URLComponents`
    /// percent-decodes the query values for us, so a link built by `folioLink(for:)`
    /// round-trips (spaces, "#", "&" in note names survive).
    static func parseFolioLink(_ url: URL) -> FolioLink? {
        // Scheme and host compare case-insensitively (RFC 3986 — "FOLIO://OPEN"
        // is the same link).
        guard url.scheme?.lowercased() == "folio",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              comps.host?.lowercased() == "open" else { return nil }
        let items = comps.queryItems ?? []
        func value(_ name: String) -> String? {
            let v = items.first { $0.name == name }?.value
            return (v?.isEmpty ?? true) ? nil : v
        }
        return FolioLink(vault: value("vault"), file: value("file"))
    }

    /// Single funnel for URLs arriving from outside the app (the delegate's
    /// `application(_:open:)`): file URLs from Finder / `open -a Folio x.md`, and
    /// `folio://` deep links. Paths are standardized before any vault-prefix check
    /// so a crafted link with `..` can't masquerade as living inside a vault.
    func handleExternal(urls: [URL]) {
        for url in urls {
            if url.isFileURL { openExternalFile(url) }
            else if url.scheme?.lowercased() == "folio" { openFolioLink(url) }
            else { beep() }
        }
    }

    private func openFolioLink(_ url: URL) {
        guard let link = Self.parseFolioLink(url) else { beep(); return }
        // A vault-qualified link fully specifies where the note lives: switch to
        // that vault first (only if it still exists), then select the file — the
        // link *is* the navigation, so it lands in the current tab, not a new one.
        if let vaultPath = link.vault {
            let target = URL(fileURLWithPath: vaultPath).standardizedFileURL
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir),
                  isDir.boolValue else { beep(); return }
            if target.path != vaultURL?.standardizedFileURL.path { setVault(target) }
            if let file = link.file {   // vault-only links (no file) just open the vault
                let fileURL = target.appendingPathComponent(file).standardizedFileURL
                if !selectResolved(fileURL) { beep() }
            }
            return
        }
        // No vault → `file` is expected to be an absolute path (same as a file URL).
        if let file = link.file { openExternalFile(URL(fileURLWithPath: file)) } else { beep() }
    }

    /// Open a Markdown file identified by an absolute URL, finding it a vault to
    /// live in. Folio can't render a rootless note, so the tiers below reuse an
    /// open/known vault when the file sits inside one, and otherwise fall back to
    /// treating the file's *parent directory* as a throwaway vault — which is what
    /// makes "open any project doc in Folio" just work.
    private func openExternalFile(_ url: URL) {
        let url = url.standardizedFileURL
        guard mdExtensions.contains(url.pathExtension.lowercased()),
              FileManager.default.fileExists(atPath: url.path) else { beep(); return }
        // Compare through resolved symlinks: a vault opened via a symlinked path
        // (e.g. ~/Projects/vapi/dev → vapi-ops) must still claim a file addressed
        // by its real path, and vice versa — otherwise we'd fall through to tier 3
        // and open a duplicate vault for the same folder.
        let resolved = url.resolvingSymlinksInPath().path

        // 1. Already inside the current vault → just select it.
        if let root = vaultURL,
           resolved.hasPrefix(root.standardizedFileURL.resolvingSymlinksInPath().path + "/") {
            if !selectResolved(url) { beep() }
            return
        }
        // 2. Inside a recent vault (deepest matching prefix wins, so a nested vault
        //    beats its parent) → switch to that vault, then select.
        if let host = recentVaults
            .filter({ resolved.hasPrefix($0.standardizedFileURL.resolvingSymlinksInPath().path + "/") })
            .max(by: { $0.standardizedFileURL.path.count < $1.standardizedFileURL.path.count }) {
            setVault(host)
            if !selectResolved(url) { beep() }
            return
        }
        // 3. No known vault contains it → open its parent directory as the vault.
        setVault(url.deletingLastPathComponent())
        if !selectResolved(url) { beep() }
    }

    /// Select a note that may be addressed by a different alias of its path than
    /// the vault index uses (symlinked vault vs. real path). Exact match first,
    /// then a resolved-path match against the indexed files.
    ///
    /// Always opens in a **new tab**: an external open (Finder, CLI, deep link) is
    /// an additive act — it must never evict the note the user is reading. If the
    /// note is already open somewhere, its tab is activated instead (no duplicate).
    @discardableResult
    private func selectResolved(_ url: URL) -> Bool {
        if files.contains(where: { $0.id == url }) { select(url, inNewTab: true); return true }
        let resolved = url.resolvingSymlinksInPath().path
        if let match = files.first(where: { $0.id.resolvingSymlinksInPath().path == resolved }) {
            select(match.id, inNewTab: true); return true
        }
        return false
    }

    /// Build a `folio://open?vault=…&file=…` deep link for a note — the string an
    /// agent or another app pastes to jump straight here. Values are percent-encoded
    /// by `URLComponents` and round-trip through `parseFolioLink`.
    func folioLink(for url: URL) -> String {
        var comps = URLComponents()
        comps.scheme = "folio"
        comps.host = "open"
        var items: [URLQueryItem] = []
        if let root = vaultURL { items.append(URLQueryItem(name: "vault", value: root.path)) }
        items.append(URLQueryItem(name: "file", value: relativePath(for: url)))
        comps.queryItems = items
        return comps.string ?? ""
    }

    private func beep() {
        #if os(macOS)
        NSSound.beep()
        #endif
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

    /// Create an untitled note — in `dir` when given (the explorer's "New Note in
    /// Folder"), else in the standard new-note folder.
    func newNote(in dir: URL? = nil) {
        guard let dir = dir ?? newNoteDirectory() else { return }
        let fm = FileManager.default
        var name = "Untitled.md"
        var n = 1
        while fm.fileExists(atPath: dir.appendingPathComponent(name).path) {
            n += 1; name = "Untitled \(n).md"
        }
        createAndOpen(at: dir.appendingPathComponent(name))
    }

    /// Create `<title>.md` (deduping the name if it exists) in the standard
    /// new-note folder and open it for writing. Used by the quick switcher's
    /// create-on-miss so the placement rule stays identical to `newNote()`.
    /// Returns the created (or opened, if it already existed) note's URL.
    @discardableResult
    func createNote(named title: String) -> URL? {
        guard let dir = newNoteDirectory() else { return nil }
        let stripped = title.hasSuffix(".md") ? String(title.dropLast(3)) : title
        // A switcher query is a note *name*, never a path: keep only the last path
        // component so "../escape" or "sub/dir" can't write outside the vault or
        // into a folder that doesn't exist.
        let base = (stripped as NSString).lastPathComponent
            .trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty, base != ".", base != ".." else { return nil }
        let fm = FileManager.default
        var fileName = base + ".md"
        var candidate = dir.appendingPathComponent(fileName)
        var n = 1
        while fm.fileExists(atPath: candidate.path) {
            n += 1; fileName = "\(base) \(n).md"
            candidate = dir.appendingPathComponent(fileName)
        }
        return createAndOpen(at: candidate) ? candidate : nil
    }

    /// New notes land in the current note's folder, else the vault root — the one
    /// placement rule shared by every create path.
    private func newNoteDirectory() -> URL? {
        guard let root = vaultURL else { return nil }
        return selection?.deletingLastPathComponent() ?? root
    }

    @discardableResult
    private func createAndOpen(at url: URL) -> Bool {
        do { try "".write(to: url, atomically: true, encoding: .utf8) } catch {
            #if os(macOS)
            NSSound.beep()               // e.g. read-only folder — don't pretend it worked
            #endif
            return false
        }
        refresh()
        openInEditMode = true        // new note → start writing
        select(url, inNewTab: true)  // creation is explicit → don't evict the current read
        return true
    }

    func rename(_ id: URL, to newName: String) {
        // Rename takes a file *name*, not a path — a "/" would silently move the
        // note (or escape the vault); keep only the last component.
        let trimmed = ((newName.trimmingCharacters(in: .whitespacesAndNewlines))
            as NSString).lastPathComponent
        guard !trimmed.isEmpty, trimmed != ".", trimmed != ".." else { return }
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
            remapNavigationState(from: id, to: dest)
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

    /// A rename moves the note's URL out from under every URL-keyed navigation
    /// structure; rewrite them all so recency ranking, Back/Forward, and Reopen
    /// Closed Tab keep working across the rename instead of silently skipping it.
    private func remapNavigationState(from old: URL, to new: URL) {
        recentFiles = recentFiles.map { $0 == old ? new : $0 }
        backStack = backStack.map { $0 == old ? new : $0 }
        forwardStack = forwardStack.map { $0 == old ? new : $0 }
        recentlyClosed = recentlyClosed.map { $0 == old ? new : $0 }
        persistRecents()
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

private extension Duration {
    /// Whole milliseconds, for perf log lines.
    var ms: Int { Int(components.seconds * 1000) + Int(components.attoseconds / 1_000_000_000_000_000) }
}
