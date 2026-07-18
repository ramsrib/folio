import SwiftUI
import UniformTypeIdentifiers

/// Browser/Notion-style tab strip. The active tab is a full-height cell framed on
/// three sides (top edge of the window + left/right borders); its bottom merges
/// into the title bar's own bottom divider, so it reads as a defined tab rather
/// than a floating box. Inactive tabs are plain text with thin separators between
/// them. A "+" at the end creates a new note. Scrolls when crowded.
struct TabBarView: View {
    @EnvironmentObject private var vault: VaultStore
    @State private var dragging: URL?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(vault.openTabs.enumerated()), id: \.element) { idx, url in
                    // Drop the separator entirely (not just hide it) next to the
                    // active tab, so its bordered cell — or a hovered neighbor's
                    // highlight — sits flush instead of leaving an empty gap.
                    if idx > 0 && !dividerHidden(idx) {
                        Divider().frame(height: 14)
                            .opacity(0.5)
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
                .padding(.horizontal, 8)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .help("New Note (⌘N)").accessibilityLabel("New note")
                .disabled(vault.vaultURL == nil)
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 2)
            .animation(.snappy(duration: 0.2), value: vault.openTabs)
        }
        .frame(maxHeight: .infinity)
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
    @EnvironmentObject private var settings: AppSettings
    @State private var hover = false

    private var name: String { (url.lastPathComponent as NSString).deletingPathExtension }

    /// Active tab uses the editor's page color so the framed cell reads distinctly;
    /// inactive tabs are transparent with only a faint hover hint.
    private var chipBackground: Color {
        if isActive { return settings.paneBackground ?? Color(nsColor: .textBackgroundColor) }
        return hover ? Color.primary.opacity(0.06) : .clear
    }

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
        .frame(maxWidth: 220, maxHeight: .infinity)
        .background(chipBackground, in: TabShape(radius: 6))
        // Active tab: three-sided frame (top + sides) with softly rounded top
        // corners; the bottom is left open so it merges into the title-bar divider.
        .overlay {
            if isActive {
                TabFrame(radius: 6).stroke(Color.secondary.opacity(0.5),
                                           style: StrokeStyle(lineWidth: 0.5, lineJoin: .round))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { vault.select(url) }
        .onHover { hover = $0 }
        .help(url.lastPathComponent)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .contextMenu {
            Button("Close") { vault.closeTab(url) }
            Button("Close Others") { vault.closeOtherTabs(keeping: url) }
            Button("Close Tabs to the Right") { vault.closeTabsToTheRight(of: url) }
            Button("Close All") { vault.closeAllTabs() }
            Button("Reopen Closed Tab") { vault.reopenClosedTab() }
            Divider()
            // Same copy trio as the explorer's context menu — keep them in sync.
            Button("Copy Relative Path") { copyToPasteboard(vault.relativePath(for: url)) }
            Button("Copy Absolute Path") { copyToPasteboard(url.path) }
            Button("Copy Wikilink") { copyToPasteboard("[[\(name)]]") }
            Divider()
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }

    private func copyToPasteboard(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}

/// Three-sided tab outline — up the left side, across the top with rounded top
/// corners, down the right — and no bottom edge, so the active tab's bottom
/// blends into the title-bar divider below it.
private struct TabFrame: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: 0.5, dy: 0)
        let top = r.minY + 0.5
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: top + radius))
        p.addQuadCurve(to: CGPoint(x: r.minX + radius, y: top),
                       control: CGPoint(x: r.minX, y: top))
        p.addLine(to: CGPoint(x: r.maxX - radius, y: top))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: top + radius),
                       control: CGPoint(x: r.maxX, y: top))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        return p
    }
}

/// Fill shape for a tab: rounded top corners, square bottom (so it sits flush on
/// the title-bar divider). Matches `TabFrame`.
private struct TabShape: InsettableShape {
    var radius: CGFloat
    var inset: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: 0,
                               bottomTrailingRadius: 0, topTrailingRadius: radius,
                               style: .continuous)
            .path(in: rect.insetBy(dx: inset, dy: 0))
    }
    func inset(by amount: CGFloat) -> some InsettableShape {
        TabShape(radius: radius, inset: inset + amount)
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
