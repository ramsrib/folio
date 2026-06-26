import SwiftUI
import UniformTypeIdentifiers

/// Horizontal bar of open notes (tabs): click to activate, ✕/⌘W to close,
/// drag to reorder, right-click for close-others/all. A "+" at the end creates a
/// new note. Scrolls when there are many tabs.
struct TabBarView: View {
    @EnvironmentObject private var vault: VaultStore
    @State private var dragging: URL?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(vault.openTabs, id: \.self) { url in
                    TabChip(url: url, isActive: url == vault.selection)
                        .onDrag {
                            dragging = url
                            return NSItemProvider(object: url.path as NSString)
                        }
                        .onDrop(of: [.plainText],
                                delegate: TabDropDelegate(item: url, dragging: $dragging, vault: vault))
                }
                if !vault.openTabs.isEmpty {
                    Divider().frame(height: 14).padding(.horizontal, 2)
                }
                Button { vault.newNote() } label: {
                    Image(systemName: "plus").font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(6)
                .contentShape(Rectangle())
                .help("New note").accessibilityLabel("New note")
                .disabled(vault.vaultURL == nil)
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
            .animation(.snappy(duration: 0.2), value: vault.openTabs)
        }
    }
}

private struct TabChip: View {
    let url: URL
    let isActive: Bool
    @EnvironmentObject private var vault: VaultStore
    @State private var hover = false

    private var name: String { (url.lastPathComponent as NSString).deletingPathExtension }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 11))
                .foregroundStyle(isActive ? Color.primary : .secondary)
            Text(name)
                .font(.system(size: 12.5, weight: isActive ? .medium : .regular))
                .foregroundStyle(isActive ? Color.primary : .secondary)
                .lineLimit(1)
            Button { vault.closeTab(url) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(isActive || hover ? 0.7 : 0)
            .accessibilityLabel("Close \(name)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: 200)
        // Flat selected style (Obsidian/Notion): a subtle fill, no shadow/border.
        .background(chipBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { vault.select(url) }
        .onHover { hover = $0 }
        .help(name)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .contextMenu {
            Button("Close") { vault.closeTab(url) }
            Button("Close Others") { vault.closeOtherTabs(keeping: url) }
            Button("Close All") { vault.closeAllTabs() }
            Divider()
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }

    private var chipBackground: Color {
        if isActive { return Color.primary.opacity(0.09) }
        return hover ? Color.primary.opacity(0.05) : .clear
    }
}

/// Live drag-reorder: as the dragged tab passes over another, swap their order.
private struct TabDropDelegate: DropDelegate {
    let item: URL
    @Binding var dragging: URL?
    let vault: VaultStore

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != item else { return }
        vault.reorderTab(from: dragging, to: item)
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { dragging = nil; return true }
}
