import Foundation
import SwiftUI

/// Renders a line of inline Markdown to a clean `AttributedString` (markers
/// removed) for Reading mode. Uses Foundation's built-in inline Markdown parser
/// for bold/italic/code/strikethrough/links, after rewriting wikilinks into
/// real links and stripping `==highlight==` markers.
enum InlineMarkdown {
    private static let wiki = try! NSRegularExpression(pattern: "\\[\\[([^\\]\\n]+)\\]\\]")
    private static let highlight = try! NSRegularExpression(pattern: "==([^=\\n]+)==")

    /// Rendered-line memo. `render` runs a full Foundation Markdown parse per
    /// call and is invoked for every visible block on every tab switch — without
    /// this, flipping back to a tab re-parses text that hasn't changed (the
    /// reported switch lag). Keyed by the raw source line; crude wholesale reset
    /// when it grows past a bound (cheap to refill, and re-tuning beats an LRU).
    @MainActor private static var cache: [String: AttributedString] = [:]

    @MainActor static func render(_ raw: String) -> AttributedString {
        if let hit = cache[raw] { return hit }
        let rendered = renderUncached(raw)
        if cache.count > 4096 { cache.removeAll(keepingCapacity: true) }
        cache[raw] = rendered
        return rendered
    }

    private static func renderUncached(_ raw: String) -> AttributedString {
        let transformed = transform(raw)
        let opts = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible)
        guard var attr = try? AttributedString(markdown: transformed, options: opts) else {
            return AttributedString(raw)
        }
        // Style inline `code` spans as subtle monospaced pills (like Obsidian).
        let codeRanges = attr.runs.compactMap {
            ($0.inlinePresentationIntent?.contains(.code) == true) ? $0.range : nil
        }
        for r in codeRanges {
            attr[r].font = .system(size: 14.5, design: .monospaced)
            attr[r].backgroundColor = Color.primary.opacity(0.06)
        }
        return attr
    }

    private static func transform(_ raw: String) -> String {
        // ==highlight== -> highlight (drop markers; Markdown has no equivalent)
        var s = highlight.stringByReplacingMatches(
            in: raw, range: NSRange(location: 0, length: (raw as NSString).length), withTemplate: "$1")

        // [[target|alias]] / [[target#heading]] -> [display](folio://wikilink?target=…)
        let ns = s as NSString
        let matches = wiki.matches(in: s, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return s }
        var out = ""; var last = 0
        for m in matches {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let inner = ns.substring(with: m.range(at: 1))
            let parts = inner.split(separator: "|", maxSplits: 1).map(String.init)
            let rawTarget = parts.first ?? inner
            let target = rawTarget.split(separator: "#").first.map(String.init) ?? rawTarget
            let display = parts.count > 1 ? parts[1] : rawTarget
            var comps = URLComponents(); comps.scheme = "folio"; comps.host = "wikilink"
            comps.queryItems = [URLQueryItem(name: "target", value: target)]
            out += "[\(display)](\(comps.url?.absoluteString ?? "folio://wikilink"))"
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        s = out
        return s
    }
}
