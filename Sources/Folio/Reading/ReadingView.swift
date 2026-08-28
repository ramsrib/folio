// The block-per-view reader, now iOS-only: macOS reading mode is `NoteReader`,
// which lays the note out as one selectable text stream (`NoteTextView`). iOS
// keeps this until it gets the same TextKit treatment.
#if !os(macOS)
import SwiftUI
import os
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Notion-style fully-rendered, read-(mostly)-only view of the current note.
/// No syntax symbols — headings, lists, checkboxes, callouts, code, tables,
/// dividers, and images are drawn as native views.
struct ReadingView: View {
    @ObservedObject var find: FindModel
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var settings: AppSettings

    // Parsed once per content change (not on every redraw/scroll). Two variants:
    // `parsed` keeps every paragraph as its own block (find-in-page needs that
    // granularity to scroll to a match); `mergedBlocks` collapses runs of
    // consecutive paragraphs into one block so text selection — which macOS can't
    // extend across separate Text views — flows over whole stretches of prose.
    // Reading uses the merged variant except while the find bar is active.
    @State private var parsed: [Block] = []
    @State private var mergedBlocks: [Block] = []
    private var blocks: [Block] { find.active ? parsed : mergedBlocks }
    private var body0: CGFloat { settings.bodyFontSize }
    private var design: Font.Design { settings.readingFont.design }

    // Everything below derives from `body0` so ⌘+/⌘− scales the whole note, not
    // just its prose, and so one line-height constant governs every text block.
    private var lineSpacing: CGFloat { body0 * Typography.lineSpacing }
    private var inlineCodeSize: CGFloat { body0 * Typography.inlineCode }
    private var blockSpacing: CGFloat { body0 * Typography.blockSpacing }
    private var listIndent: CGFloat { body0 * Typography.listIndent }

    /// Inline Markdown with `code` runs sized against the surrounding text —
    /// body size by default, or `base` for the fixed-size metadata chrome.
    private func inline(_ text: String, base: CGFloat? = nil) -> AttributedString {
        InlineMarkdown.render(text, codeSize: (base ?? body0) * Typography.inlineCode)
    }

    // Ordered occurrences across searchable blocks. Maps the shared model's
    // `current` index to a block (for scrolling) and its occurrence within that
    // block (for the stronger current-match tint). `findScroll` triggers the scroll.
    @State private var findMatches: [FindLoc] = []
    @State private var findScroll: Int?
    // Properties (frontmatter) start collapsed — reading the *content* is the
    // point of opening a note; metadata is one click away. Lives here (not in
    // PropertiesView) so a content re-parse mid-note (e.g. toggling a checkbox)
    // doesn't snap an expanded card shut; switching notes re-collapses below.
    @State private var propsExpanded = false

    private struct FindLoc: Equatable { let block: Int; let occ: Int }

    /// Parsed-block memo across tab switches, keyed by content length + hash.
    @MainActor private static var parseCache: [String: ([Block], [Block])] = [:]

    /// The parse task's identity. Constant while the view is hidden behind the
    /// editor (so keystrokes never re-fire it); flips to the content's identity
    /// when reading returns — re-parsing exactly once if edits happened, and not
    /// at all if they didn't.
    private var parseTaskID: Int {
        guard ui.mode == .read else { return .min }
        // Include the line-break preference so toggling it re-parses live.
        return vault.content.count &+ vault.content.hashValue &* 31
            &+ settings.lineBreaks.rawValue.hashValue
    }

