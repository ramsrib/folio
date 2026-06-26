import SwiftUI
import AppKit

/// One flattened, depth-indented row of the file explorer.
struct SidebarItem: Identifiable {
    let node: VaultNode
    let depth: Int
    var id: URL { node.id }
}

/// A single file-explorer row: rotating chevron for folders, subtle rounded
/// selection + hover highlight (no heavy full-width blue bar).
struct SidebarRow: View {
    let item: SidebarItem
    @Binding var expanded: Set<URL>
    let selected: Bool
    let onSelect: () -> Void
    let onToggle: () -> Void
    let startRename: (URL) -> Void
    @EnvironmentObject private var vault: VaultStore
    @State private var hover = false

    private var node: VaultNode { item.node }
    private var isOpen: Bool { expanded.contains(node.id) }

    var body: some View {
        HStack(spacing: 5) {
            if node.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .frame(width: 10)
            } else {
                Color.clear.frame(width: 10)
            }
            Image(systemName: node.isDirectory ? "folder" : "doc.text")
                .font(.system(size: 12))
                .foregroundStyle(selected ? Color.accentColor : .secondary)
            Text(node.name)
                .font(.system(size: 13, weight: selected ? .medium : .regular))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.leading, 6 + CGFloat(item.depth) * 14)
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { if node.isDirectory { onToggle() } else { onSelect() } }
        .onHover { hover = $0 }
        .contextMenu {
            if node.isDirectory {
                Button(isOpen ? "Collapse" : "Expand") { onToggle() }
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.id]) }
            } else {
                Button("Rename…") { startRename(node.id) }
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.id]) }
                Divider()
                Button("Move to Trash", role: .destructive) { vault.delete(node.id) }
            }
        }
    }

    private var rowBackground: Color {
        if selected { return Color.accentColor.opacity(0.18) }
        if hover { return Color.primary.opacity(0.06) }
        return .clear
    }
}
