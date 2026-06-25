import AppKit

/// Applies Live-Preview styling to a literal-Markdown `NSTextStorage`.
///
/// The text is never altered — only attributes are set, so the on-disk content
/// stays byte-for-byte identical. Syntax markers (`**`, `#`, `` ` ``, …) are
/// *dimmed* when the cursor is on another line and shown normally when the
/// cursor is on their line — Obsidian's "reveal on edit" behaviour. Wikilinks
/// and Markdown links also get a `.link` attribute so they're clickable.
enum MarkdownHighlighter {
    private static func rx(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }

    private static let heading    = rx("^(#{1,6})\\s+.*")
    private static let unordered  = rx("^\\s*([-*+])\\s+")
    private static let ordered    = rx("^\\s*(\\d+[.)])\\s+")
    private static let boldStars  = rx("\\*\\*([^*\\n]+)\\*\\*")
    private static let italicStar = rx("(?<!\\*)\\*(?!\\*)([^*\\n]+)\\*(?!\\*)")
    private static let inlineCode = rx("`([^`\\n]+)`")
    private static let strike     = rx("~~([^~\\n]+)~~")
    private static let mdLink     = rx("\\[([^\\]\\n]+)\\]\\(([^)\\n]+)\\)")
    private static let wiki       = rx("\\[\\[([^\\]\\n]+)\\]\\]")
    private static let tag        = rx("(?<!\\S)#([A-Za-z0-9_/-]+)")
    private static let highlight  = rx("==([^=\\n]+)==")
    private static let task       = rx("^(\\s*[-*+]\\s+)(\\[[ xX]\\])(.*)$")

