import SwiftUI
import AppKit

@main
struct FolioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    /// App-wide, unlike the vault and UI state: appearance belongs to the person,
    /// not the window.
    @StateObject private var settings = AppSettings()

    init() {
        // Use thin, auto-hiding overlay scrollbars everywhere, regardless of the
        // system "Show scroll bars" setting. The app's own defaults domain takes
        // precedence over the global one, so this also overrides "Always".
        UserDefaults.standard.set("WhenScrolling", forKey: "AppleShowScrollBars")
        // No inline prediction UI anywhere in the app — palette/search fields are
        // queries, not prose, and the candidate bar is the "phantom dropdown"
        // that flashed over the first palette after launch.
        UserDefaults.standard.set(false, forKey: "NSAutomaticInlinePredictionEnabled")
    }

    var body: some Scene {
        // One window per vault (Obsidian's model). The stores moved into
        // `VaultWindow` so each window is an independent workspace; keeping them
        // here is what made a second window a mirror of the first.
        // No `defaultValue`: a nil ref means "no vault named", which the store
        // reads as "reopen the last one, or show the empty state". Naming a
        // fallback folder here is a trap — pointing it at the home directory sends
        // the store off to scan all of ~.
        WindowGroup(for: VaultRef.self) { $ref in
            VaultWindow(ref: $ref, settings: settings, appDelegate: appDelegate)
                .onAppear {
                    VaultWindows.delegate = appDelegate
                    appDelegate.openWindow = { VaultWindows.open($0, using: openWindow) }
                    appDelegate.flushPendingOpens()
                }
        }
        // First-launch size: proportional to whichever display the window lands on
        // (laptop panel vs. big monitor get sensibly different frames), capped so a
        // 5K display doesn't produce a wall of text. Once the user resizes, the
        // system restores their frame and this never runs again.
        .defaultWindowPlacement { _, context in
            let visible = context.defaultDisplay.visibleRect
            return WindowPlacement(size: CGSize(
                width: min(1500, visible.width * 0.80),
                height: min(1000, visible.height * 0.88)))
        }
        .windowStyle(.hiddenTitleBar)
        .commands { FolioCommands(settings: settings) }
        // No Settings scene: SettingsView presents as an in-window overlay
        // (ContentView.paletteOverlay) via the ⌘, command in FolioCommands.
    }
}

