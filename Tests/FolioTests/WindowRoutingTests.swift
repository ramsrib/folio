#if os(macOS)
import AppKit
import Foundation
import Testing
@testable import Folio

/// Where an external open actually *lands* — the half `DeepLinkRoutingTests`
/// can't see. These drive `WindowCoordinator` with stand-in windows and assert on
/// the stores, so they catch what parsing tests cannot: a link that parses
/// perfectly and is then routed to the wrong window, or to none at all.
///
/// The original regression is `cliLinkReachesTheOpenVault`: deleting the
/// vault-less branch in `handleExternal` leaves every parsing test green and only
/// this one red.
///
/// Serialized: the coordinator, `VaultSession` and the recents list all live in
/// `UserDefaults.standard`, which is process-wide.
@MainActor
@Suite("Window routing", .serialized)
struct WindowRoutingTests {

    // MARK: Harness

    /// Plays the part of SwiftUI's `WindowGroup`: each "window" is a `VaultStore`
    /// created and registered exactly as `VaultWindow` does it (claim in init,
    /// `start()` then `register` in `.task`). Windows stay `nil` — the coordinator
    /// treats that as a window not yet attached, which is a real state.
    @MainActor
    final class Windows {
        let coordinator = WindowCoordinator()
        private(set) var stores: [VaultStore] = []

        init() {
            coordinator.openWindowAction = { [unowned self] in _ = materialize() }
        }

        @discardableResult
        func materialize() -> VaultStore {
            let claim = coordinator.claimPendingVault()
            let store = VaultStore(vault: claim?.url)
            stores.append(store)
            store.start()
            coordinator.register(store, claimed: claim)
            coordinator.bootstrapIfNeeded()
            return store
        }

        /// The window holding this vault, by the only thing a test can see.
        func store(for vault: URL) -> VaultStore? {
            stores.first { $0.vaultURL.map(VaultRef.init) == VaultRef(vault) }
        }
    }

    /// `NSApp` is an implicitly-unwrapped global; `handleExternal` calls
    /// `activate` on it. Nothing here shows a window — this just makes the
    /// instance exist.
    static func makeApp() { _ = NSApplication.shared }

