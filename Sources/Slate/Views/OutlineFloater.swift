import SwiftUI

/// Notion-style table of contents: a minimal stack of tick marks pinned to the
/// right edge that expands into a translucent rounded card on hover. No side
/// panel. Click a heading to scroll the editor there.
struct OutlineFloater: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var settings: AppSettings
    @State private var hovering = false

    var body: some View {
        if !vault.outline.isEmpty {
            Group {
                if hovering { expanded } else { collapsed }
            }
            .onHover { hovering = $0 }
            .animation(.smooth(duration: 0.18), value: hovering)
        }
    }

    private var collapsed: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(vault.outline) { item in
                Capsule()
                    .fill(.secondary.opacity(0.5))
                    .frame(width: tickWidth(item.level), height: 2)
            }
        }
        .padding(10)
        .frame(maxHeight: 460, alignment: .top)
    }

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Outline")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            ForEach(vault.outline) { item in
                Button { vault.scrollRequest = item.charIndex } label: {
                    Text(item.title)
                        .font(.callout)
                        .lineLimit(1)
                        .padding(.leading, CGFloat(item.level - 1) * 11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 1)
            }
        }
        .padding(14)
        .frame(width: 250, alignment: .leading)
        .frame(maxHeight: 460)
        .fixedSize(horizontal: false, vertical: true)
        .background(settings.surfaceStyle, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.6)))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
    }

    private func tickWidth(_ level: Int) -> CGFloat {
        max(8, 24 - CGFloat(level - 1) * 4)
    }
}
