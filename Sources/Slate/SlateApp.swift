import SwiftUI
import AppKit

@main
struct SlateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var vault = VaultStore()
    @StateObject private var ui = UIState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vault)
                .environmentObject(ui)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Note") { vault.newNote() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Close Tab") { if let s = vault.selection { vault.closeTab(s) } }
                    .keyboardShortcut("w", modifiers: .command)
                Button("Open Vault…") { vault.pickVault() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Reload Vault") { vault.refresh() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Divider()
                Button("Search Files…") { ui.showQuickSwitcher = true }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Command Palette…") { ui.showCommandPalette = true }
                    .keyboardShortcut("p", modifiers: .command)
                Divider()
                Button(ui.mode == .read ? "Edit Mode" : "Reading Mode") {
                    ui.mode = ui.mode == .read ? .edit : .read
                }
                .keyboardShortcut("e", modifiers: .command)
            }
        }
    }
}

/// Behave as a regular foreground app even when launched unbundled via `swift run`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
