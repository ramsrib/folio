import SwiftUI
import UniformTypeIdentifiers

/// Horizontal bar of open notes (tabs): click to activate, ✕/⌘W to close,
/// drag to reorder, right-click for close-others/all. Scrolls when there are
/// many tabs so it never overflows the title bar.
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
            .padding(.vertical, 3)
            .animation(.snappy(duration: 0.2), value: vault.openTabs)
        }
    }
}

private struct TabChip: View {
    let url: URL
    let isActive: Bool
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var settings: AppSettings
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
            .opacity(isActive || hover ? 0.8 : 0)
            .accessibilityLabel("Close \(name)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .frame(maxWidth: 200)
        .background(chipBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isActive ? Color.black.opacity(0.08) : .clear, lineWidth: 1)
        )
        .shadow(color: .black.opacity(isActive ? 0.12 : 0), radius: 2.5, y: 1)   // active tab "pops"
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
        if isActive { return settings.paneBackground ?? Color(nsColor: .textBackgroundColor) }
        return hover ? Color.primary.opacity(0.06) : .clear
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
