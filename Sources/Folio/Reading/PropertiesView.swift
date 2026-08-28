import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Properties (frontmatter) block

/// Notion/Obsidian-style frontmatter card: each row gets a type icon inferred from
/// its key/value, dates are formatted, tag-like keys render as pill chips, and URLs
/// or `[[wikilinks]]` stay clickable. Read-only — mirrors the note's YAML.
/// Collapsible, and collapsed by default (a one-line "Properties · N" row): the
/// content, not the metadata, is what you opened the note to read.
struct PropertiesView: View {
    let props: [Prop]
    @Binding var expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Button {
                withAnimation(.smooth(duration: 0.22)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text("Properties")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("\(props.count)")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "Collapse properties" : "Expand properties (\(props.count))")

            if expanded { rows }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, expanded ? 16 : 11)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 13) {
            ForEach(props) { p in
                let kind = PropKind.infer(key: p.key, value: p.value)
                HStack(alignment: .top, spacing: 10) {
                    HStack(spacing: 7) {
                        Image(systemName: kind.icon)
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .frame(width: 16)
                        Text(p.key)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(width: 172, alignment: .leading)
                    value(p, kind: kind)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private func value(_ p: Prop, kind: PropKind) -> some View {
        if p.value.isEmpty {
            Text("—").font(.system(size: 14.5)).foregroundStyle(.tertiary)
        } else if kind == .tags {
            FlowLayout(spacing: 6) {
                ForEach(splitList(p.value), id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 2.5)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }
        } else if kind == .date {
            Text(Self.prettyDate(p.value))
                .font(.system(size: 14.5))
        } else {
            // Metadata chrome, deliberately fixed-size: code runs size against
            // this card's own 14.5pt, not the note's body size.
            Text(InlineMarkdown.render(p.value, codeSize: 14.5 * Typography.inlineCode))
                .font(.system(size: 14.5))
                .lineSpacing(3)
                .textSelection(.enabled)
        }
    }

    private func splitList(_ s: String) -> [String] {
        s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    // ISO `yyyy-MM-dd` → a friendlier medium style (e.g. "May 22, 2026"); leaves
    // anything that doesn't parse untouched.
    private static let isoParser: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let prettyFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()
    static func prettyDate(_ value: String) -> String {
        guard let d = isoParser.date(from: value) else { return value }
        return prettyFormatter.string(from: d)
    }
}

/// The kind of a frontmatter value, used to pick a leading icon and renderer.
private enum PropKind {
    case text, date, tags, link, number

    var icon: String {
        switch self {
        case .date:   return "calendar"
        case .tags:   return "tag"
        case .link:   return "link"
        case .number: return "number"
        case .text:   return "text.alignleft"
        }
    }

    static func infer(key: String, value: String) -> PropKind {
        let k = key.lowercased()
        if ["tags", "tag", "aliases", "alias", "keywords", "categories", "category"].contains(k) { return .tags }
        if ["date", "started", "start", "updated", "created", "due", "closed", "modified", "published"]
            .contains(where: { k.contains($0) }) { return .date }
        if value.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil { return .date }
        if ["url", "link", "links", "source", "related", "homepage", "website", "repo", "repository"].contains(k) { return .link }
        if value.hasPrefix("http://") || value.hasPrefix("https://") || value.contains("[[") { return .link }
        if !value.isEmpty, Double(value) != nil { return .number }
        return .text
    }
}

/// Minimal wrapping layout — lays subviews left-to-right, wrapping to the next row
/// when the proposed width runs out. Used for tag chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, rowHeight: CGFloat = 0, totalHeight: CGFloat = 0, widest: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                totalHeight += rowHeight + spacing
                widest = max(widest, x - spacing)
                x = 0; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        widest = max(widest, x - spacing)
        return CGSize(width: min(widest, maxWidth), height: totalHeight + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
