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
        WindowGroup {
            ContentView()
                .environmentObject(vault)
                .environmentObject(ui)
                .environmentObject(settings)
                .frame(minWidth: 900, minHeight: 600)
                .preferredColorScheme(settings.colorScheme)
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
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        configureAppIcon()
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

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
