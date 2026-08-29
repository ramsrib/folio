import Foundation

/// Identity of a window: the vault it holds.
///
/// One vault per window (Obsidian's model). `WindowGroup(for:)` keys windows by
/// this value, which is also what makes `openWindow(value:)` *focus* an existing
/// window for a vault instead of opening a duplicate — the routing rule that
/// keeps a note from ever hijacking the vault someone is reading.
struct VaultRef: Hashable, Codable, Identifiable {
    /// Symlink-resolved so `/tmp/x` and `/private/tmp/x` are one window, not two.
    let path: String

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
    var name: String { url.lastPathComponent }

    init(_ url: URL) {
        path = url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    init?(path: String?) {
        guard let path else { return nil }
        self.init(URL(fileURLWithPath: path, isDirectory: true))
    }

    var exists: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}

/// The set of vaults with a window open, so a relaunch restores the workspace
/// rather than just the last vault touched.
@MainActor
enum VaultSession {
    private static let key = "folio.openVaults"
    private static let d = UserDefaults.standard

    static var openVaults: [VaultRef] {
        (d.array(forKey: key) as? [String] ?? []).compactMap { VaultRef(path: $0) }.filter(\.exists)
    }

    static func opened(_ ref: VaultRef) {
        var refs = openVaults.filter { $0 != ref }
        refs.append(ref)
        d.set(refs.map(\.path), forKey: key)
    }

    static func closed(_ ref: VaultRef) {
        d.set(openVaults.filter { $0 != ref }.map(\.path), forKey: key)
    }
}
