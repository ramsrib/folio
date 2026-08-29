import Foundation

/// Which vault should hold a file that arrived from outside the app.
///
/// The window-routing layer needs this *before* a window exists, so it can't live
/// on `VaultStore` (which resolves the same way once it has one — tier 1 there is
/// "already in this window's vault").
@MainActor
enum VaultResolver {
    /// Deepest recent vault containing the file, else the file's own folder.
    /// Comparisons go through resolved symlinks so an aliased path never spawns a
    /// duplicate vault for a folder that is already open.
    static func vault(for file: URL) -> URL {
        let resolved = file.resolvingSymlinksInPath().standardizedFileURL.path
        let recents = (UserDefaults.standard.array(forKey: "folio.recentVaults") as? [String] ?? [])
            .map { URL(fileURLWithPath: $0) }
        let containing = recents.filter {
            resolved.hasPrefix($0.resolvingSymlinksInPath().standardizedFileURL.path + "/")
        }
        if let deepest = containing.max(by: { $0.standardizedFileURL.path.count < $1.standardizedFileURL.path.count }) {
            return deepest
        }
        return file.deletingLastPathComponent()
    }

    /// The vault (and optional file) a `folio://` link addresses, so the router
    /// can send it to the window that owns that vault instead of to whichever
    /// window happens to be frontmost.
    static func destination(for url: URL) -> (vault: URL, file: URL?)? {
        guard url.scheme?.lowercased() == "folio" else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let vaultPath = items.first(where: { $0.name == "vault" })?.value else { return nil }
        let vault = URL(fileURLWithPath: vaultPath, isDirectory: true)
        let file = items.first(where: { $0.name == "file" })?.value
            .map { vault.appendingPathComponent($0) }
        return (vault, file)
    }
}
