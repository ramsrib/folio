import SwiftUI
import UniformTypeIdentifiers

/// Notion-style tab strip: tabs separated by thin dividers, the active tab shown
/// by bolder/darker text (no fill), with the dividers beside it suppressed so it
/// stands out. A "+" at the end creates a new note. Scrolls when crowded.
struct TabBarView: View {
    @EnvironmentObject private var vault: VaultStore
    @State private var dragging: URL?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(vault.openTabs.enumerated()), id: \.element) { idx, url in
                    if idx > 0 {
                        Divider().frame(height: 14)
                            .opacity(dividerHidden(idx) ? 0 : 0.5)
                            .padding(.horizontal, 1)
                    }
                    TabChip(url: url, isActive: url == vault.selection)
                        .onDrag {
                            dragging = url
                            return NSItemProvider(object: url.path as NSString)
                        }
                        .onDrop(of: [.plainText],
                                delegate: TabDropDelegate(item: url, dragging: $dragging, vault: vault))
                }
                if !vault.openTabs.isEmpty {
                    Divider().frame(height: 14).opacity(0.5).padding(.horizontal, 1)
                }
                Button { vault.newNote() } label: {
                    Image(systemName: "plus").font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .contentShape(Rectangle())
                .help("New note").accessibilityLabel("New note")
                .disabled(vault.vaultURL == nil)
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 2)
            .animation(.snappy(duration: 0.2), value: vault.openTabs)
        }
    }

    private func isActive(_ i: Int) -> Bool {
        vault.openTabs.indices.contains(i) && vault.openTabs[i] == vault.selection
    }
    private func dividerHidden(_ idx: Int) -> Bool { isActive(idx) || isActive(idx - 1) }
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
                .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Color.primary : .secondary)
                .lineLimit(1)
            Button { vault.closeTab(url) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(isActive || hover ? 0.6 : 0)
            .accessibilityLabel("Close \(name)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(maxWidth: 220)
        // No fill (Notion style); a faint hover hint only on inactive tabs.
        .background(hover && !isActive ? Color.primary.opacity(0.05) : .clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
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
