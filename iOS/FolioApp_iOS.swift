import SwiftUI

/// iOS entry point. Reuses the shared data layer (VaultStore, UIState,
/// AppSettings) and the shared ReadingView; the navigation/chrome is iOS-native.
@main
struct FolioApp: App {
    @StateObject private var vault = VaultStore(vault: TestLaunch.vault)
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

/// UI-test hooks, read once from the launch arguments. Debug builds only; in a
/// release build every member is inert so the app has no test-only behavior.
///
/// - `--ui-testing`: forget the saved vault (bookmark, path, session) so a test
///   always starts from the empty state regardless of what the simulator last had open.
/// - `--vault <path>`: open this folder at launch instead of the saved one. The
///   simulator doesn't sandbox file access, so a test can hand over a folder it
///   just wrote.
enum TestLaunch {
    static let vault: URL? = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--ui-testing") else { return nil }
        for key in ["folio.vaultBookmark", "folio.vaultPath", "folio.openVaults", "folio.recentVaults"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        guard let i = args.firstIndex(of: "--vault"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
        #else
        return nil
        #endif
    }()
}
