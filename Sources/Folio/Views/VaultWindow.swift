import SwiftUI

/// One window = one vault.
///
/// The stores live *here*, not on the `App`, which is what makes windows
/// independent workspaces rather than mirrors of one another. `AppSettings` stays
/// app-wide on purpose: appearance is a property of the person, not the window.
struct VaultWindow: View {
    @StateObject private var vault: VaultStore
    @StateObject private var ui = UIState()
    @ObservedObject var settings: AppSettings
    let appDelegate: AppDelegate

    /// The window's own scene value. Written back once the store settles on a
    /// vault: a window opened without one (launch, ⌘N) would otherwise stay
    /// anonymous, and `openWindow(value:)` would open a *second* window for the
    /// vault this one is already showing.
    @Binding var ref: VaultRef?

    init(ref: Binding<VaultRef?>, settings: AppSettings, appDelegate: AppDelegate) {
        _ref = ref
        // The ref is fixed when the window is created, so the autoclosure running
        // once is exactly right.
        _vault = StateObject(wrappedValue: VaultStore(vault: ref.wrappedValue?.url))
        self.settings = settings
        self.appDelegate = appDelegate
    }

    var body: some View {
        ContentView()
            .environmentObject(vault)
            .environmentObject(ui)
            .environmentObject(settings)
            .frame(minWidth: 900, minHeight: 600)
            .preferredColorScheme(settings.colorScheme)
            // Menu commands act on whichever window has focus; see FolioCommands.
            .focusedSceneValue(\.vaultStore, vault)
            .focusedSceneValue(\.uiState, ui)
            .task {
                vault.start()
                if let url = vault.vaultURL { ref = VaultRef(url) }
                appDelegate.register(vault)          // loading happens here, not in init
            }
            // Keep the scene value in step if the window's vault ever changes.
            .onChange(of: vault.vaultURL) { _, url in
                if let url { ref = VaultRef(url) }
            }
            .onDisappear {
                appDelegate.unregister(vault)
                if let url = vault.vaultURL { VaultSession.closed(VaultRef(url)) }
            }
    }
}

// MARK: - Focused values

private struct VaultStoreKey: FocusedValueKey { typealias Value = VaultStore }
private struct UIStateKey: FocusedValueKey { typealias Value = UIState }

extension FocusedValues {
    /// The front window's vault store, so a menu item acts on the window you're
    /// looking at rather than on a single app-wide store.
    var vaultStore: VaultStore? {
        get { self[VaultStoreKey.self] }
        set { self[VaultStoreKey.self] = newValue }
    }
    var uiState: UIState? {
        get { self[UIStateKey.self] }
        set { self[UIStateKey.self] = newValue }
    }
}
