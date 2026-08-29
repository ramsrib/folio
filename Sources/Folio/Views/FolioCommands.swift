import SwiftUI

/// The menu bar. Every item targets the **focused** window's stores rather than a
/// shared pair, which is the half of multi-window that isn't the scene itself:
/// without it, ⌘N in one window would add a note to another.
struct FolioCommands: Commands {
    @ObservedObject var settings: AppSettings
    let coordinator: WindowCoordinator
    /// Objects, not values: `@FocusedValue` only re-evaluates when *which* object
    /// is focused changes, so `canGoBack` would go stale and silently disable
    /// ⌘[ / ⌘] as you navigate.
    @FocusedObject private var vault: VaultStore?
    @FocusedObject private var ui: UIState?

    var body: some Commands {
        // Settings is an in-window overlay, not a Settings scene — replace the
        // system item so ⌘, opens ours (see SettingsView for the rationale).
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { ui?.showSettings = true }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(ui == nil)
        }
        CommandGroup(replacing: .newItem) {
            Button("New Note") { vault?.newNote() }
                .keyboardShortcut("n", modifiers: .command)
            Button("Close Tab") { if let s = vault?.selection { vault?.closeTab(s) } }
                .keyboardShortcut("w", modifiers: .command)
            Button("Reopen Closed Tab") { vault?.reopenClosedTab() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Button("Next Tab") { vault?.cycleTab(1) }
                .keyboardShortcut(.tab, modifiers: .control)
            Button("Previous Tab") { vault?.cycleTab(-1) }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
            Divider()

            // Vaults open windows; they never replace the vault in this one.
            Button("New Window") { coordinator.openEmptyWindow() }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Button("Switch Vault…") { ui?.showVaultSwitcher = true }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(ui == nil)
            Button("Open Vault…") {
                if let url = VaultPicker.choose() { coordinator.open(VaultRef(url)) }
            }
            .keyboardShortcut("o", modifiers: [.command, .option])
            Menu("Open Recent") {
                ForEach(vault?.recentVaults ?? [], id: \.self) { url in
                    Button(url.lastPathComponent) { coordinator.open(VaultRef(url)) }
                }
                if !(vault?.recentVaults.isEmpty ?? true) {
                    Divider()
                    Button("Clear Menu") { vault?.clearRecentVaults() }
                }
            }
            .disabled(vault?.recentVaults.isEmpty ?? true)
            Button("Reload Vault") { vault?.refresh() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Divider()
            // Navigation history (Obsidian muscle memory). ⌘⌥← / ⌘⌥→ are bound
            // as hidden shortcuts in ContentView so both key combos reach it.
            Button("Back") { vault?.goBack() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!(vault?.canGoBack ?? false))
            Button("Forward") { vault?.goForward() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!(vault?.canGoForward ?? false))
            Divider()
            Button("Search Files…") { ui?.showQuickSwitcher = true }
                .keyboardShortcut("k", modifiers: .command)
            Button("Search in Vault…") { ui?.showSearch = true }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Filter Files") { ui?.sidebarFilterFocus &+= 1 }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Button("Command Palette…") { ui?.showCommandPalette = true }
                .keyboardShortcut("p", modifiers: .command)
            Button("Browse Tags…") { ui?.showTags = true }
                .keyboardShortcut("y", modifiers: [.command, .shift])
            Divider()
            Button(ui?.mode == .read ? "Writing Mode" : "Reading Mode") {
                ui?.mode = ui?.mode == .read ? .edit : .read
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(ui == nil)
            // ⌘= reads as ⌘+ on a US layout — the browser/reader convention.
            Button("Bigger Text") { settings.biggerText() }
                .keyboardShortcut("=", modifiers: .command)
            Button("Smaller Text") { settings.smallerText() }
                .keyboardShortcut("-", modifiers: .command)
            Button("Reset Text Size") { settings.resetTextSize() }
                .keyboardShortcut("0", modifiers: .command)
            Button("Keyboard Shortcuts") { ui?.showShortcuts = true }
                .keyboardShortcut("/", modifiers: .command)
        }
    }
}

/// The "choose a folder" panel, lifted out of `VaultStore` — picking a vault is
/// now a window-opening action, not something a store does to itself.
enum VaultPicker {
    @MainActor static func choose() -> URL? {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Vault"
        panel.message = "Choose a folder of Markdown notes"
        return panel.runModal() == .OK ? panel.url : nil
        #else
        return nil
        #endif
    }
}
