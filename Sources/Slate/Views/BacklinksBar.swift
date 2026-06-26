import SwiftUI

/// Notion-style "Linked references": an inline, collapsible section anchored to
/// the bottom of the note (no side panel). Shows a count pill that expands
/// upward into a translucent rounded card listing the inbound links.
struct BacklinksBar: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var settings: AppSettings
    @State private var expanded = false

    var body: some View {
        if !vault.backlinks.isEmpty {
            VStack(spacing: 0) {
                if expanded {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(vault.backlinks) { link in
                                Button { vault.select(link.source) } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(link.sourceName).font(.callout.weight(.medium)).lineLimit(1)
                                        Text(link.context).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(14)
                    }
                    .frame(maxHeight: 220)
                    Divider()
                }
                Button {
                    withAnimation(.smooth(duration: 0.22)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                        Text("\(vault.backlinks.count) backlink\(vault.backlinks.count == 1 ? "" : "s")")
                        Spacer()
                        Image(systemName: expanded ? "chevron.down" : "chevron.up")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: 680)
            .background(settings.surfaceStyle, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.6)))
            .shadow(color: .black.opacity(0.16), radius: 14, y: 4)
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
    }
}
