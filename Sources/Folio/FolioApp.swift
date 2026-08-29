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
        // Wire the coordinator's "give me one more window" action here, not from a
        // window's `.task`: `body` runs before any window exists, so the action is
        // available even on a launch that presents no scene (see the
        // `handlesExternalEvents` note below). Idempotent — `body` re-evaluates.
        let _ = { appDelegate.coordinator.openWindowAction = { [openWindow] in openWindow(id: "vault") } }()
        // A PLAIN WindowGroup. The value-typed variant cannot express this app's
        // lifecycle: windows acquire their vault *after* creation (launch, ⌘N, an
        // external open landing in the launch window), and there is no way to tell
        // SwiftUI about that afterwards. `WindowCoordinator` owns identity instead.
        WindowGroup(id: "vault") {
            VaultWindow(coordinator: appDelegate.coordinator, settings: settings)
        }
        // `VaultSession` is the only restore mechanism. Leaving AppKit's own
        // restoration on means two systems racing to decide how many windows
        // exist, which is unwinnable.
        .restorationBehavior(.disabled)
        // Files and folio:// URLs are handled by the AppDelegate
        // (`application(_:open:)`) and routed by the coordinator. Without this,
        // SwiftUI ALSO reacts to every external open by materializing a fresh
        // (vault-less) scene from this group — one ghost window per Finder/CLI
        // open, on top of whatever the coordinator decides to do. The measured
        // "one openWindow call yields two windows" was exactly this ghost.
        //
        // Side effect: a launch *caused by* a document open then presents no
        // scene at all (`.defaultLaunchBehavior(.presented)` does not override
        // it). The AppDelegate summons the launch window in that case — see
        // `applicationDidFinishLaunching`.
        .handlesExternalEvents(matching: [])
        // First-launch size: proportional to whichever display the window lands on
        // (laptop panel vs. big monitor get sensibly different frames), capped so a
        // 5K display doesn't produce a wall of text.
        .defaultWindowPlacement { _, context in
            let visible = context.defaultDisplay.visibleRect
            return WindowPlacement(size: CGSize(
                width: min(1500, visible.width * 0.80),
                height: min(1000, visible.height * 0.88)))
        }
        .windowStyle(.hiddenTitleBar)
        .commands { FolioCommands(settings: settings, coordinator: appDelegate.coordinator) }
    }
}

/// Behave as a regular foreground app even when launched unbundled via `swift run`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Windows, routing and the session all live in the coordinator. Created here
    /// so it exists before any scene body runs.
    @MainActor private static let sharedCoordinator = WindowCoordinator()
    @MainActor var coordinator: WindowCoordinator { Self.sharedCoordinator }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        configureAppIcon()
        NSApp.activate(ignoringOtherApps: true)
        // With the WindowGroup opted out of external events, a launch triggered
        // BY a document/URL open presents no window at all (SwiftUI treats the
        // launch as event-driven and finds no scene willing to take the event).
        // On a normal launch the window is already up before this notification
        // fires — measured — so an empty window list here means exactly that
        // case: summon the launch window, whose `.task` runs the coordinator's
        // bootstrap and releases the buffered open.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if NSApp.windows.isEmpty { self.coordinator.openWindowAction?() }
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { coordinator.applicationWillTerminate() }
    }

    // MARK: - Dock menu (recent notes + vaults)

    /// Right-click / long-press the Dock icon. Built fresh each time so it always
    /// reflects the current recents. Sections that would be empty are omitted, and
    /// a wholly empty menu returns nil (no reference to the store yet, or a fresh
    /// launch with no history).
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let store = MainActor.assumeIsolated({ coordinator.keyStore }) else { return nil }
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
        coordinator.keyStore?.select(url)
    }

    @MainActor @objc private func openRecentVault(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL,
              FileManager.default.fileExists(atPath: url.path) else { NSSound.beep(); return }
        coordinator.open(VaultRef(url))   // a vault opens a window; it never replaces one
    }

    /// The single AppKit entry point for both Finder double-clicks / `open -a Folio`
    /// (file URLs) and `folio://` deep links. URLs can arrive before the window
    /// exists (open-at-launch), so buffer until `urlHandler` is wired.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { coordinator.handleExternal(urls) }
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
