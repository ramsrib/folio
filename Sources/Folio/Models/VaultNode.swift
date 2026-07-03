import Foundation

/// A node in the vault's folder tree. Directories carry `children`; files have
/// `children == nil` (so `OutlineGroup` treats them as leaves).
struct VaultNode: Identifiable, Hashable {
    let id: URL            // file or directory URL
    let name: String
    let isDirectory: Bool
    var children: [VaultNode]?
}
