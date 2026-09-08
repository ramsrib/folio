import Foundation
import Testing
@testable import Folio

/// The shared store, compiled for iOS and exercised the way the iOS screens use
/// it: open a folder, walk the tree, open a note, edit, save, restore. These run
/// hosted inside the app on a simulator, so UIKit-only branches (the bookmark
/// path) are the ones under test — the macOS suite never reaches them.
@MainActor
@Suite("VaultStore on iOS", .serialized)
struct VaultStoreiOSTests {

    // MARK: - Fixture

    /// A throwaway vault on disk. Removed, along with the UserDefaults keys the
    /// store writes, when the test finishes — so a test run can't leave the host
    /// app pointing at a folder that no longer exists.
    final class TempVault {
        let root: URL
        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("folio-test-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        @discardableResult
        func write(_ relative: String, _ text: String) throws -> URL {
            let url = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        }
        func read(_ relative: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
        }
        deinit {
            try? FileManager.default.removeItem(at: root)
            for key in ["folio.vaultBookmark", "folio.vaultPath", "folio.openVaults", "folio.recentVaults",
                        "folio.tabsByVault", "folio.activeByVault", "folio.recentsByVault"] {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    private func sampleVault() throws -> TempVault {
        let v = try TempVault()
        try v.write("Welcome.md", "# Welcome\n\nFirst note. #intro #folio\n")
        try v.write("Projects/Folio.md", "# Folio\n\nA notes app. #folio\n\nSee [[Welcome]].\n")
        try v.write("Projects/Ideas.md", "- one\n- two\n")
        try v.write("Projects/Archive/Old.md", "old\n")
        try v.write("notes.txt", "not markdown")
        try v.write("node_modules/pkg/README.md", "# ignored\n")
        return v
    }

    // MARK: - Opening a vault

    @Test("Opening a folder builds the tree and the flat file list")
    func openBuildsTree() throws {
        let v = try sampleVault()
        let store = VaultStore()
        store.setVault(v.root)

        #expect(store.vaultURL == v.root)
        #expect(Set(store.files.map(\.name)) == ["Welcome", "Folio", "Ideas", "Old"])
        #expect(Set(store.tree.map(\.name)) == ["Projects", "Welcome"],
                "top level: the Projects folder and Welcome (no extension); notes.txt and node_modules are skipped")

        let projects = try #require(store.tree.first { $0.isDirectory })
        #expect(projects.name == "Projects")
        #expect(Set(projects.children?.map(\.name) ?? []) == ["Archive", "Folio", "Ideas"])
    }

    @Test("Relative paths are vault-relative, names drop the extension")
    func markdownFilePaths() throws {
        let v = try sampleVault()
        let store = VaultStore()
        store.setVault(v.root)
        let folio = try #require(store.files.first { $0.name == "Folio" })
        #expect(folio.relativePath == "Projects/Folio.md")
    }

    @Test("Tags are indexed across the vault, most-used first")
    func tagsIndexed() throws {
        let v = try sampleVault()
        let store = VaultStore()
        store.setVault(v.root)

        #expect(store.allTags.map(\.tag) == ["folio", "intro"])
        #expect(store.allTags.first?.count == 2)
        #expect(Set(store.notes(forTag: "folio").map(\.name)) == ["Welcome", "Folio"])
        #expect(store.notes(forTag: "intro").map(\.name) == ["Welcome"])
        #expect(store.notes(forTag: "missing").isEmpty)
    }

    // MARK: - Reading and editing a note

    @Test("Selecting a note loads its text; a folder or unknown URL is ignored")
    func selectLoadsContent() throws {
        let v = try sampleVault()
        let store = VaultStore()
        store.setVault(v.root)
        let welcome = try #require(store.files.first { $0.name == "Welcome" })

        store.select(welcome.id)
        #expect(store.selection == welcome.id)
        #expect(store.content == "# Welcome\n\nFirst note. #intro #folio\n")
        #expect(store.outline.map(\.title) == ["Welcome"])

        store.select(v.root.appendingPathComponent("Projects"))
        #expect(store.selection == welcome.id, "a folder never replaces the open note")
        store.select(nil)
        #expect(store.selection == welcome.id)
    }

    @Test("Edits reach disk through the debounced save")
    func debouncedSave() async throws {
        let v = try sampleVault()
        let store = VaultStore()
        store.setVault(v.root)
        let ideas = try #require(store.files.first { $0.name == "Ideas" })
        store.select(ideas.id)

        store.content += "- three\n"
        store.contentEdited()
        #expect(try v.read("Projects/Ideas.md") == "- one\n- two\n", "not yet: the save is debounced")

        try await Task.sleep(for: .milliseconds(900))
        #expect(try v.read("Projects/Ideas.md") == "- one\n- two\n- three\n")
        #expect(store.savedAt != nil)
    }

    @Test("Leaving a note flushes a pending edit immediately")
    func flushOnLeave() throws {
        let v = try sampleVault()
        let store = VaultStore()
        store.setVault(v.root)
        let ideas = try #require(store.files.first { $0.name == "Ideas" })
        store.select(ideas.id)

        store.content = "- rewritten\n"
        store.contentEdited()
        store.flushSave()                       // NoteScreen.onDisappear
        #expect(try v.read("Projects/Ideas.md") == "- rewritten\n")
    }

    @Test("Toggling a task checkbox rewrites the marker in place")
    func toggleTask() throws {
        let v = try sampleVault()
        let url = try v.write("Todo.md", "- [ ] buy milk\n- [x] done\n")
        let store = VaultStore()
        store.setVault(v.root)
        store.select(url)

        store.toggleTask(atContentIndex: 3)     // the space inside "[ ]"
        #expect(store.content == "- [x] buy milk\n- [x] done\n")
        store.toggleTask(atContentIndex: 18)    // the x inside the second "[x]"
        #expect(store.content == "- [x] buy milk\n- [ ] done\n")
    }

    // MARK: - Persistence across launches (the iOS-only bookmark path)

    @Test("Opening a vault stores a security-scoped bookmark, and start() reopens it")
    func bookmarkRestore() throws {
        let v = try sampleVault()
        VaultStore().setVault(v.root)

        let data = try #require(UserDefaults.standard.data(forKey: "folio.vaultBookmark"))
        var stale = false
        let resolved = try URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)
        #expect(resolved.resolvingSymlinksInPath().path == v.root.resolvingSymlinksInPath().path)

        // A fresh store, as on the next launch: nothing until start(), then the vault.
        let relaunched = VaultStore()
        #expect(relaunched.vaultURL == nil)
        relaunched.start()
        #expect(relaunched.vaultURL?.resolvingSymlinksInPath().path == v.root.resolvingSymlinksInPath().path)
        #expect(Set(relaunched.files.map(\.name)) == ["Welcome", "Folio", "Ideas", "Old"])
    }

    @Test("A vault given at init wins over the saved bookmark")
    func requestedVaultWins() throws {
        let saved = try sampleVault()
        VaultStore().setVault(saved.root)

        let other = try TempVault()
        try other.write("Only.md", "# Only\n")
        let store = VaultStore(vault: other.root)
        store.start()
        #expect(store.vaultURL == other.root)
        #expect(store.files.map(\.name) == ["Only"])
    }

    @Test("Refresh picks up notes written while the app wasn't watching")
    func refreshFindsNewFiles() throws {
        let v = try sampleVault()
        let store = VaultStore()
        store.setVault(v.root)
        let before = store.revision

        try v.write("Later.md", "# Later\n#new\n")
        store.refresh()                          // the browser's pull-to-refresh
        #expect(store.revision > before)
        #expect(store.files.contains { $0.name == "Later" })
        #expect(store.notes(forTag: "new").map(\.name) == ["Later"])
    }
}
