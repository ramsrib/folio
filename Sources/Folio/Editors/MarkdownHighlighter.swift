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
    // Shared with the index — see TagSyntax. Highlighting a token the tag list
    // refuses to file is a lie about what the vault contains.
    private static let tag        = TagSyntax.regex
    private static let highlight  = rx("==([^=\\n]+)==")
    private static let task       = rx("^(\\s*[-*+]\\s+)(\\[[ xX]\\])(.*)$")

    /// - Parameter theme: fonts/metrics for the user's current body size and
    ///   reading font, so writing mode matches reading mode.
    /// - Parameter resolveWikilink: returns true if the target note exists.
    static func apply(to storage: NSTextStorage, theme: Theme, cursorLine: NSRange,
                      resolveWikilink: (String) -> Bool) {
        let text = storage.string
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        storage.beginEditing()
        defer { storage.endEditing() }

        storage.setAttributes(theme.baseAttributes, range: full)

        // Frontmatter is YAML, not Markdown: style it as metadata (mono, dimmed,
        // keys tinted) and — critically — exclude it from every Markdown rule
        // below. A YAML comment (`# deploy notes`) once rendered as a giant H1.
        let fm = frontmatterRange(ns)
        if let fm { styleFrontmatter(storage, ns, fm, theme, cursorLine) }
        let content: NSRange = fm.map {
            NSRange(location: NSMaxRange($0), length: ns.length - NSMaxRange($0))
        } ?? full

        // Block elements, line by line (tracks fenced code regions).
        var fenced: [NSRange] = []
        var inFence = false
        ns.enumerateSubstrings(in: content, options: .byLines) { sub, lineRange, _, _ in
            let line = sub ?? ns.substring(with: lineRange)
            let lineNS = NSRange(location: 0, length: (line as NSString).length)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") { inFence.toggle(); fenced.append(lineRange); return }
            if inFence { fenced.append(lineRange); return }

            if let m = heading.firstMatch(in: line, range: lineNS) {
                let level = m.range(at: 1).length
                storage.addAttribute(.font, value: theme.heading(level), range: lineRange)
                mark(storage, NSRange(location: lineRange.location, length: min(level + 1, lineRange.length)), cursorLine, theme.text)
            } else if let m = task.firstMatch(in: line, range: lineNS) {
                let g1 = m.range(at: 1), g2 = m.range(at: 2), g3 = m.range(at: 3)
                mark(storage, NSRange(location: lineRange.location, length: g1.length + g2.length), cursorLine, theme.text)
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
                storage.addAttribute(.foregroundColor, value: theme.secondary, range: lineRange)
            } else if let m = unordered.firstMatch(in: line, range: lineNS) {
                let r = m.range(at: 1)
                mark(storage, NSRange(location: lineRange.location + r.location, length: r.length), cursorLine, theme.text)
            } else if let m = ordered.firstMatch(in: line, range: lineNS) {
                let r = m.range(at: 1)
                storage.addAttribute(.foregroundColor, value: Theme.accent,
                    range: NSRange(location: lineRange.location + r.location, length: r.length))
            }
        }

        // Inline spans whose content is styled and delimiters dimmed. All scoped
        // to `content` so frontmatter stays pure metadata.
        inline(boldStars,  storage, text, content, cursorLine, [.font: theme.bold], theme.text)
        inline(italicStar, storage, text, content, cursorLine, [.font: theme.italic], theme.text)
        inline(strike,     storage, text, content, cursorLine, [.strikethroughStyle: NSUnderlineStyle.single.rawValue], theme.text)
        inline(inlineCode, storage, text, content, cursorLine, [.font: theme.mono, .backgroundColor: Theme.codeBg], theme.text)
        inline(highlight,  storage, text, content, cursorLine, [.backgroundColor: theme.inlineHighlight], theme.text)

        // Wikilinks: resolved (accent) vs unresolved (red); whole span clickable.
        wiki.enumerateMatches(in: text, range: content) { m, _, _ in
            guard let m else { return }
            let whole = m.range, content = m.range(at: 1)
            let inner = ns.substring(with: content)
            let resolved = resolveWikilink(inner)
            storage.addAttribute(.foregroundColor, value: resolved ? Theme.accent : Theme.unresolved, range: content)
            if let url = wikilinkURL(inner) { storage.addAttribute(.link, value: url, range: whole) }
            mark(storage, NSRange(location: whole.location, length: 2), cursorLine, theme.text)              // [[
            mark(storage, NSRange(location: NSMaxRange(whole) - 2, length: 2), cursorLine, theme.text)       // ]]
        }

        // Markdown links: text styled + clickable, brackets/url dimmed.
        mdLink.enumerateMatches(in: text, range: content) { m, _, _ in
            guard let m else { return }
            let whole = m.range, label = m.range(at: 1), dest = m.range(at: 2)
            storage.addAttributes([.foregroundColor: Theme.accent,
                                   .underlineStyle: NSUnderlineStyle.single.rawValue], range: label)
            if let url = URL(string: ns.substring(with: dest)) { storage.addAttribute(.link, value: url, range: label) }
            mark(storage, NSRange(location: whole.location, length: label.location - whole.location), cursorLine, theme.text)
            let tStart = NSMaxRange(label)
            mark(storage, NSRange(location: tStart, length: NSMaxRange(whole) - tStart), cursorLine, theme.text)
        }

        tag.enumerateMatches(in: text, range: content) { m, _, _ in
            guard let m else { return }
            storage.addAttribute(.foregroundColor, value: Theme.accent, range: m.range)
        }

        for r in fenced { storage.addAttributes([.font: theme.mono, .backgroundColor: Theme.codeBg], range: r) }
    }

    // MARK: Frontmatter

    private static let yamlKey = rx("^\\s*(-\\s+)?[A-Za-z0-9_.-]+(?=:)")
    private static let yamlCommentRx = rx("(^|\\s)#[^\\n]*")

    /// The document's leading `--- … ---` block, including both fence lines,
    /// or nil when the note has no (closed) frontmatter.
    private static func frontmatterRange(_ ns: NSString) -> NSRange? {
        guard ns.length >= 4, ns.substring(to: min(4, ns.length)).hasPrefix("---\n") else { return nil }
        var result: NSRange?
        var first = true
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byLines) { sub, lineRange, _, stop in
            if first { first = false; return }   // the opening fence
            if (sub ?? "").trimmingCharacters(in: .whitespaces) == "---" {
                result = NSRange(location: 0, length: NSMaxRange(lineRange))
                stop.pointee = true
            }
        }
        return result
    }

    /// Metadata styling: mono + dimmed base, keys tinted, YAML comments dimmest,
    /// and the `---` fences on the marker/reveal treatment like other syntax.
    private static func styleFrontmatter(_ storage: NSTextStorage, _ ns: NSString,
                                         _ fm: NSRange, _ theme: Theme, _ cursorLine: NSRange) {
        storage.addAttributes([.font: theme.mono, .foregroundColor: theme.secondary], range: fm)
        ns.enumerateSubstrings(in: fm, options: .byLines) { sub, lineRange, _, _ in
            let line = sub ?? ns.substring(with: lineRange)
            let lineNS = NSRange(location: 0, length: (line as NSString).length)
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                mark(storage, lineRange, cursorLine, theme.text)   // fences dim, reveal on cursor
                return
            }
            if let m = yamlKey.firstMatch(in: line, range: lineNS) {
                storage.addAttribute(.foregroundColor, value: Theme.accent,
                    range: NSRange(location: lineRange.location + m.range.location, length: m.range.length))
            }
            if let m = yamlCommentRx.firstMatch(in: line, range: lineNS) {
                storage.addAttribute(.foregroundColor, value: Theme.yamlComment,
                    range: NSRange(location: lineRange.location + m.range.location, length: m.range.length))
            }
        }
    }

    private static func wikilinkURL(_ inner: String) -> URL? {
        var comps = URLComponents()
        comps.scheme = "folio"
        comps.host = "wikilink"
        comps.queryItems = [URLQueryItem(name: "target", value: inner)]
        return comps.url
    }

    private static func inline(_ regex: NSRegularExpression, _ storage: NSTextStorage,
                               _ text: String, _ full: NSRange, _ cursorLine: NSRange,
                               _ attrs: [NSAttributedString.Key: Any], _ bodyColor: NSColor) {
        regex.enumerateMatches(in: text, range: full) { m, _, _ in
            guard let m else { return }
            let whole = m.range
            let content = m.numberOfRanges > 1 ? m.range(at: 1) : whole
            guard content.location != NSNotFound else { return }
            storage.addAttributes(attrs, range: content)
            let leading = NSRange(location: whole.location, length: content.location - whole.location)
            let tStart = content.location + content.length
            let trailing = NSRange(location: tStart, length: whole.location + whole.length - tStart)
            if leading.length > 0 { mark(storage, leading, cursorLine, bodyColor) }
            if trailing.length > 0 { mark(storage, trailing, cursorLine, bodyColor) }
        }
    }

    private static func mark(_ storage: NSTextStorage, _ range: NSRange, _ cursorLine: NSRange,
                             _ bodyColor: NSColor) {
        let revealed = NSIntersectionRange(range, cursorLine).length > 0
            || NSLocationInRange(range.location, cursorLine)
        storage.addAttribute(.foregroundColor, value: revealed ? bodyColor : Theme.marker, range: range)
    }
}
