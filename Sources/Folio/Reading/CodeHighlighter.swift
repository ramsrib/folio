import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Lightweight, language-agnostic syntax highlighter for fenced code blocks in
/// Reading mode. Not a full parser — regex passes for comments, strings,
/// numbers, and a broad set of common keywords. Good enough to make code legible.
enum CodeHighlighter {
    private static let mono = PlatformFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)

    private static let keywords: Set<String> = [
        "func", "function", "fn", "def", "let", "var", "const", "val", "mut",
        "if", "else", "elif", "for", "while", "do", "switch", "case", "default",
        "break", "continue", "return", "yield", "guard", "defer", "in", "of",
        "class", "struct", "enum", "protocol", "interface", "extension", "trait",
        "import", "export", "from", "package", "module", "use", "using", "namespace",
        "public", "private", "protected", "internal", "static", "final", "override",
        "async", "await", "try", "catch", "throw", "throws", "finally",
        "new", "this", "self", "super", "nil", "null", "none", "true", "false",
        "void", "int", "string", "bool", "float", "double", "char", "type",
        "extends", "implements", "where", "as", "is", "and", "or", "not", "with",
        "lambda", "pass", "end", "then", "begin", "match", "when", "go", "defer",
    ]

    private static func rx(_ p: String, _ opts: NSRegularExpression.Options = []) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: opts)
    }
    private static let identifier = rx("\\b[A-Za-z_][A-Za-z0-9_]*\\b")
    private static let number = rx("\\b\\d[\\d_]*(?:\\.\\d+)?\\b")
    private static let string = rx("\"[^\"\\n]*\"|'[^'\\n]*'|`[^`]*`")
    private static let comment = rx("//[^\\n]*|#[^\\n]*|/\\*.*?\\*/|--[^\\n]*", [.dotMatchesLineSeparators])

    /// Highlighted-block memo — same rationale as `InlineMarkdown`'s cache: the
    /// regex passes re-ran for every visible code block on every tab switch.
    @MainActor private static var cache: [String: AttributedString] = [:]

    @MainActor static func highlight(_ code: String, language: String) -> AttributedString {
        let key = language + "\u{0}" + code
        if let hit = cache[key] { return hit }
        let rendered = highlightUncached(code, language: language)
        if cache.count > 512 { cache.removeAll(keepingCapacity: true) }
        cache[key] = rendered
        return rendered
    }

    private static func highlightUncached(_ code: String, language: String) -> AttributedString {
        let storage = NSMutableAttributedString(
            string: code, attributes: [.font: mono, .foregroundColor: PlatformColor.pLabel])
        let full = NSRange(location: 0, length: (code as NSString).length)
        let ns = code as NSString

        // Keywords (applied first; strings/comments override them where overlapping).
        identifier.enumerateMatches(in: code, range: full) { m, _, _ in
            guard let m else { return }
            if keywords.contains(ns.substring(with: m.range)) {
                storage.addAttribute(.foregroundColor, value: PlatformColor.systemPink, range: m.range)
            }
        }
        apply(number, code, full, storage, .systemOrange)
        apply(string, code, full, storage, .systemGreen)
        apply(comment, code, full, storage, .pSecondaryLabel)

        return AttributedString(storage)
    }

    private static func apply(_ regex: NSRegularExpression, _ code: String, _ full: NSRange,
                              _ storage: NSMutableAttributedString, _ color: PlatformColor) {
        regex.enumerateMatches(in: code, range: full) { m, _, _ in
            guard let m else { return }
            storage.addAttribute(.foregroundColor, value: color, range: m.range)
        }
    }
}
