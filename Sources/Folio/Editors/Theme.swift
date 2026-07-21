import AppKit

/// Visual vocabulary for the Live Preview editor. Kept in one place so the
/// styling stays consistent and is easy to tune.
enum Theme {
    static let bodySize: CGFloat = 16

    static let body = NSFont.systemFont(ofSize: bodySize)
    static let bold = NSFont.boldSystemFont(ofSize: bodySize)
    static let italic = NSFontManager.shared.convert(
        NSFont.systemFont(ofSize: bodySize), toHaveTrait: .italicFontMask)
    static let mono = NSFont.monospacedSystemFont(ofSize: bodySize - 1, weight: .regular)

    static let text = NSColor.labelColor
    static let marker = NSColor.tertiaryLabelColor   // dimmed syntax when off the cursor line
    static let accent = NSColor.controlAccentColor
    static let unresolved = NSColor.systemRed      // wikilink to a non-existent note
    static let quote = NSColor.secondaryLabelColor
    static let codeBg = NSColor(white: 0.5, alpha: 0.14)
    static let highlightBg = NSColor.systemYellow.withAlphaComponent(0.30)
    /// Writing mode's current-line wash — just enough to anchor the eye (Zed/
    /// editor convention), quiet enough to disappear while reading the draft.
    static let currentLineBg = NSColor.labelColor.withAlphaComponent(0.045)
    /// Frontmatter comments (`# …` inside YAML) — metadata, never a heading.
    static let yamlComment = NSColor.tertiaryLabelColor

    static func heading(_ level: Int) -> NSFont {
        let sizes: [CGFloat] = [30, 25, 21, 18, 16, 15]
        return NSFont.systemFont(ofSize: sizes[min(max(level - 1, 0), 5)], weight: .bold)
    }
}
