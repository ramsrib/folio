import SwiftUI
import AppKit

/// One window = one vault.
///
/// The stores live *here*, not on the `App`, which is what makes windows
/// independent workspaces rather than mirrors of one another. `AppSettings` stays
/// app-wide on purpose: appearance is a property of the person, not the window.
struct VaultWindow: View {
    @StateObject private var vault: VaultStore
    @StateObject private var ui = UIState()
    @ObservedObject var settings: AppSettings
    let coordinator: WindowCoordinator

    init(coordinator: WindowCoordinator, settings: AppSettings) {
        self.coordinator = coordinator
        self.settings = settings
        // The claim must happen inside the autoclosure: it runs exactly once per
        // window, whereas this init runs on every re-evaluation of the parent —
        // claiming there would drain the queue.
        _vault = StateObject(wrappedValue: VaultStore(vault: coordinator.claimPendingVault()?.url))
    }

    var body: some View {
        ContentView()
            .environmentObject(vault)
            .environmentObject(ui)
            .environmentObject(settings)
            .environment(\.windowCoordinator, coordinator)
            .frame(minWidth: 900, minHeight: 600)
            .preferredColorScheme(settings.colorScheme)
            // Objects, not values: `@FocusedValue` only re-evaluates the menus when
            // *which* object is focused changes, so `canGoBack` would go stale and
            // silently disable ⌘[ / ⌘].
            .focusedSceneObject(vault)
            .focusedSceneObject(ui)
            .background(WindowBinder { window in coordinator.attach(window, to: vault) })
            .task {
                // `openWindowAction` is wired at the App level (it must exist
                // before any window does — a document-driven launch presents no
                // scene until the AppDelegate summons one).
                vault.start()
                coordinator.register(vault)
                coordinator.bootstrapIfNeeded()
                let l = "pid=\(ProcessInfo.processInfo.processIdentifier) vault=\(vault.vaultURL?.lastPathComponent ?? "none")\n"
                if let h = try? FileHandle(forWritingTo: URL(fileURLWithPath: "/tmp/folio-mw.log")) { h.seekToEndOfFile(); h.write(Data(l.utf8)); try? h.close() }
                else { try? l.write(to: URL(fileURLWithPath: "/tmp/folio-mw.log"), atomically: true, encoding: .utf8) }
            }
    }
}
