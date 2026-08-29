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
    let appDelegate: AppDelegate

    /// The vault this window was opened for. Read once at creation; the window's
    /// identity afterwards is tracked by `AppDelegate`, keyed on the store's
    /// vault path, not by this binding.
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
            // Hand the registry this window so a vault can be *focused* rather
            // than re-opened. Note what we deliberately do NOT do: write the
            // settled vault back into `$ref`. Assigning to a WindowGroup's value
            // binding presents a new window for that value — it is not a rename,
            // and using it as one spawns a window every time a vault loads.
            .background(WindowAccessor { window in
                appDelegate.attach(window, to: vault)
            })
            .task {
                vault.start()
                appDelegate.register(vault)
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

/// Reports the hosting `NSWindow` once it exists, so the vault→window registry
/// can focus a window instead of opening another.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let w = view.window { onWindow(w) } }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { if let w = nsView.window { onWindow(w) } }
    }
}
