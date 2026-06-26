import SwiftUI
import AppKit

/// One row of the file explorer. Folders are `DisclosureGroup`s whose **whole
/// label toggles expansion on click** (not just the chevron); files are
/// selectable note rows with a context menu.
struct FileTreeRow: View {
    let node: VaultNode
    @Binding var expanded: Set<URL>
    let startRename: (URL) -> Void
    @EnvironmentObject private var vault: VaultStore

    var body: some View {
        if node.isDirectory {
            DisclosureGroup(isExpanded: expandBinding) {
                ForEach(node.children ?? []) { child in
                    FileTreeRow(node: child, expanded: $expanded, startRename: startRename)
                }
            } label: {
                Label(node.name, systemImage: expanded.contains(node.id) ? "folder.fill" : "folder")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { toggle() }
            }
        } else {
            Label(node.name, systemImage: "doc.text")
                .lineLimit(1)
                .tag(node.id)
                .contextMenu {
                    Button("Rename…") { startRename(node.id) }
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([node.id])
                    }
                    Divider()
                    Button("Move to Trash", role: .destructive) { vault.delete(node.id) }
                }
        }
    }

    private var expandBinding: Binding<Bool> {
        Binding(get: { expanded.contains(node.id) },
                set: { isOn in if isOn { expanded.insert(node.id) } else { expanded.remove(node.id) } })
    }

    private func toggle() {
        if expanded.contains(node.id) { expanded.remove(node.id) } else { expanded.insert(node.id) }
    }
}