    /// - Parameter resolveWikilink: returns true if the target note exists.
    static func apply(to storage: NSTextStorage, cursorLine: NSRange,
                      resolveWikilink: (String) -> Bool) {
        let text = storage.string
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        storage.beginEditing()
        defer { storage.endEditing() }

        storage.setAttributes([.font: Theme.body, .foregroundColor: Theme.text], range: full)

        // Block elements, line by line (tracks fenced code regions).
        var fenced: [NSRange] = []
        var inFence = false
        ns.enumerateSubstrings(in: full, options: .byLines) { sub, lineRange, _, _ in
            let line = sub ?? ns.substring(with: lineRange)
            let lineNS = NSRange(location: 0, length: (line as NSString).length)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") { inFence.toggle(); fenced.append(lineRange); return }
            if inFence { fenced.append(lineRange); return }

            if let m = heading.firstMatch(in: line, range: lineNS) {
                let level = m.range(at: 1).length
                storage.addAttribute(.font, value: Theme.heading(level), range: lineRange)
                mark(storage, NSRange(location: lineRange.location, length: min(level + 1, lineRange.length)), cursorLine)
            } else if let m = task.firstMatch(in: line, range: lineNS) {
                let g1 = m.range(at: 1), g2 = m.range(at: 2), g3 = m.range(at: 3)
                mark(storage, NSRange(location: lineRange.location, length: g1.length + g2.length), cursorLine)
                let checked = ns.substring(
                    with: NSRange(location: lineRange.location + g2.location + 1, length: 1)).lowercased() == "x"
                if checked {
                    storage.addAttribute(.foregroundColor, value: Theme.accent,
                        range: NSRange(location: lineRange.location + g2.location, length: g2.length))
                    if g3.length > 0 {
                        storage.addAttributes(
                            [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: Theme.marker],
                            range: NSRange(location: lineRange.location + g3.location, length: g3.length))
                    }
                }
            } else if trimmed.hasPrefix(">") {
                storage.addAttribute(.foregroundColor, value: Theme.quote, range: lineRange)
            } else if let m = unordered.firstMatch(in: line, range: lineNS) {
                let r = m.range(at: 1)
                mark(storage, NSRange(location: lineRange.location + r.location, length: r.length), cursorLine)
            } else if let m = ordered.firstMatch(in: line, range: lineNS) {
                let r = m.range(at: 1)
                storage.addAttribute(.foregroundColor, value: Theme.accent,
                    range: NSRange(location: lineRange.location + r.location, length: r.length))
            }
        }

        // Inline spans whose content is styled and delimiters dimmed.
        inline(boldStars,  storage, text, full, cursorLine, [.font: Theme.bold])
        inline(italicStar, storage, text, full, cursorLine, [.font: Theme.italic])
        inline(strike,     storage, text, full, cursorLine, [.strikethroughStyle: NSUnderlineStyle.single.rawValue])
        inline(inlineCode, storage, text, full, cursorLine, [.font: Theme.mono, .backgroundColor: Theme.codeBg])
        inline(highlight,  storage, text, full, cursorLine, [.backgroundColor: Theme.highlightBg])

        // Wikilinks: resolved (accent) vs unresolved (red); whole span clickable.
        wiki.enumerateMatches(in: text, range: full) { m, _, _ in
            guard let m else { return }
            let whole = m.range, content = m.range(at: 1)
            let inner = ns.substring(with: content)
            let resolved = resolveWikilink(inner)
            storage.addAttribute(.foregroundColor, value: resolved ? Theme.accent : Theme.unresolved, range: content)
            if let url = wikilinkURL(inner) { storage.addAttribute(.link, value: url, range: whole) }
            mark(storage, NSRange(location: whole.location, length: 2), cursorLine)              // [[
            mark(storage, NSRange(location: NSMaxRange(whole) - 2, length: 2), cursorLine)       // ]]
        }

        // Markdown links: text styled + clickable, brackets/url dimmed.
        mdLink.enumerateMatches(in: text, range: full) { m, _, _ in
            guard let m else { return }
            let whole = m.range, label = m.range(at: 1), dest = m.range(at: 2)
            storage.addAttributes([.foregroundColor: Theme.accent,
                                   .underlineStyle: NSUnderlineStyle.single.rawValue], range: label)
            if let url = URL(string: ns.substring(with: dest)) { storage.addAttribute(.link, value: url, range: label) }
            mark(storage, NSRange(location: whole.location, length: label.location - whole.location), cursorLine)
            let tStart = NSMaxRange(label)
            mark(storage, NSRange(location: tStart, length: NSMaxRange(whole) - tStart), cursorLine)
        }

        tag.enumerateMatches(in: text, range: full) { m, _, _ in
            guard let m else { return }
            storage.addAttribute(.foregroundColor, value: Theme.accent, range: m.range)
        }

        for r in fenced { storage.addAttributes([.font: Theme.mono, .backgroundColor: Theme.codeBg], range: r) }
    }

    private static func wikilinkURL(_ inner: String) -> URL? {
        var comps = URLComponents()
        comps.scheme = "slate"
        comps.host = "wikilink"
        comps.queryItems = [URLQueryItem(name: "target", value: inner)]
        return comps.url
    }

    private static func inline(_ regex: NSRegularExpression, _ storage: NSTextStorage,
                               _ text: String, _ full: NSRange, _ cursorLine: NSRange,
                               _ attrs: [NSAttributedString.Key: Any]) {
        regex.enumerateMatches(in: text, range: full) { m, _, _ in
            guard let m else { return }
            let whole = m.range
            let content = m.numberOfRanges > 1 ? m.range(at: 1) : whole
            guard content.location != NSNotFound else { return }
            storage.addAttributes(attrs, range: content)
            let leading = NSRange(location: whole.location, length: content.location - whole.location)
            let tStart = content.location + content.length
            let trailing = NSRange(location: tStart, length: whole.location + whole.length - tStart)
            if leading.length > 0 { mark(storage, leading, cursorLine) }
            if trailing.length > 0 { mark(storage, trailing, cursorLine) }
        }
    }

    private static func mark(_ storage: NSTextStorage, _ range: NSRange, _ cursorLine: NSRange) {
        let revealed = NSIntersectionRange(range, cursorLine).length > 0
            || NSLocationInRange(range.location, cursorLine)
        storage.addAttribute(.foregroundColor, value: revealed ? Theme.text : Theme.marker, range: range)
    }
}
