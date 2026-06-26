import SwiftUI
import AppKit

/// Notion-style fully-rendered, read-(mostly)-only view of the current note.
/// No syntax symbols — headings, lists, checkboxes, callouts, code, tables,
/// dividers, and images are drawn as native views.
struct ReadingView: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var settings: AppSettings

    private var blocks: [Block] { MarkdownParser.parse(vault.content) }
    private var body0: CGFloat { settings.bodyFontSize }
    private var design: Font.Design { settings.readingFont.design }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
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
            VStack(alignment: .leading, spacing: 11) {
                ForEach(props) { p in
                    HStack(alignment: .top, spacing: 16) {
                        Text(p.key)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 150, alignment: .leading)
                        Text(p.value.isEmpty ? "—" : p.value)
                            .font(.system(size: 14.5))
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

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
        } else if let nsImage = localImage(source) {
            Image(nsImage: nsImage).resizable().scaledToFit()
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

    private func localImage(_ source: String) -> NSImage? {
        guard let note = vault.selection else { return nil }
        let candidates = [
            note.deletingLastPathComponent().appendingPathComponent(source),
            vault.vaultURL?.appendingPathComponent(source),
            URL(fileURLWithPath: source)
        ].compactMap { $0 }
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            if let img = NSImage(contentsOf: url) { return img }
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
