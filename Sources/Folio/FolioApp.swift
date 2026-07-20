import SwiftUI
import AppKit

@main
struct FolioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var vault = VaultStore()
    @StateObject private var ui = UIState()
    @StateObject private var settings = AppSettings()

    init() {
        // Use thin, auto-hiding overlay scrollbars everywhere, regardless of the
        // system "Show scroll bars" setting. The app's own defaults domain takes
        // precedence over the global one, so this also overrides "Always".
        UserDefaults.standard.set("WhenScrolling", forKey: "AppleShowScrollBars")
    }

    var body: some Scene {
        // A single `Window` scene, deliberately: the vault/tab state is one shared
        // @StateObject, so a WindowGroup's extra windows were *mirrors* of the same
        // store (navigate in one, every window follows) — worse than no second
        // window. True multi-window needs per-window stores + focused-scene menu
        // plumbing; until that lands, one honest window.
        Window("Folio", id: "main") {
            ContentView()
                .environmentObject(vault)
                .environmentObject(ui)
                .environmentObject(settings)
                .frame(minWidth: 900, minHeight: 600)
                .preferredColorScheme(settings.colorScheme)
                // The delegate has no reference to this @StateObject and may have
                // buffered file/URL opens that arrived before SwiftUI existed; hand
                // it the store here and flush whatever queued up.
                .onAppear {
                    appDelegate.store = vault
                    appDelegate.urlHandler = { [weak vault] in vault?.handleExternal(urls: $0) }
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
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Note") { vault.newNote() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Close Tab") { if let s = vault.selection { vault.closeTab(s) } }
                    .keyboardShortcut("w", modifiers: .command)
                Button("Reopen Closed Tab") { vault.reopenClosedTab() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                Button("Next Tab") { vault.cycleTab(1) }
                    .keyboardShortcut(.tab, modifiers: .control)
                Button("Previous Tab") { vault.cycleTab(-1) }
                    .keyboardShortcut(.tab, modifiers: [.control, .shift])
                Button("Open Vault…") { vault.pickVault() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Menu("Open Recent") {
                    ForEach(vault.recentVaults, id: \.self) { url in
                        Button(url.lastPathComponent) { vault.setVault(url) }
                    }
                    if !vault.recentVaults.isEmpty {
                        Divider()
                        Button("Clear Menu") { vault.clearRecentVaults() }
                    }
                }
                .disabled(vault.recentVaults.isEmpty)
                Button("Reload Vault") { vault.refresh() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Divider()
                // Navigation history (Obsidian muscle memory). ⌘⌥← / ⌘⌥→ are bound
                // as hidden shortcuts in ContentView so both key combos reach it.
                Button("Back") { vault.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(!vault.canGoBack)
                Button("Forward") { vault.goForward() }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(!vault.canGoForward)
                Divider()
                Button("Search Files…") { ui.showQuickSwitcher = true }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Search in Vault…") { ui.showSearch = true }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Button("Filter Files") { ui.sidebarFilterFocus &+= 1 }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                Button("Command Palette…") { ui.showCommandPalette = true }
                    .keyboardShortcut("p", modifiers: .command)
                Button("Browse Tags…") { ui.showTags = true }
                    .keyboardShortcut("y", modifiers: [.command, .shift])
                Divider()
                Button(ui.mode == .read ? "Writing Mode" : "Reading Mode") {
                    ui.mode = ui.mode == .read ? .edit : .read
                }
                .keyboardShortcut("e", modifiers: .command)
                // ⌘= reads as ⌘+ on a US layout — the browser/reader convention.
                Button("Bigger Text") { settings.biggerText() }
                    .keyboardShortcut("=", modifiers: .command)
                Button("Smaller Text") { settings.smallerText() }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Reset Text Size") { settings.resetTextSize() }
                    .keyboardShortcut("0", modifiers: .command)
                Button("Keyboard Shortcuts") { ui.showShortcuts = true }
                    .keyboardShortcut("/", modifiers: .command)
            }
        }

        Settings {
            SettingsView().environmentObject(settings)
        }
    }
}

/// Behave as a regular foreground app even when launched unbundled via `swift run`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set from the WindowGroup's `.onAppear` once the store exists. Weak because
    /// the store is owned by the SwiftUI scene, not the delegate.
    weak var store: VaultStore?
    /// Route for external file/URL opens. nil until SwiftUI is up; opens that
    /// arrive before then are buffered and flushed the moment it's assigned.
    var urlHandler: (([URL]) -> Void)? {
        didSet {
            guard let urlHandler, !bufferedURLs.isEmpty else { return }
            let pending = bufferedURLs; bufferedURLs = []
            urlHandler(pending)
        }
    }
    private var bufferedURLs: [URL] = []

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
        store?.setVault(url)
    }

    /// The single AppKit entry point for both Finder double-clicks / `open -a Folio`
    /// (file URLs) and `folio://` deep links. URLs can arrive before the window
    /// exists (open-at-launch), so buffer until `urlHandler` is wired.
    func application(_ application: NSApplication, open urls: [URL]) {
        if let urlHandler { urlHandler(urls) } else { bufferedURLs.append(contentsOf: urls) }
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
