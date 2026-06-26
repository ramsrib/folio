import SwiftUI
import UniformTypeIdentifiers

/// Horizontal bar of open notes (tabs): click to activate, ✕/⌘W to close,
/// drag to reorder, right-click for close-others/all.
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
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
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
            Image(systemName: "doc.text").font(.system(size: 11)).foregroundStyle(.secondary)
            Text(name).font(.system(size: 13)).lineLimit(1)
            Button { vault.closeTab(url) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(isActive || hover ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: 200)
        .background(isActive ? Color.primary.opacity(0.08) : .clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(isActive ? Color.secondary.opacity(0.25) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { vault.select(url) }
        .onHover { hover = $0 }
        .help(name)
        .contextMenu {
            Button("Close") { vault.closeTab(url) }
            Button("Close Others") { vault.closeOtherTabs(keeping: url) }
            Button("Close All") { vault.closeAllTabs() }
            Divider()
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
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
