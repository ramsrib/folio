#if os(macOS)
import SwiftUI
import AppKit

/// Owns everything about windows: which vault each one holds, which vault a
/// newborn window should claim, and the session.
///
/// SwiftUI's job is reduced to "materialize one more generic window when asked".
/// All identity, dedupe and routing live here, because the scene system cannot do
/// it for us: a window opened without a vault (launch, ⌘N) acquires one
/// *afterwards*, and there is no way to tell SwiftUI about that after the fact.
///
/// Deliberately **not** an `ObservableObject`. It is mutated from a `StateObject`
/// autoclosure and from `viewDidMoveToWindow` — i.e. mid-view-update — where
/// publishing a change would re-enter SwiftUI's update cycle. (That re-entrancy
/// is what made an earlier version hang before any window appeared.)
/// ## The ordering contract (read this before changing anything here)
///
/// A window reports itself in two steps that can arrive in **either order**:
///
/// 1. `claimPendingVault()` — in the `StateObject` autoclosure, before the window
///    exists. Destructive: it removes a vault from the queue.
/// 2. `register(_:claimed:)` — from `.task`, after `start()` has loaded the vault.
/// 3. `attach(_:to:)` — from `viewDidMoveToWindow`, which may fire **before**
///    `.task`, i.e. before `register`.
///
/// So a store can be in `entries` with `vaultURL == nil` while already owning a
/// vault it claimed at birth. That is why `Entry.claimed` exists and why every
/// "is this window empty?" test checks it: without it, such a window looks free,
/// gets handed another vault, and the vault it claimed is lost with no window to
/// show it.
///
/// Likewise `open(_:)` must consider vaults already *requested* but not yet
/// registered (`pendingVaults`), because `openWindowAction` is asynchronous.
@MainActor
final class WindowCoordinator {
    private struct Entry {
        weak var store: VaultStore?
        weak var window: NSWindow?
        /// What this window claimed at birth. `attach` can run before `.task`, so
        /// a store can be registered while `vaultURL` is still nil even though it
        /// already owns a vault — without this, such a window looks "empty" and
        /// gets handed someone else's vault, discarding its own.
        var claimed: VaultRef?
    }

    private var entries: [Entry] = []
    /// Vaults waiting for a window that is being born. Enqueued by `open`,
    /// dequeued exactly once per window by `claimPendingVault`.
    private var pendingVaults: [VaultRef] = []
    /// Opens waiting on a window that is still being born, each tagged with the
    /// vault it belongs to. Tagging (rather than matching paths at claim time) is
    /// what lets a `folio://` link queue alongside a plain file.
    private var pendingOpens: [(url: URL, ref: VaultRef)] = []
    /// External opens that arrived before any window existed.
    private var bufferedURLs: [URL] = []
    private var didBootstrap = false
    private var isTerminating = false

    /// Asks SwiftUI for one more window. Set once a window exists.
    var openWindowAction: (() -> Void)?

    init() {
        // Seed from the previous session; migrate the pre-multi-window key.
        var session = VaultSession.openVaults
        // One-shot: gating on an empty session alone would re-fire on any launch
        // where nothing was open, resurrecting whatever vault was last touched.
        let migrationKey = "folio.didMigrateSingleVault"
        if session.isEmpty, !UserDefaults.standard.bool(forKey: migrationKey) {
            UserDefaults.standard.set(true, forKey: migrationKey)
            if let legacy = VaultRef(path: UserDefaults.standard.string(forKey: "folio.vaultPath")),
               legacy.exists {
                session = [legacy]
            }
        }
        pendingVaults = session
    }

    // MARK: Window birth & death

    /// Called from the window's `StateObject` autoclosure — exactly once per
    /// window, before it is on screen. Any window-creation path we don't control
    /// (⌘N, a system restore) simply gets `nil` and shows the empty state, which
    /// is why this degrades safely.
    func claimPendingVault() -> VaultRef? {
        pendingVaults.isEmpty ? nil : pendingVaults.removeFirst()
    }

