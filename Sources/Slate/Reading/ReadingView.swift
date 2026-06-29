import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Notion-style fully-rendered, read-(mostly)-only view of the current note.
/// No syntax symbols — headings, lists, checkboxes, callouts, code, tables,
/// dividers, and images are drawn as native views.
struct ReadingView: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var settings: AppSettings

    // Parsed once per content change (not on every redraw/scroll).
    @State private var blocks: [Block] = []
    private var body0: CGFloat { settings.bodyFontSize }
    private var design: Font.Design { settings.readingFont.design }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(blocks) { block in
                        view(for: block).id(anchorID(block))
                    }
                }
                .frame(maxWidth: settings.readableWidth, alignment: .leading)
                .frame(maxWidth: .infinity, minHeight: 200, alignment: .top)
                .contentShape(Rectangle())
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                // Double-click the page to start writing (like Notion).
                .onTapGesture(count: 2) { withAnimation(.smooth(duration: 0.2)) { ui.mode = .edit } }
            }
            .task(id: vault.content) { blocks = MarkdownParser.parse(vault.content) }
            .onChange(of: vault.scrollRequest) {
                if let req = vault.scrollRequest {
                    withAnimation(.smooth) { proxy.scrollTo(req, anchor: .top) }
                    vault.scrollRequest = nil
                }
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "slate", url.host == "wikilink" {
                let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "target" })?.value ?? ""
                vault.openWikilink(target); return .handled
            }
            return .systemAction
        })
        .textSelection(.enabled)
    }

    private func anchorID(_ block: Block) -> Int {
        if case let .heading(_, _, anchor) = block.kind { return anchor }
        return -block.id.hashValue
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block.kind {
        case let .properties(props):
            PropertiesView(props: props)

        case let .heading(level, text, _):
            Text(InlineMarkdown.render(text))
                .font(.system(size: headingSize(level), weight: level <= 2 ? .bold : .semibold, design: design))
                .padding(.top, level <= 2 ? 18 : 8)

        case let .paragraph(text):
            Text(InlineMarkdown.render(text)).font(.system(size: body0, design: design)).lineSpacing(body0 * 0.42)

        case let .listItem(ordered, number, indent, text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(ordered ? "\(number)." : "•").font(.system(size: body0 - 0.5)).foregroundStyle(.secondary)
                Text(InlineMarkdown.render(text)).font(.system(size: body0 - 0.5, design: design)).lineSpacing(body0 * 0.36)
            }
            .padding(.leading, CGFloat(indent) * 22)

        case let .task(checked, indent, text, checkboxIndex):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button { vault.toggleTask(atContentIndex: checkboxIndex) } label: {
                    Image(systemName: checked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(checked ? Color.accentColor : .secondary)
                        .font(.system(size: body0 - 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(checked ? "Completed task" : "Incomplete task")
                .accessibilityAddTraits(.isButton)
                Text(InlineMarkdown.render(text)).font(.system(size: body0 - 0.5, design: design)).lineSpacing(body0 * 0.36)
                    .strikethrough(checked).foregroundStyle(checked ? .secondary : .primary)
            }
            .padding(.leading, CGFloat(indent) * 22)

        case let .quote(text):
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2).fill(.secondary.opacity(0.5)).frame(width: 3)
                Text(InlineMarkdown.render(text)).font(.system(size: body0 - 0.5, design: design)).lineSpacing(body0 * 0.36)
                    .foregroundStyle(.secondary)
            }

        case let .callout(kind, title, body):
            calloutView(kind: kind, title: title, body: body)

        case let .code(language, text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(CodeHighlighter.highlight(text, language: language))
                    .textSelection(.enabled)
                    .padding(12)
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

        case .divider:
            Divider().padding(.vertical, 6)

        case let .image(alt, source):
            imageView(alt: alt, source: source)

        case let .table(headers, rows):
            tableView(headers: headers, rows: rows)
        }
    }

    private func calloutView(kind: String, title: String, body: String) -> some View {
        let (icon, tint) = calloutStyle(kind)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).font(.system(size: 16, weight: .semibold))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 15, weight: .semibold))
                if !body.isEmpty { Text(InlineMarkdown.render(body)).font(.system(size: 15)) }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(tint.opacity(0.3)))
    }

    @ViewBuilder
    private func imageView(alt: String, source: String) -> some View {
        if source.hasPrefix("http"), let url = URL(string: source) {
            AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
                .frame(maxWidth: 680, maxHeight: 480, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else if let local = localImage(source) {
            Image(platform: local).resizable().scaledToFit()
                .frame(maxWidth: 680, maxHeight: 480, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            Label(alt.isEmpty ? source : alt, systemImage: "photo").foregroundStyle(.secondary)
        }
    }

    private func tableView(headers: [String], rows: [[String]]) -> some View {
        let columns = max(headers.count, rows.map(\.count).max() ?? 0)
        return VStack(spacing: 0) {
            tableRow(headers, columns: columns, bold: true)
            Divider()
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                tableRow(row, columns: columns, bold: false)
                Divider()
            }
        }
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator))
    }

    private func tableRow(_ cells: [String], columns: Int, bold: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<columns, id: \.self) { c in
                Text(c < cells.count ? InlineMarkdown.render(cells[c]) : AttributedString(""))
                    .font(.system(size: 14, weight: bold ? .semibold : .regular))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                if c < columns - 1 { Divider() }
            }
        }
    }

    // MARK: helpers

    private func headingSize(_ level: Int) -> CGFloat {
        let scale: [CGFloat] = [1.75, 1.4, 1.18, 1.06, 0.98, 0.9]
        return body0 * scale[min(max(level - 1, 0), 5)]
    }

    private func localImage(_ source: String) -> PlatformImage? {
        guard let note = vault.selection else { return nil }
        let candidates = [
            note.deletingLastPathComponent().appendingPathComponent(source),
            vault.vaultURL?.appendingPathComponent(source),
            URL(fileURLWithPath: source)
        ].compactMap { $0 }
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            if let img = PlatformImage.load(contentsOf: url) { return img }
        }
        return nil
    }

    private func calloutStyle(_ kind: String) -> (String, Color) {
        switch kind {
        case "warning", "caution", "attention": return ("exclamationmark.triangle.fill", .orange)
        case "danger", "error", "bug":          return ("xmark.octagon.fill", .red)
        case "success", "check", "done":        return ("checkmark.circle.fill", .green)
        case "question", "faq", "help":         return ("questionmark.circle.fill", .purple)
        case "tip", "hint", "important":        return ("flame.fill", .pink)
        case "quote", "cite":                   return ("quote.opening", .gray)
        default:                                 return ("info.circle.fill", .blue)
        }
    }
}

// MARK: - Properties (frontmatter) block

/// Notion/Obsidian-style frontmatter card: each row gets a type icon inferred from
/// its key/value, dates are formatted, tag-like keys render as pill chips, and URLs
/// or `[[wikilinks]]` stay clickable. Read-only — mirrors the note's YAML.
private struct PropertiesView: View {
    let props: [Prop]

    var body: some View {
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
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            Text(InlineMarkdown.render(p.value))
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
private struct FlowLayout: Layout {
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
