import Foundation

/// A single Markdown note on disk. The file URL is the identity — the file
/// system is the source of truth, so there is no separate database row.
struct MarkdownFile: Identifiable, Hashable {
    let id: URL          // absolute file URL
    let name: String     // filename without extension (display title)
    let relativePath: String  // path relative to the vault root

    var url: URL { id }

    init(url: URL, vaultRoot: URL) {
        self.id = url
        self.name = url.deletingPathExtension().lastPathComponent
        let root = vaultRoot.path.hasSuffix("/") ? vaultRoot.path : vaultRoot.path + "/"
        self.relativePath = url.path.hasPrefix(root)
            ? String(url.path.dropFirst(root.count))
            : url.lastPathComponent
    }
}
