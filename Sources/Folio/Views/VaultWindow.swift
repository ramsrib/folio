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
    /// The vault this window claimed at birth, so the coordinator knows it is
    /// spoken for even before `start()` has loaded it.
    private let claimed: VaultRef?

    init(coordinator: WindowCoordinator, settings: AppSettings) {
        self.coordinator = coordinator
        self.settings = settings
        // The claim must happen inside the autoclosure: it runs exactly once per
        // window, whereas this init runs on every re-evaluation of the parent —
        // claiming there would drain the queue.
        let claim = coordinator.claimPendingVault()
        claimed = claim
        _vault = StateObject(wrappedValue: VaultStore(vault: claim?.url))
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
                coordinator.register(vault, claimed: claimed)
                coordinator.bootstrapIfNeeded()
            }
    }
}