    func register(_ store: VaultStore, claimed: VaultRef?) {
        entries.removeAll { $0.store == nil }
        if let i = entries.firstIndex(where: { $0.store === store }) {
            if entries[i].claimed == nil { entries[i].claimed = claimed }
        } else {
            entries.append(Entry(store: store, window: nil, claimed: claimed))
        }
        if let url = store.vaultURL { VaultSession.opened(VaultRef(url)) }
        claimFiles(for: store)
    }

    /// From `WindowBinder`. Idempotent: `viewDidMoveToWindow` can fire more than once.
    func attach(_ window: NSWindow, to store: VaultStore) {
        guard let i = entries.firstIndex(where: { $0.store === store }) else {
            entries.append(Entry(store: store, window: window))
            observeClose(window)
            return
        }
        guard entries[i].window !== window else { return }
        entries[i].window = window
        observeClose(window)
        // Per-vault frame memory, keyed by identity we control rather than by a
        // scene session — it survives with state restoration switched off.
        if let url = store.vaultURL {
            window.setFrameAutosaveName("folio-vault:\(VaultRef(url).path)")
        }
    }

    private func observeClose(_ window: NSWindow) {
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: nil
        ) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated { self?.windowWillClose(window) }
        }
    }

    private func windowWillClose(_ window: NSWindow) {
        guard let i = entries.firstIndex(where: { $0.window === window }) else { return }
        let ref = entries[i].store?.vaultURL.map(VaultRef.init)
        entries.remove(at: i)
        // Closing the last window quits; keep that vault in the session so the
        // next launch reopens it. Quitting keeps everything for the same reason.
        if let ref, !isTerminating, !entries.isEmpty { VaultSession.closed(ref) }
    }

    func applicationWillTerminate() { isTerminating = true }

    // MARK: The single "open a vault" entry point

    /// Focus the window already showing this vault, fill an empty one, or open a
    /// new window. Every caller — menu, switcher, palette, Dock, external open —
    /// comes through here, so the one-window-per-vault rule lives in one place.
    func open(_ ref: VaultRef) {
        if let entry = entry(holding: ref) {
            if entry.window?.isMiniaturized == true { entry.window?.deminiaturize(nil) }
            entry.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        // A window for this vault may already be *in flight*: `openWindowAction`
        // is async, so the window registers many runloop turns later. Without
        // this, opening two files from one vault in a single batch queues it
        // twice and materializes two windows for it.
        guard !pendingVaults.contains(ref) else { return }
        if let i = entries.firstIndex(where: { $0.store?.vaultURL == nil && $0.claimed == nil }),
           let empty = entries[i].store {
            entries[i].claimed = ref
            empty.adopt(ref.url)
            entries[i].window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        pendingVaults.append(ref)
        openWindowAction?()
    }

    /// The window showing this vault, by claim or by loaded vault — a window that
    /// has claimed but not yet started still owns its vault.
    private func entry(holding ref: VaultRef) -> Entry? {
        entries.first { $0.store?.vaultURL.map(VaultRef.init) == ref || $0.claimed == ref }
    }

    func openEmptyWindow() { openWindowAction?() }

    // MARK: Launch

    /// Runs once, from the first window's `.task`: open the rest of the session,
    /// then release anything that arrived before we were ready.
    func bootstrapIfNeeded() {
        guard !didBootstrap else { return }
        didBootstrap = true
        // Clear as we request: the buffer drain below runs in this same turn, and
        // a still-populated queue would make it re-request vaults already in flight.
        let remaining = pendingVaults
        pendingVaults = []
        for ref in remaining { pendingVaults.append(ref); openWindowAction?() }
        let buffered = bufferedURLs
        bufferedURLs = []
        if !buffered.isEmpty { handleExternal(buffered) }
    }

    // MARK: External opens

    func handleExternal(_ urls: [URL]) {
        guard didBootstrap else { bufferedURLs.append(contentsOf: urls); return }
        for url in urls {
            // Which vault does this open belong to? A folio:// link names its own;
            // a file is resolved against the open/recent vaults.
            let ref: VaultRef
            if url.isFileURL {
                ref = window(owning: url).map { VaultRef($0.store.vaultURL!) }
                    ?? VaultRef(VaultResolver.vault(for: url))
            } else if let (vault, _) = VaultResolver.destination(for: url),
                      VaultRef(vault).exists {
                ref = VaultRef(vault)
            } else {
                // A folio:// link with no resolvable vault. Handing it to some
                // window would make that window swap vaults — the single-window
                // behaviour this feature exists to remove.
                NSSound.beep()
                continue
            }

            if let entry = entries.first(where: { $0.store?.vaultURL.map(VaultRef.init) == ref }),
               let store = entry.store {
                // The window exists: hand it the open directly. Queuing here would
                // strand it, since the queue only drains when a *new* store registers.
                store.handleExternal(urls: [url])
                entry.window?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            } else if let i = entries.firstIndex(where: { $0.store?.vaultURL == nil && $0.claimed == nil }),
                      let empty = entries[i].store {
                entries[i].claimed = ref
                empty.handleExternal(urls: [url])
                entries[i].window?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            } else {
                pendingOpens.append((url, ref))
                open(ref)
            }
        }
    }

    /// Hand a newly-loaded window whatever was queued for its vault.
    private func claimFiles(for store: VaultStore) {
        guard !pendingOpens.isEmpty, let root = store.vaultURL else { return }
        let ref = VaultRef(root)
        let mine = pendingOpens.filter { $0.ref == ref }.map(\.url)
        guard !mine.isEmpty else { return }
        pendingOpens.removeAll { $0.ref == ref }
        store.handleExternal(urls: mine)
    }

    private func window(owning url: URL) -> (store: VaultStore, window: NSWindow?)? {
        let path = Self.normalized(url)
        for entry in entries {
            guard let store = entry.store, let root = store.vaultURL else { continue }
            if path.hasPrefix(Self.boundary(root)) { return (store, entry.window) }
        }
        return nil
    }

    /// The trailing separator matters: without it `/notes/vault` claims a file in
    /// `/notes/vault2`, and the wrong window grabs it.
    private static func boundary(_ root: URL) -> String {
        let path = normalized(root)
        return path.hasSuffix("/") ? path : path + "/"
    }

    private static func normalized(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    // MARK: Lookups

    /// The store of the front window — what window-less actions (the Dock menu)
    /// should act on.
    /// True until the first window has bootstrapped — the launch heuristic keys
    /// off this rather than `NSApp.windows`, which is non-empty for panels and
    /// SwiftUI's own hosts and would silently leave the app running with no UI.
    var needsLaunchWindow: Bool { entries.isEmpty && !didBootstrap }

    var keyStore: VaultStore? {
        if let key = NSApp.keyWindow,
           let entry = entries.first(where: { $0.window === key }) { return entry.store }
        return entries.compactMap(\.store).last
    }

}

private struct WindowCoordinatorKey: EnvironmentKey {
    static let defaultValue: WindowCoordinator? = nil
}

extension EnvironmentValues {
    /// The app's window coordinator, so views (the vault switcher, the command
    /// palette) can open vaults through the one entry point.
    var windowCoordinator: WindowCoordinator? {
        get { self[WindowCoordinatorKey.self] }
        set { self[WindowCoordinatorKey.self] = newValue }
    }
}

/// Reports the hosting `NSWindow` the moment the view enters the window
/// hierarchy. `viewDidMoveToWindow` fires synchronously at exactly the right
/// time; polling `view.window` on the next runloop turn is a race.
struct WindowBinder: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    final class BinderView: NSView {
        var onWindow: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow?(window) }   // also fires with nil on teardown
        }
    }

    func makeNSView(context: Context) -> BinderView {
        let view = BinderView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: BinderView, context: Context) { nsView.onWindow = onWindow }
}
#endif
