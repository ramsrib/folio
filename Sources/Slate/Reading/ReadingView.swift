import SwiftUI
import AppKit

/// Notion-style fully-rendered, read-(mostly)-only view of the current note.
/// No syntax symbols — headings, lists, checkboxes, callouts, code, tables,
/// dividers, and images are drawn as native views.
struct ReadingView: View {
    @EnvironmentObject private var vault: VaultStore

    private var blocks: [Block] { MarkdownParser.parse(vault.content) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(blocks) { block in
                        view(for: block).id(anchorID(block))
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
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
        case let .heading(level, text, _):
            Text(InlineMarkdown.render(text))
                .font(.system(size: headingSize(level), weight: .bold, design: .rounded))
                .padding(.top, level <= 2 ? 10 : 4)

        case let .paragraph(text):
            Text(InlineMarkdown.render(text)).font(.system(size: 16)).lineSpacing(4)

        case let .listItem(ordered, number, indent, text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(ordered ? "\(number)." : "•").font(.system(size: 16)).foregroundStyle(.secondary)
                Text(InlineMarkdown.render(text)).font(.system(size: 16))
            }
            .padding(.leading, CGFloat(indent) * 20)

        case let .task(checked, indent, text, checkboxIndex):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button { vault.toggleTask(atContentIndex: checkboxIndex) } label: {
                    Image(systemName: checked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(checked ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                Text(InlineMarkdown.render(text)).font(.system(size: 16))
                    .strikethrough(checked).foregroundStyle(checked ? .secondary : .primary)
            }
            .padding(.leading, CGFloat(indent) * 20)

        case let .quote(text):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(.secondary.opacity(0.5)).frame(width: 3)
                Text(InlineMarkdown.render(text)).font(.system(size: 16)).foregroundStyle(.secondary)
            }

        case let .callout(kind, title, body):
            calloutView(kind: kind, title: title, body: body)

        case let .code(_, text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text).font(.system(size: 13.5, design: .monospaced)).padding(12)
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
        [28, 23, 19, 17, 16, 15][min(max(level - 1, 0), 5)]
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
