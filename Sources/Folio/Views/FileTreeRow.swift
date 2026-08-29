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
    /// While the filter is active every shown folder reads as open (its matching
    /// descendants are already visible), so force the chevron open regardless of
    /// the persisted expansion state.
    var forceExpanded: Bool = false
    let onSelect: () -> Void
    /// Double-click on a file: "keep both" — the note being read keeps its tab,
    /// this one opens in its own (see `VaultStore.openInOwnTab`).
    let onOpenOwnTab: () -> Void
    /// The context menu's "Open in New Tab". Routed through the parent like the
    /// other two rather than calling `vault.select` here, so the sidebar can tell
    /// this is a selection it made itself and skip re-centring the row.
    let onOpenInNewTab: () -> Void
    let onToggle: () -> Void
    let startRename: (URL) -> Void
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var settings: AppSettings
    @State private var hover = false
    @State private var lastTap: TimeInterval = 0   // manual double-click detection

    private var node: VaultNode { item.node }
    private var isOpen: Bool { forceExpanded || expanded.contains(node.id) }

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
                .foregroundStyle(selected ? settings.selectionTint : .secondary)
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
        // Manual double-click detection — NEVER `.onTapGesture(count: 2)` here: a
        // count-2 recognizer makes SwiftUI hold every single click for the whole
        // double-click interval to disambiguate, which felt like ~1s of lag on
        // every row click. Instead the first click acts instantly, and a second
        // click inside the interval *upgrades* it (openInOwnTab is built to undo
        // the first click's in-place navigation — VS Code's keep-open semantics).
        .onTapGesture {
            if node.isDirectory { onToggle(); return }
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastTap < NSEvent.doubleClickInterval { onOpenOwnTab() } else { onSelect() }
            lastTap = now
        }
        .onHover { hover = $0 }
        .contextMenu {
            if node.isDirectory {
                Button(isOpen ? "Collapse" : "Expand") { onToggle() }
                Button("New Note in Folder") { vault.newNote(in: node.id) }
                Divider()
                copyItems
                Divider()
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.id]) }
            } else {
                Button("Open in New Tab") { onOpenInNewTab() }
                Button("Rename…") { startRename(node.id) }
                Divider()
                copyItems
                // A wikilink is how notes refer to each other — copy it ready to
                // paste into another note (Obsidian's "copy link").
                Button("Copy Wikilink") {
                    copyToPasteboard("[[\((node.name as NSString).deletingPathExtension)]]")
                }
                // A folio:// deep link straight to this note — for pasting into
                // another app or handing an agent (Copy Wikilink's cross-app peer).
                Button("Copy Folio Link") { copyToPasteboard(vault.folioLink(for: node.id)) }
                Divider()
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.id]) }
                Divider()
                Button("Move to Trash", role: .destructive) { vault.delete(node.id) }
            }
        }
        .focusEffectDisabled()   // suppress the blue focus ring on right-click / focus
    }

    /// Copy Relative Path / Copy Absolute Path — shared by files and folders.
    /// Relative is vault-relative (what Obsidian copies, what you'd paste into a
    /// Markdown link); absolute is the full filesystem path for tools/terminals.
    @ViewBuilder private var copyItems: some View {
        Button("Copy Relative Path") { copyToPasteboard(vault.relativePath(for: node.id)) }
        Button("Copy Absolute Path") { copyToPasteboard(node.id.path) }
    }

    private func copyToPasteboard(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    private var rowBackground: Color {
        if selected { return settings.selectionFill }
        if hover { return Color.primary.opacity(0.06) }
        return .clear
    }
}
