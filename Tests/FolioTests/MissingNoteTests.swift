#if os(macOS)
import AppKit
import Foundation
import Testing
@testable import Folio

/// What happens to an open note when its file goes away behind Folio's back —
/// trashed in Finder, renamed by another tool, dropped by a branch switch, or
/// deleted from a second Folio window (each window has its own store).
///
/// The regression these pin: `select` used to require the URL to be in `files`,
/// so clicking the tab of a deleted note did *nothing at all* — no navigation, no
/// message, no beep. The tab looked completely ordinary and the app looked broken.
///
/// Serialized: `setVault` writes the session and per-vault tab keys in
/// `UserDefaults.standard`, which is process-wide.
@MainActor
@Suite("Missing notes", .serialized)
struct MissingNoteTests {

    /// A vault on disk holding `a.md` and `b.md`, with the shared defaults reset
    /// so tests don't inherit each other's session — or the developer's real one.
    static func vault() -> URL {
        _ = NSApplication.shared
        for key in ["folio.recentVaults", "folio.openVaults", "folio.vaultPath",
                    "folio.tabsByVault", "folio.activeByVault", "folio.recentsByVault"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("folio-missing-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for note in ["a.md", "b.md"] {
            try! "# \(note)".write(to: root.appendingPathComponent(note),
                                   atomically: true, encoding: .utf8)
        }
        return root.resolvingSymlinksInPath()
    }

    /// A store with both notes open in their own tabs and `b.md` active — the
    /// state the reported bug needs (you were reading the note that then died,
    /// and had since moved on to another tab).
    static func storeWithBothTabs() -> (VaultStore, a: URL, b: URL) {
        let root = vault()
        let store = VaultStore(vault: root)
        store.start()
        let a = store.files.first { $0.id.lastPathComponent == "a.md" }!.id
        let b = store.files.first { $0.id.lastPathComponent == "b.md" }!.id
        store.select(a)
        store.select(b, inNewTab: true)
        return (store, a, b)
    }

    /// Deletion by anything other than Folio: the file goes, then the watcher's
    /// refresh lands.
    static func deleteOutsideFolio(_ url: URL, _ store: VaultStore) {
        try! FileManager.default.removeItem(at: url)
        store.refresh()
    }

    // MARK: Tests

    /// THE REGRESSION. Reverting the `openTabs.contains(id)` half of `select`'s
    /// guard leaves every other test green and only this one red.
    @Test("Clicking the tab of a deleted note still opens it")
    func clickingAMissingTabSelectsIt() {
        let (store, a, b) = Self.storeWithBothTabs()
        Self.deleteOutsideFolio(a, store)

        #expect(store.openTabs == [a, b])      // the tab stays — the file may come back
        #expect(store.isMissing(a))
        #expect(!store.isMissing(b))

        store.select(a)

        #expect(store.selection == a)
        #expect(store.isSelectionMissing)
        #expect(store.content == "# a.md")     // the last version we read
    }

    /// The note stays on screen when it dies under you, rather than blanking or
    /// silently showing text that no longer matches any file.
    @Test("A note deleted while it is open stays readable and goes read-only")
    func deletedWhileActiveStaysReadable() {
        let (store, a, _) = Self.storeWithBothTabs()
        store.select(a)
        Self.deleteOutsideFolio(a, store)

        #expect(store.selection == a)
        #expect(store.content == "# a.md")
        #expect(store.isSelectionMissing)
    }

    /// The teeth behind "read-only": with no write target, no save path can put
    /// the file back. Folio is a reader — a deleted note must stay deleted.
    @Test("Editing a missing note never writes the file back to disk")
    func aMissingNoteIsNeverWrittenBack() {
        let (store, a, _) = Self.storeWithBothTabs()
        Self.deleteOutsideFolio(a, store)
        store.select(a)

        store.content += "\nedited after the file was deleted"
        store.contentEdited()
        store.flushSave()

        #expect(!FileManager.default.fileExists(atPath: a.path))
    }

    /// Reading-mode checkboxes are a write too.
    @Test("Toggling a task in a missing note changes nothing")
    func taskTogglesAreInertWhenMissing() {
        let root = Self.vault()
        let task = root.appendingPathComponent("task.md")
        try! "- [ ] ship it".write(to: task, atomically: true, encoding: .utf8)
        let store = VaultStore(vault: root)
        store.start()
        let url = store.files.first { $0.id.lastPathComponent == "task.md" }!.id
        store.select(url)
        Self.deleteOutsideFolio(url, store)

        store.toggleTask(atContentIndex: (store.content as NSString).range(of: " ").location)

        #expect(store.content == "- [ ] ship it")
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    /// Missing is a live fact about the disk, not a flag we latch: a note that
    /// comes back (Put Back from the Trash, a branch switched back, a sync
    /// catching up) becomes an ordinary note again, in the tab it never left.
    ///
    /// Checked **without navigating away**, which is the hard case: the note is
    /// the active one, so nothing re-runs `select`. Re-adopting it has to happen
    /// in the refresh, or the tab stops looking missing (Write comes back on)
    /// while still holding no write target — and every edit after that is lost.
    @Test("A note that reappears is writable again in place")
    func reappearingNoteHealsItself() {
        let (store, a, _) = Self.storeWithBothTabs()
        Self.deleteOutsideFolio(a, store)
        store.select(a)
        #expect(store.isSelectionMissing)

        try! "# a.md, restored".write(to: a, atomically: true, encoding: .utf8)
        store.refresh()

        #expect(!store.isMissing(a))
        #expect(store.openTabs.first == a)      // same tab, never closed
        #expect(store.content == "# a.md, restored")   // disk wins

        // …and edits land on disk again.
        store.content += "\nedited after it came back"
        store.contentEdited()
        store.flushSave()
        #expect(try! String(contentsOf: a, encoding: .utf8) == "# a.md, restored\nedited after it came back")
    }

    /// The watcher coalesces events, and suppresses same-process ones entirely
    /// (another Folio window's delete), so the index can still list a note that is
    /// already gone. The *read* has to be what decides, not the index: trusting
    /// `files` here blanked the pane, overwrote the cached text with "" and took a
    /// write target on a file that no longer existed.
    @Test("Clicking a note deleted before the refresh lands is still read-only")
    func deletionNotYetSeenByTheIndexIsStillMissing() {
        let (store, a, _) = Self.storeWithBothTabs()
        try! FileManager.default.removeItem(at: a)   // no refresh: the index still lists a.md
        #expect(!store.isMissing(a))

        store.select(a)

        #expect(store.selection == a)
        #expect(store.isSelectionMissing)          // decided by the failed read
        #expect(store.content == "# a.md")         // cache intact, not blanked

        store.content += "\nedited"
        store.contentEdited()
        store.flushSave()
        #expect(!FileManager.default.fileExists(atPath: a.path))
    }

    /// A save already in flight when the file goes away must not put it back.
    /// This is the debounce firing on its own — no `flushSave()` to cancel it.
    @Test("A debounced save that fires after the delete recreates nothing")
    func aPendingSaveNeverResurrectsTheFile() async throws {
        let (store, a, _) = Self.storeWithBothTabs()
        store.select(a)
        store.content += "\nedit that schedules a save"
        store.contentEdited()                       // 500ms debounce now running
        try! FileManager.default.removeItem(at: a)  // deleted while it runs

        try await Task.sleep(for: .milliseconds(900))

        #expect(!FileManager.default.fileExists(atPath: a.path))
        #expect(store.isSelectionMissing)           // and the UI now says so
    }

    /// Following `[[a]]` from another note creates the note when it's missing —
    /// that's Folio's create-on-miss — but it must not leave the tab showing
    /// cached text over a file that now exists.
    @Test("Recreating a missing note through a wikilink re-adopts its tab")
    func creatingAMissingNoteThroughALinkReadoptsIt() {
        let (store, a, _) = Self.storeWithBothTabs()
        Self.deleteOutsideFolio(a, store)
        store.select(a)
        #expect(store.isSelectionMissing)

        store.openWikilink("a")

        #expect(FileManager.default.fileExists(atPath: a.path))
        #expect(store.selection == a)
        #expect(!store.isSelectionMissing)     // no stale read-only state over a live file
        store.content = "written after the link recreated it"
        store.contentEdited()
        store.flushSave()
        #expect(try! String(contentsOf: a, encoding: .utf8) == "written after the link recreated it")
    }

    /// The cache is keyed by URL, like every other navigation structure a rename
    /// has to carry across — otherwise a note renamed in Folio and *then* deleted
    /// outside it shows "File not found" despite Folio having read its text.
    @Test("A rename carries the note's cached text to its new URL")
    func renameCarriesTheCachedText() {
        let (store, a, b) = Self.storeWithBothTabs()
        store.select(a)
        store.select(b)                        // a.md's text is now only in the cache
        store.rename(a, to: "c")
        let c = store.openTabs.first { $0.lastPathComponent == "c.md" }!
        Self.deleteOutsideFolio(c, store)

        store.select(c)

        #expect(store.isSelectionMissing)
        #expect(store.content == "# a.md")     // not the empty "File not found" state
    }

    /// A pending save must not outlive the file it was going to write, even when
    /// the deletion is *observed* while the debounce is still running. Left alive
    /// it recreates the note — or, if the path is taken over meanwhile, overwrites
    /// the new file with text from before the deletion.
    @Test("An observed deletion cancels the pending save, and the file that comes back wins")
    func anObservedDeletionCancelsThePendingSave() async throws {
        let (store, a, _) = Self.storeWithBothTabs()
        store.select(a)
        store.content += "\nedit from before the delete"
        store.contentEdited()                        // debounce running

        Self.deleteOutsideFolio(a, store)            // …and the refresh sees it go
        #expect(store.isSelectionMissing)

        try! "# a.md, replaced by something else".write(to: a, atomically: true, encoding: .utf8)
        store.refresh()
        try await Task.sleep(for: .milliseconds(900))

        #expect(try! String(contentsOf: a, encoding: .utf8) == "# a.md, replaced by something else")
        #expect(store.content == "# a.md, replaced by something else")
        #expect(!store.isSelectionMissing)
    }

    /// A path Folio can list but not read is not a note that came back. Re-adopting
    /// it would blank the pane, destroy the snapshot and hand back a write target
    /// over a file that does exist — so the next edit would overwrite it.
    @Test("A note that comes back unreadable stays missing")
    func unreadableReappearanceStaysMissing() {
        let (store, a, _) = Self.storeWithBothTabs()
        store.select(a)
        Self.deleteOutsideFolio(a, store)

        try! Data([0xFF, 0xFE, 0xFF]).write(to: a)   // listed, but not valid UTF-8
        store.refresh()

        #expect(store.isSelectionMissing)
        #expect(store.content == "# a.md")           // snapshot intact
        store.content += "\nedited"
        store.contentEdited()
        store.flushSave()
        #expect(try! Data(contentsOf: a) == Data([0xFF, 0xFE, 0xFF]))   // untouched
    }

    /// Renaming while a save is in flight: the debounced write captured the old
    /// URL, which the move then takes away. Without settling it first the edit is
    /// lost twice over — never written, then wiped from the editor by the reload
    /// that follows.
    @Test("A rename carries an unsaved edit to the new file")
    func renameCarriesAnUnsavedEdit() async throws {
        let (store, a, _) = Self.storeWithBothTabs()
        store.select(a)
        store.content += "\nunsaved when the rename happened"
        store.contentEdited()                        // debounce running

        store.rename(a, to: "c")
        try await Task.sleep(for: .milliseconds(900))

        let c = a.deletingLastPathComponent().appendingPathComponent("c.md")
        #expect(store.selection == c)
        #expect(!FileManager.default.fileExists(atPath: a.path))   // nothing resurrected
        #expect(try! String(contentsOf: c, encoding: .utf8)
                == "# a.md\nunsaved when the rename happened")
        #expect(store.content == "# a.md\nunsaved when the rename happened")
    }

    /// Detection can happen in `flushSave` rather than a refresh (iOS leaves the
    /// note screen this way, and its watcher is a stub). The missing state has to
    /// be complete either way, or the UI keeps offering an editor whose edits go
    /// nowhere.
    @Test("Detection through a flush marks the note missing too")
    func flushOnlyDetectionMarksMissing() {
        let (store, a, _) = Self.storeWithBothTabs()
        store.select(a)
        store.content += "\nedited"
        try! FileManager.default.removeItem(at: a)   // no refresh at all

        store.flushSave()

        #expect(store.isMissing(a))
        #expect(store.isSelectionMissing)
        #expect(!FileManager.default.fileExists(atPath: a.path))
    }

    /// Folio's own Move to Trash is unchanged: it closes the tab, so it never
    /// produces a missing tab in the window that did the deleting.
    @Test("Folio's own delete closes the tab instead")
    func inAppDeleteClosesTheTab() {
        let (store, a, b) = Self.storeWithBothTabs()
        store.delete(a)

        #expect(store.openTabs == [b])
        #expect(store.selection == b)
    }
}
#endif
