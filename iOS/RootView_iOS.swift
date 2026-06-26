import SwiftUI

/// Phase 1 skeleton: render a sample note through the shared `ReadingView` to
/// prove the shared core + iOS build pipeline. Vault browsing/editing come next.
struct RootView_iOS: View {
    @EnvironmentObject private var vault: VaultStore

    var body: some View {
        NavigationStack {
            ReadingView()
                .navigationTitle("Slate")
                .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            if vault.content.isEmpty { vault.content = Self.sample }
        }
    }

    private static let sample = """
    # Welcome to Slate for iOS

    This note is rendered by the **same** `ReadingView` and Markdown parser the
    macOS app uses — no duplicated rendering code.

    ## What works
    - Headings, **bold**, _italic_, `inline code`
    - Lists and tasks
    - [x] Shared core compiles for iOS
    - [ ] Open a real vault (next)

    > Files on disk stay the source of truth.

    ```swift
    let greeting = "Hello, Slate"
    print(greeting)
    ```

    | Feature | Status |
    | --- | --- |
    | Reader | ✅ |
    | Editing | soon |
    """
}
