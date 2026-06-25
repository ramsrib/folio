import SwiftUI
import AppKit

@main
struct SlateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var vault = VaultStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vault)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Vault…") { vault.pickVault() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Reload Vault") { vault.refresh() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
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
