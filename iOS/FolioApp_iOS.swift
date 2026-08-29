import SwiftUI

/// iOS entry point. Reuses the shared data layer (VaultStore, UIState,
/// AppSettings) and the shared ReadingView; the navigation/chrome is iOS-native.
@main
struct FolioApp: App {
    @StateObject private var vault = VaultStore()
    @StateObject private var ui = UIState()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView_iOS()
                .environmentObject(vault)
                .environmentObject(ui)
                .environmentObject(settings)
                .preferredColorScheme(settings.colorScheme)
                // `VaultStore.init` is deliberately cheap (see its doc comment);
                // loading happens here. Without this the app launches to the
                // empty state every time and the saved bookmark is never read.
                .task { vault.start() }
        }
    }
}