    @ViewBuilder private var blockRows: some View {
        ForEach(Array(blocks.enumerated()), id: \.element.id) { i, block in
            view(for: block, index: i).id(anchorID(block))
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Non-lazy for normal documents: LazyVStack only *estimates* the
                // height of unrealized rows, so restoring a remembered pixel offset
                // (ScrollMemory) landed near-but-not-on the old spot and drifted as
                // rows realized. A plain VStack lays out exact geometry every time —
                // scroll restore is pinned to the pixel. Lazy only kicks in for very
                // large documents, where full layout would cost real time and a
                // slightly drifty restore is the better trade.
                Group {
                    // Gate on content size too: a 370KB doc can be only ~125
                    // blocks, but full non-lazy Core Text layout of it per switch
                    // is a visible stall — big documents keep the lazy layout
                    // (slightly drifty scroll restore is the better trade there).
                    if blocks.count > 400 || vault.content.count > 150_000 {
                        LazyVStack(alignment: .leading, spacing: blockSpacing) { blockRows }
                    } else {
                        VStack(alignment: .leading, spacing: blockSpacing) { blockRows }
                    }
                }
                .frame(maxWidth: settings.columnWidth, alignment: .leading)
                .frame(maxWidth: .infinity, minHeight: 200, alignment: .top)
                .contentShape(Rectangle())
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                // No double-click-to-edit: double-clicks happen constantly while
                // reading (word selection), and silently flipping into writing mode
                // reads as random. Mode changes are explicit only — the toolbar
                // pencil or ⌘E.
                // Vim-style j/k/h/l scrolling (macOS only — AppKit-backed). Only
                // while visible: the view stays mounted behind the editor, and a
                // hidden scroller must not eat j/k when the editor loses focus.
                #if os(macOS)
                .background { if ui.mode == .read { KeyboardScroller() } }
                // Per-note scroll memory: restore each note's own offset on tab
                // switch (top for first visits). A find/search jump or heading
                // scroll owns the position for that switch and wins.
                .background(ScrollMemory(noteID: vault.selection, positionOwnedElsewhere: {
                    (find.active && !find.query.isEmpty) || vault.scrollRequest != nil || ui.pendingFind != nil
                }))
                #endif
            }
            .task(id: parseTaskID) {
                guard ui.mode == .read else { return }
                let t0 = ContinuousClock.now
                // Per-document parse memo: tab switches re-run this task with
                // content that was parsed moments ago (twice, in fact — the view
                // updates once with the old content before the new one lands).
                // Reusing cached blocks also keeps their identities stable, which
                // lets SwiftUI diff the list instead of rebuilding every row.
                let key = "\(vault.content.count)|\(vault.content.hashValue)|\(settings.lineBreaks.rawValue)"
                if let hit = Self.parseCache[key] {
                    (parsed, mergedBlocks) = hit
                } else {
                    parsed = MarkdownParser.parse(vault.content,
                                                  lineBreaks: settings.lineBreaks)
                    mergedBlocks = Self.mergeParagraphRuns(parsed)
                    if Self.parseCache.count > 24 { Self.parseCache.removeAll(keepingCapacity: true) }
                    Self.parseCache[key] = (parsed, mergedBlocks)
                }
                recomputeMatches(); scrollToCurrent()
                let us = (ContinuousClock.now - t0).components.attoseconds / 1_000_000_000_000
                Logger(subsystem: "com.sriramb.folio", category: "perf")
                    .debug("reading parse: \(us)µs (\(parsed.count) blocks)")
            }
            .onChange(of: vault.scrollRequest) {
                // Only when visible — mounted-but-hidden must not steal the
                // request from the editor (which consumes it via its binding).
                if ui.mode == .read, let req = vault.scrollRequest {
                    withAnimation(.smooth) { proxy.scrollTo(req, anchor: .top) }
                    vault.scrollRequest = nil
                }
            }
            .onChange(of: vault.selection) { propsExpanded = false }   // each note opens collapsed
            // `current` is already zeroed by FindModel.query.didSet; don't re-zero
            // it here, so a search jump can set `current` right after `query` and
            // have it survive the recompute (see EditorPane.consumePendingFind).
            .onChange(of: find.query) { recomputeMatches(); scrollToCurrent() }
            .onChange(of: find.caseSensitive) { recomputeMatches(); scrollToCurrent() }
            .onChange(of: find.active) { recomputeMatches(); scrollToCurrent() }
            .onChange(of: find.current) { scrollToCurrent() }
            .onChange(of: findScroll) {
                if let anchor = findScroll {
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(anchor, anchor: .center) }
                }
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "folio", url.host == "wikilink" {
                let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "target" })?.value ?? ""
                #if os(macOS)
                let newTab = NSApp.currentEvent?.modifierFlags.contains(.command) ?? false
                #else
                let newTab = false
                #endif
                vault.openWikilink(target, inNewTab: newTab); return .handled
            }
            // Relative `[text](docs/plan.md)` links have no scheme (file: links are
            // the absolute cousins) — the system can't open those (Finder's "-50");
            // resolve them against the note/vault ourselves.
            if url.scheme == nil || url.isFileURL {
                vault.openLocalLink(url.isFileURL ? url.path : url.absoluteString)
                return .handled
            }
            return .systemAction   // http(s), mailto, … → the system
        })
        .textSelection(.enabled)
    }

    private func anchorID(_ block: Block) -> Int {
        if case let .heading(_, _, anchor) = block.kind { return anchor }
        return -block.id.hashValue
    }

    /// Collapse runs of consecutive paragraphs into single blocks, joined with
    /// "\n\n". With line breaks preserved a paragraph can contain single "\n"s,
    /// but never a blank line — so the double-newline separator stays
    /// unambiguous. One block = one Text = one selectable flow.
    ///
    /// Runs are capped: an unbounded merge turned prose-heavy documents into a
    /// few enormous Texts, and Core Text laying those out on every tab switch
    /// was a visible stall. Selection still flows across a cap's worth of
    /// paragraphs — selecting more than ~24 at once is a rare act.
    private static let mergeRunCap = 24

    private static func mergeParagraphRuns(_ blocks: [Block]) -> [Block] {
        var out: [Block] = []
        var run: [String] = []
        func flush() {
            guard !run.isEmpty else { return }
            out.append(Block(kind: .paragraph(text: run.joined(separator: "\n\n"))))
            run = []
        }
        for b in blocks {
            if case let .paragraph(t) = b.kind {
                run.append(t)
                if run.count >= mergeRunCap { flush() }
            } else { flush(); out.append(b) }
        }
        flush()
        return out
    }

    /// Render a (possibly merged) paragraph block. The blank separator line gets
    /// a much smaller font so the visual gap inside a merged run stays close to
    /// the 16pt block spacing — otherwise merging would widen the paragraph
    /// rhythm. Must be used by *both* the view and `searchAttr` so find-match
    /// ranges line up with what's displayed.
    private func renderParagraph(_ text: String) -> AttributedString {
        let parts = text.components(separatedBy: "\n\n")
        guard parts.count > 1 else { return inline(text) }
        var out = AttributedString()
        for (i, part) in parts.enumerated() {
            if i > 0 {
                var sep = AttributedString("\n\n")
                sep.font = .system(size: body0 * 0.3, design: design)
                out += sep
            }
            out += inline(part)
        }
        return out
    }

    // MARK: - Find in page

    /// The rendered text a block contributes to search — nil for blocks we don't
    /// highlight yet (callouts, tables, properties, images).
    private func searchAttr(_ block: Block) -> AttributedString? {
        switch block.kind {
        case let .heading(_, t, _):     return inline(t)
        case let .paragraph(t):         return renderParagraph(t)
        case let .listItem(_, _, _, t): return inline(t)
        case let .task(_, _, t, _):     return inline(t)
        case let .quote(t):             return inline(t)
        case let .code(lang, t):        return CodeHighlighter.highlight(t, language: lang,
                                                                        size: body0 * Typography.codeBlock)
        default:                        return nil
        }
    }

    private func matchRanges(in attr: AttributedString, query: String) -> [Range<AttributedString.Index>] {
        guard !query.isEmpty else { return [] }
        var out: [Range<AttributedString.Index>] = []
        let options = find.options
        var start = attr.startIndex
        while start < attr.endIndex, let r = attr[start..<attr.endIndex].range(of: query, options: options) {
            out.append(r)
            start = r.upperBound
        }
        return out
    }

    /// Tint every match in a block's text; the current match gets a stronger fill.
    private func applyFindHighlight(_ attr: AttributedString, blockIndex: Int) -> AttributedString {
        guard find.active, !find.query.isEmpty else { return attr }
        var result = attr
        let ranges = matchRanges(in: result, query: find.query)
        guard !ranges.isEmpty else { return result }
        let cur = findMatches.indices.contains(find.current) ? findMatches[find.current] : nil
        for (k, r) in ranges.enumerated() {
            let isCurrent = cur?.block == blockIndex && cur?.occ == k
            result[r].backgroundColor = isCurrent ? Color.orange.opacity(0.9) : Color.yellow.opacity(0.4)
            if isCurrent { result[r].foregroundColor = .black }
        }
        return result
    }

    private func recomputeMatches() {
        // Hidden behind the editor: the editor owns the shared FindModel's
        // totals; a stale-block recompute here would fight it.
        guard ui.mode == .read else { return }
        guard find.active, !find.query.isEmpty else {
            findMatches = []
            if find.total != 0 { find.total = 0 }
            return
        }
        var locs: [FindLoc] = []
        for (i, block) in blocks.enumerated() {
            guard let attr = searchAttr(block) else { continue }
            let count = matchRanges(in: attr, query: find.query).count
            for k in 0..<count { locs.append(FindLoc(block: i, occ: k)) }
        }
        findMatches = locs
        if find.total != locs.count { find.total = locs.count }
        if find.current >= locs.count { find.current = max(0, locs.count - 1) }
    }

    private func scrollToCurrent() {
        guard ui.mode == .read else { return }
        guard find.active, findMatches.indices.contains(find.current) else { return }
        findScroll = anchorID(blocks[findMatches[find.current].block])
    }

    @ViewBuilder
    private func view(for block: Block, index: Int) -> some View {
        switch block.kind {
        case let .properties(props):
            PropertiesView(props: props, expanded: $propsExpanded)

        case let .heading(level, text, _):
            // Generous air above section headings (Notion-grade rhythm): the gap
            // above a heading should read clearly larger than the paragraph gaps
            // inside its section, so section boundaries land while scanning. No
            // extra padding when the heading opens the document.
            Text(applyFindHighlight(inline(text), blockIndex: index))
                .font(.system(size: headingSize(level), weight: level <= 2 ? .bold : .semibold, design: design))
                .tracking(Typography.tracking(forSize: headingSize(level)))
                .lineSpacing(headingSize(level) * Typography.headingLineSpacing)
                .padding(.top, index == 0 ? 0 : body0 * Typography.headingTopPadding(level: level))

        case let .paragraph(text):
            Text(applyFindHighlight(renderParagraph(text), blockIndex: index))
                .font(.system(size: body0, design: design)).lineSpacing(lineSpacing)

        case let .listItem(ordered, number, indent, text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(ordered ? "\(number)." : "•").font(.system(size: body0)).foregroundStyle(.secondary)
                Text(applyFindHighlight(inline(text), blockIndex: index))
                    .font(.system(size: body0, design: design)).lineSpacing(lineSpacing)
            }
            .padding(.leading, CGFloat(indent) * listIndent)

        case let .task(checked, indent, text, checkboxIndex):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button { vault.toggleTask(atContentIndex: checkboxIndex) } label: {
                    Image(systemName: checked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(checked ? Color.accentColor : .secondary)
                        .font(.system(size: body0 * 0.94))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(checked ? "Completed task" : "Incomplete task")
                .accessibilityAddTraits(.isButton)
                Text(applyFindHighlight(inline(text), blockIndex: index))
                    .font(.system(size: body0, design: design)).lineSpacing(lineSpacing)
                    .strikethrough(checked).foregroundStyle(checked ? .secondary : .primary)
            }
            .padding(.leading, CGFloat(indent) * listIndent)

        case let .quote(text):
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2).fill(.secondary.opacity(0.5)).frame(width: 3)
                Text(applyFindHighlight(inline(text), blockIndex: index))
                    .font(.system(size: body0, design: design)).lineSpacing(lineSpacing)
                    .foregroundStyle(.secondary)
            }

        case let .callout(kind, title, body):
            calloutView(kind: kind, title: title, body: body)

        case let .code(language, text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(applyFindHighlight(CodeHighlighter.highlight(text, language: language,
                                                                  size: body0 * Typography.codeBlock),
                                        blockIndex: index))
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
            Image(systemName: icon).foregroundStyle(tint)
                .font(.system(size: body0 * 0.94, weight: .semibold))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: body0 * Typography.callout, weight: .semibold))
                if !body.isEmpty {
                    Text(inline(body))
                        .font(.system(size: body0 * Typography.callout, design: design))
                        .lineSpacing(lineSpacing)
                }
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
                Text(c < cells.count ? inline(cells[c]) : AttributedString(""))
                    .font(.system(size: body0 * Typography.table, weight: bold ? .semibold : .regular))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                if c < columns - 1 { Divider() }
            }
        }
    }

    // MARK: helpers

    private func headingSize(_ level: Int) -> CGFloat {
        Typography.headingSize(level, body: body0)
    }

    private func localImage(_ source: String) -> PlatformImage? {
        NoteImageLoader.load(source, noteURL: vault.selection, vaultURL: vault.vaultURL)
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
#endif
