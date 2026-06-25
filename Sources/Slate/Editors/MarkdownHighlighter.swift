import AppKit

/// Applies Live-Preview styling to a literal-Markdown `NSTextStorage`.
///
/// The text is never altered — only attributes are set, so the on-disk content
/// stays byte-for-byte identical. Syntax markers (`**`, `#`, `` ` ``, …) are
/// *dimmed* when the cursor is on another line and shown normally when the
/// cursor is on their line — Obsidian's "reveal on edit" behaviour.
enum MarkdownHighlighter {
    private static func rx(_ p: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p)
    }

    private static let heading   = rx("^(#{1,6})\\s+.*")
    private static let unordered = rx("^\\s*([-*+])\\s+")
    private static let ordered   = rx("^\\s*(\\d+[.)])\\s+")
    private static let boldStars = rx("\\*\\*([^*\\n]+)\\*\\*")
    private static let italicStar = rx("(?<!\\*)\\*(?!\\*)([^*\\n]+)\\*(?!\\*)")
    private static let inlineCode = rx("`([^`\\n]+)`")
    private static let strike    = rx("~~([^~\\n]+)~~")
    private static let link      = rx("\\[([^\\]\\n]+)\\]\\(([^)\\n]+)\\)")
    private static let wiki      = rx("\\[\\[([^\\]\\n]+)\\]\\]")
    private static let tag       = rx("(?<!\\S)#([A-Za-z0-9_/-]+)")

    static func apply(to storage: NSTextStorage, cursorLine: NSRange) {
        let text = storage.string
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        storage.beginEditing()
        defer { storage.endEditing() }

        // 1. Reset everything to the body style.
        storage.setAttributes([.font: Theme.body, .foregroundColor: Theme.text], range: full)

        // 2. Block elements, line by line (also tracks fenced code regions).
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
                let markerLen = min(level + 1, lineRange.length)
                mark(storage, NSRange(location: lineRange.location, length: markerLen), cursorLine)
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

        // 3. Inline spans (content styled, delimiters treated as markers).
        inline(boldStars,  storage, text, full, cursorLine, [.font: Theme.bold])
        inline(italicStar, storage, text, full, cursorLine, [.font: Theme.italic])
        inline(strike,     storage, text, full, cursorLine, [.strikethroughStyle: NSUnderlineStyle.single.rawValue])
        inline(wiki,       storage, text, full, cursorLine, [.foregroundColor: Theme.accent])
        inline(link,       storage, text, full, cursorLine, [.foregroundColor: Theme.accent,
                                                              .underlineStyle: NSUnderlineStyle.single.rawValue])
        inline(inlineCode, storage, text, full, cursorLine, [.font: Theme.mono, .backgroundColor: Theme.codeBg])

        tag.enumerateMatches(in: text, range: full) { m, _, _ in
            guard let m else { return }
            storage.addAttribute(.foregroundColor, value: Theme.accent, range: m.range)
        }

        // 4. Fenced code overrides any inline styling that fell inside it.
        for r in fenced {
            storage.addAttributes([.font: Theme.mono, .backgroundColor: Theme.codeBg], range: r)
        }
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