/// Behave as a regular foreground app even when launched unbundled via `swift run`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Every open window's store, weakly held (SwiftUI owns them). External opens
    /// are routed against this: a file goes to the window whose vault contains it,
    /// never to whichever window happens to be frontmost.
    private var stores: [WeakStore] = []
    private struct WeakStore { weak var store: VaultStore? }
    /// vault store → its window, so a vault can be brought forward instead of
    /// opened again. SwiftUI's own value-matching can't do this for us: a window
    /// opened without a value (launch, ⌘N) settles on its vault *afterwards*, and
    /// writing that vault back into the scene value opens another window rather
    /// than re-tagging this one.
    private var windows: [ObjectIdentifier: NSWindow] = [:]

    @MainActor func attach(_ window: NSWindow, to store: VaultStore) {
        windows[ObjectIdentifier(store)] = window
    }

    /// Bring the window already showing this vault to the front. Returns false if
    /// no window holds it, in which case the caller should open one.
    @MainActor func focus(vault ref: VaultRef) -> Bool {
        guard let store = stores.compactMap(\.store).first(where: {
            guard let url = $0.vaultURL else { return false }
            return VaultRef(url) == ref
        }), let window = windows[ObjectIdentifier(store)] else { return false }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    /// Opens a window for a vault, focusing an existing one if there is a match.
    var openWindow: ((VaultRef) -> Void)?
    /// URLs that arrived before any window existed (open-at-launch).
    private var bufferedURLs: [URL] = []

    @MainActor func register(_ store: VaultStore) {
        stores.removeAll { $0.store == nil }
        if !stores.contains(where: { $0.store === store }) { stores.append(WeakStore(store: store)) }
        claimPendingFiles(for: store)
        flushPendingOpens()
    }

    @MainActor func unregister(_ store: VaultStore) {
        windows.removeValue(forKey: ObjectIdentifier(store))
        stores.removeAll { $0.store == nil || $0.store === store }
    }

    /// The most recently registered live store — the fallback for window-less
    /// actions like the Dock menu.
    @MainActor var store: VaultStore? { stores.compactMap(\.store).last }

    @MainActor func flushPendingOpens() {
        guard !bufferedURLs.isEmpty, !stores.isEmpty else { return }
        let pending = bufferedURLs
        bufferedURLs = []
        route(pending)
    }

    /// Send each URL to the window that owns it.
    ///
    /// A file inside an open vault goes to that window; otherwise a window opens
    /// for the vault that contains it. Nothing ever swaps the vault under a window
    /// that is showing something else — the rule that made "open a note" able to
    /// close the vault you were reading.
    @MainActor func route(_ urls: [URL]) {
        for url in urls {
            if url.isFileURL, let owner = window(owning: url) {
                owner.handleExternal(urls: [url])
            } else if url.isFileURL, let empty = stores.compactMap(\.store).first(where: { $0.vaultURL == nil }) {
                // A window with no vault yet (fresh launch) takes the file rather
                // than sitting empty beside a new window.
                empty.handleExternal(urls: [url])
            } else if url.isFileURL {
                let vault = VaultResolver.vault(for: url)
                openWindow?(VaultRef(vault))
                // The window opens asynchronously; hand it the file once it exists.
                pendingFileOpens.append(url)
            } else if let store = store {
                store.handleExternal(urls: [url])   // folio:// links carry their own vault
            } else {
                bufferedURLs.append(url)
            }
        }
    }

    /// Files waiting for the window that will show them to finish opening.
    private var pendingFileOpens: [URL] = []

    /// A newly registered store claims any queued file that belongs to it.
    @MainActor private func claimPendingFiles(for store: VaultStore) {
        guard !pendingFileOpens.isEmpty, let root = store.vaultURL else { return }
        let mine = pendingFileOpens.filter { $0.path.hasPrefix(root.resolvingSymlinksInPath().path) }
        guard !mine.isEmpty else { return }
        pendingFileOpens.removeAll { mine.contains($0) }
        store.handleExternal(urls: mine)
    }

    @MainActor private func window(owning url: URL) -> VaultStore? {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return stores.compactMap(\.store).first { store in
            guard let root = store.vaultURL?.resolvingSymlinksInPath().standardizedFileURL.path
            else { return false }
            return path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
        }
    }



    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        configureAppIcon()
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: - Dock menu (recent notes + vaults)

    /// Right-click / long-press the Dock icon. Built fresh each time so it always
    /// reflects the current recents. Sections that would be empty are omitted, and
    /// a wholly empty menu returns nil (no reference to the store yet, or a fresh
    /// launch with no history).
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let store else { return nil }
        let menu = NSMenu()

        // Recents can go stale (file trashed, vault folder moved since) — a Dock
        // click on a ghost would beep or open nothing, so filter here at build time
        // (the handlers re-check on click as the last line of defense).
        let notes = Array(store.recentFiles
            .filter { FileManager.default.fileExists(atPath: $0.path) }.prefix(5))
        if !notes.isEmpty {
            menu.addItem(header("Recent Notes"))
            for url in notes {
                menu.addItem(dockItem(title: (url.lastPathComponent as NSString).deletingPathExtension,
                                      url: url, action: #selector(openRecentNote(_:))))
            }
        }

        // Skip the vault already open — switching to it would be a no-op.
        let vaults = store.recentVaults
            .filter { $0.standardizedFileURL.path != store.vaultURL?.standardizedFileURL.path }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .prefix(5)
        if !vaults.isEmpty {
            if !notes.isEmpty { menu.addItem(.separator()) }
            menu.addItem(header("Recent Vaults"))
            for url in vaults {
                menu.addItem(dockItem(title: url.lastPathComponent,
                                      url: url, action: #selector(openRecentVault(_:))))
            }
        }
        return menu.items.isEmpty ? nil : menu
    }

    /// A disabled, dimmed label acting as a section heading in the Dock menu.
    private func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func dockItem(title: String, url: URL, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = url
        return item
    }

    // Dock menu actions fire on the main thread, so touching the MainActor store
    // directly is safe. Recent notes are per-vault, so the note is in the open
    // vault and `select` resolves it.
    @MainActor @objc private func openRecentNote(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL,
              FileManager.default.fileExists(atPath: url.path) else { NSSound.beep(); return }
        store?.select(url)
    }

    @MainActor @objc private func openRecentVault(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL,
              FileManager.default.fileExists(atPath: url.path) else { NSSound.beep(); return }
        openWindow?(VaultRef(url))   // a vault opens a window; it never replaces one
    }

    /// The single AppKit entry point for both Finder double-clicks / `open -a Folio`
    /// (file URLs) and `folio://` deep links. URLs can arrive before the window
    /// exists (open-at-launch), so buffer until `urlHandler` is wired.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            if stores.isEmpty { bufferedURLs.append(contentsOf: urls) } else { route(urls) }
        }
    }

    private func configureAppIcon() {
        let bundledIcon = Bundle.main.url(forResource: "Folio", withExtension: "icns")
        let sourceIcon = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/AppIcon/FolioAppIcon-mac.png")

        for url in [bundledIcon, sourceIcon].compactMap({ $0 }) {
            if let image = NSImage(contentsOf: url) {
                NSApp.applicationIconImage = image
                return
            }
        }
    }
}