    /// A vault on disk with the given notes, plus a clean slate in the shared
    /// defaults (recents, session, per-vault tabs) so tests don't inherit each
    /// other's state — or the developer's real one.
    static func vault(_ notes: [String], recents: [URL] = []) -> URL {
        makeApp()
        for key in ["folio.recentVaults", "folio.openVaults", "folio.vaultPath",
                    "folio.tabs", "folio.recentFiles", "folio.didMigrateSingleVault"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("folio-routing-\(UUID().uuidString)")
        for note in notes {
            let file = root.appendingPathComponent(note)
            try! FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try! "# \(note)".write(to: file, atomically: true, encoding: .utf8)
        }
        UserDefaults.standard.set(recents.map(\.path), forKey: "folio.recentVaults")
        return root.resolvingSymlinksInPath()
    }

    /// The note as the *index* spells it. `contentsOfDirectory` hands back
    /// `/private/var/…` while `resolvingSymlinksInPath()` strips `/private`, so a
    /// hand-built URL is not the one in `files` — the very mismatch
    /// `selectResolved` exists to absorb. Tests select the indexed URL, as the
    /// explorer does.
    static func indexed(_ store: VaultStore, _ name: String) -> URL {
        store.files.first { $0.id.lastPathComponent == name }!.id
    }

    static func cliLink(_ file: URL) -> URL {
        // Exactly what the shim builds: absolute path, fully percent-encoded.
        URL(string: "folio://open?file=" +
            file.path.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)!
    }

    // MARK: Tests

    /// THE REGRESSION. `folio <file>` on a vault that is already open.
    @Test("A CLI link lands in the window holding its vault, as a new tab")
    func cliLinkReachesTheOpenVault() {
        let root = Self.vault(["a.md", "b.md"])
        let w = Windows()
        w.coordinator.open(VaultRef(root))
        let store = try! #require(w.store(for: root))
        store.select(Self.indexed(store, "a.md"))

        w.coordinator.handleExternal([Self.cliLink(root.appendingPathComponent("b.md"))])

        #expect(w.stores.count == 1)                  // no second window conjured
        #expect(store.selection?.lastPathComponent == "b.md")
        #expect(store.openTabs.map(\.lastPathComponent) == ["a.md", "b.md"])
    }

    /// An open note is never evicted, and never duplicated.
    @Test("An already-open note activates its tab")
    func alreadyOpenNoteActivatesItsTab() {
        let root = Self.vault(["a.md", "b.md"])
        let w = Windows()
        w.coordinator.open(VaultRef(root))
        let store = try! #require(w.store(for: root))
        store.select(Self.indexed(store, "a.md"))
        store.select(Self.indexed(store, "b.md"), inNewTab: true)

        w.coordinator.handleExternal([Self.cliLink(root.appendingPathComponent("a.md"))])

        #expect(store.selection?.lastPathComponent == "a.md")
        #expect(store.openTabs.map(\.lastPathComponent) == ["a.md", "b.md"])
    }

    /// The empty window must take the vault the *router* resolved. It snapshots
    /// recents at init, so a window that has sat empty since before the vault was
    /// last opened resolves the same file differently — landing the note under
    /// `sub/` while the coordinator records the window as holding the root.
    @Test("An empty window adopts the vault the router chose, not its own stale guess")
    func emptyWindowAdoptsRoutedVault() {
        let root = Self.vault(["sub/a.md"])            // recents deliberately empty
        let w = Windows()
        w.materialize()                                // born knowing no vaults
        UserDefaults.standard.set([root.path], forKey: "folio.recentVaults")

        w.coordinator.handleExternal([Self.cliLink(root.appendingPathComponent("sub/a.md"))])

        let store = try! #require(w.stores.first)
        #expect(store.vaultURL.map(VaultRef.init) == VaultRef(root))
        #expect(store.selection?.lastPathComponent == "a.md")
        #expect(w.stores.count == 1)
    }

    /// A cold `folio <file>`: the URL arrives before any window exists, is
    /// buffered, and is released by the first window's bootstrap.
    @Test("A link arriving before bootstrap is not lost")
    func linkBufferedBeforeBootstrapIsDelivered() {
        let root = Self.vault(["a.md"], recents: [])
        let w = Windows()
        w.coordinator.handleExternal([Self.cliLink(root.appendingPathComponent("a.md"))])
        #expect(w.stores.isEmpty)                      // nothing to deliver to yet

        w.materialize()                                // the launch window bootstraps

        let store = try! #require(w.stores.first)
        #expect(store.selection?.lastPathComponent == "a.md")
        #expect(store.vaultURL.map(VaultRef.init) == VaultRef(root))
    }

    /// Routing is not free: a link the store will only beep at must not conjure a
    /// window or claim an idle one, or the user gets an empty window for a vault
    /// with nothing to show.
    @Test("Links the store would reject never touch window state", arguments: [
        "txt", "missing", "host",
    ])
    func unopenableLinksLeaveWindowsAlone(_ kind: String) {
        let root = Self.vault(["a.md"])
        try! "hi".write(to: root.appendingPathComponent("readme.txt"),
                        atomically: true, encoding: .utf8)
        let w = Windows()
        w.materialize()                                // one empty window, unclaimed

        let url: URL
        switch kind {
        case "txt":     url = Self.cliLink(root.appendingPathComponent("readme.txt"))
        case "missing": url = Self.cliLink(root.appendingPathComponent("gone.md"))
        default:        url = URL(string: "folio://wrong?file=" + root
                                    .appendingPathComponent("a.md").path
                                    .addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)!
        }
        w.coordinator.handleExternal([url])

        #expect(w.stores.count == 1)
        #expect(w.stores.first?.vaultURL == nil)       // still empty, still unclaimed
    }

    /// The shim sends one URL per file; AppKit can also deliver them as one batch.
    @Test("A batch of files opens as tabs in the one window")
    func batchOpensAsTabs() {
        let root = Self.vault(["a.md", "b.md", "c.md"])
        let w = Windows()
        w.coordinator.open(VaultRef(root))

        w.coordinator.handleExternal(["a.md", "b.md", "c.md"].map {
            Self.cliLink(root.appendingPathComponent($0))
        })

        let store = try! #require(w.store(for: root))
        #expect(w.stores.count == 1)
        #expect(store.openTabs.map(\.lastPathComponent) == ["a.md", "b.md", "c.md"])
    }
}
#endif
