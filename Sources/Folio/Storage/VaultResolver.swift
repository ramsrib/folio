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
}
