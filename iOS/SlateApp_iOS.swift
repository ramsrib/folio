import SwiftUI

/// iOS entry point. Reuses the shared data layer (VaultStore, UIState,
/// AppSettings) and the shared ReadingView; the navigation/chrome is iOS-native.
@main
struct SlateiOSApp: App {
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
        }
    }
}
