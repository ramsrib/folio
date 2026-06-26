import AppKit

/// Lightweight, language-agnostic syntax highlighter for fenced code blocks in
/// Reading mode. Not a full parser — regex passes for comments, strings,
/// numbers, and a broad set of common keywords. Good enough to make code legible.
enum CodeHighlighter {
    private static let mono = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)

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

    static func highlight(_ code: String, language: String) -> AttributedString {
        let storage = NSMutableAttributedString(
            string: code, attributes: [.font: mono, .foregroundColor: NSColor.labelColor])
        let full = NSRange(location: 0, length: (code as NSString).length)
        let ns = code as NSString

        // Keywords (applied first; strings/comments override them where overlapping).
        identifier.enumerateMatches(in: code, range: full) { m, _, _ in
            guard let m else { return }
            if keywords.contains(ns.substring(with: m.range)) {
                storage.addAttribute(.foregroundColor, value: NSColor.systemPink, range: m.range)
            }
        }
        apply(number, code, full, storage, .systemOrange)
        apply(string, code, full, storage, .systemGreen)
        apply(comment, code, full, storage, .secondaryLabelColor)

        return AttributedString(storage)
    }

    private static func apply(_ regex: NSRegularExpression, _ code: String, _ full: NSRange,
                              _ storage: NSMutableAttributedString, _ color: NSColor) {
        regex.enumerateMatches(in: code, range: full) { m, _, _ in
            guard let m else { return }
            storage.addAttribute(.foregroundColor, value: color, range: m.range)
        }
    }
}
