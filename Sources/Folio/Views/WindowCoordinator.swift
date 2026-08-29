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
@MainActor
final class WindowCoordinator {
    private struct Entry {
        weak var store: VaultStore?
        weak var window: NSWindow?
    }

    private var entries: [Entry] = []
    /// Vaults waiting for a window that is being born. Enqueued by `open`,
    /// dequeued exactly once per window by `claimPendingVault`.
    private var pendingVaults: [VaultRef] = []
    /// Files whose window is still opening.
    private var pendingFiles: [URL] = []
    /// External opens that arrived before any window existed.
    private var bufferedURLs: [URL] = []
    private var didBootstrap = false
    private var isTerminating = false

    /// Asks SwiftUI for one more window. Set once a window exists.
    var openWindowAction: (() -> Void)?

    init() {
        // Seed from the previous session; migrate the pre-multi-window key.
        var session = VaultSession.openVaults
        if session.isEmpty,
           let legacy = VaultRef(path: UserDefaults.standard.string(forKey: "folio.vaultPath")),
           legacy.exists {
            session = [legacy]
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

    func register(_ store: VaultStore) {
        entries.removeAll { $0.store == nil }
        if !entries.contains(where: { $0.store === store }) {
            entries.append(Entry(store: store, window: nil))
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
            forName: NSWindow.willCloseNotification, object: window, queue: .main
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
        if let entry = entries.first(where: { $0.store?.vaultURL.map(VaultRef.init) == ref }) {
            entry.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        if let empty = entries.compactMap(\.store).first(where: { $0.vaultURL == nil }) {
            empty.adopt(ref.url)
            entries.first { $0.store === empty }?.window?.makeKeyAndOrderFront(nil)
            return
        }
        pendingVaults.append(ref)
        trace("open -> NEW WINDOW for \(ref.name)")
        openWindowAction?()
    }

    func openEmptyWindow() { openWindowAction?() }

    // MARK: Launch

    /// Runs once, from the first window's `.task`: open the rest of the session,
    /// then release anything that arrived before we were ready.
    func bootstrapIfNeeded() {
        guard !didBootstrap else { return }
        didBootstrap = true
        let remaining = pendingVaults
        trace("bootstrap opening \(remaining.count) extra")
        for _ in remaining { openWindowAction?() }
        let buffered = bufferedURLs
        bufferedURLs = []
        if !buffered.isEmpty { handleExternal(buffered) }
    }

    // MARK: External opens

    private func trace(_ m: String) {   // TEMP
        let l = "TRACE \(m)\n"
        if let h = try? FileHandle(forWritingTo: URL(fileURLWithPath: "/tmp/folio-mw.log")) { h.seekToEndOfFile(); h.write(Data(l.utf8)); try? h.close() }
        else { try? l.write(to: URL(fileURLWithPath: "/tmp/folio-mw.log"), atomically: true, encoding: .utf8) }
    }

    func handleExternal(_ urls: [URL]) {
        trace("handleExternal \(urls.map(\.lastPathComponent)) bootstrap=\(didBootstrap)")
        guard didBootstrap else { bufferedURLs.append(contentsOf: urls); return }
        for url in urls {
            guard url.isFileURL else {
                // folio:// carries its own vault; route it to that vault's window.
                if let (vault, _) = VaultResolver.destination(for: url) {
                    open(VaultRef(vault))
                    pendingFiles.append(url)
                } else {
                    keyStore?.handleExternal(urls: [url])
                }
                continue
            }
            if let owner = window(owning: url) {
                owner.store.handleExternal(urls: [url])
                owner.window?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            } else if let empty = entries.compactMap(\.store).first(where: { $0.vaultURL == nil }) {
                empty.handleExternal(urls: [url])
            } else {
                pendingFiles.append(url)
                open(VaultRef(VaultResolver.vault(for: url)))
            }
        }
    }

    /// Hand a newly-loaded window any queued file that belongs to it.
    private func claimFiles(for store: VaultStore) {
        guard !pendingFiles.isEmpty, let root = store.vaultURL else { return }
        let bounded = Self.boundary(root)
        let mine = pendingFiles.filter { Self.normalized($0).hasPrefix(bounded) }
        guard !mine.isEmpty else { return }
        pendingFiles.removeAll { mine.contains($0) }
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
    var keyStore: VaultStore? {
        if let key = NSApp.keyWindow,
           let entry = entries.first(where: { $0.window === key }) { return entry.store }
        return entries.compactMap(\.store).last
    }

    var openVaultCount: Int { entries.count }
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
