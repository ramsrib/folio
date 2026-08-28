import AppKit

/// Visual vocabulary for the Live Preview editor. Kept in one place so the
/// styling stays consistent and is easy to tune.
///
/// Fonts are per-instance because they follow the user's body size and reading
/// font (writing mode must match reading mode exactly — see `Typography`); the
/// colors are fixed, so they stay static.
struct Theme: Equatable {
    let bodySize: CGFloat
    let family: ReadingFont

    let body: NSFont
    let bold: NSFont
    let italic: NSFont
    let mono: NSFont
    /// Shared by every paragraph so line height matches reading mode.
    let paragraphStyle: NSParagraphStyle

    init(bodySize: CGFloat, family: ReadingFont) {
        self.bodySize = bodySize
        self.family = family

        body = family.nsFont(size: bodySize)
        bold = family.nsFont(size: bodySize, weight: .bold)
        italic = NSFontManager.shared.convert(body, toHaveTrait: .italicFontMask)
        mono = NSFont.monospacedSystemFont(ofSize: bodySize * Typography.inlineCode, weight: .regular)

        let style = NSMutableParagraphStyle()
        // `lineSpacing` (not `lineHeightMultiple`): it means the same thing as
        // SwiftUI's `.lineSpacing` — points between line fragments — so reading
        // and writing mode land on the same line height from the same constant.
        // `lineHeightMultiple` would also shift baselines within the line box and
        // drag the caret off the text.
        style.lineSpacing = bodySize * Typography.lineSpacing
        paragraphStyle = style
    }

    @MainActor init(_ settings: AppSettings) {
        self.init(bodySize: settings.bodyFontSize, family: settings.readingFont)
    }

    func heading(_ level: Int) -> NSFont {
        family.nsFont(size: Typography.headingSize(level, body: bodySize), weight: .bold)
    }

    /// Base attributes for the whole document — the floor every syntax rule
    /// paints over.
    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: body, .foregroundColor: Theme.text, .paragraphStyle: paragraphStyle]
    }

    static func == (a: Theme, b: Theme) -> Bool {
        a.bodySize == b.bodySize && a.family == b.family
    }

    // MARK: Colors

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
}

extension ReadingFont {
    /// AppKit counterpart of `design`: writing mode needs real `NSFont`s, and it
    /// has to honor the same family the reader is using.
    func nsFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        switch self {
        case .system:
            return base
        case .mono:
            return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        case .serif:
            guard let descriptor = base.fontDescriptor.withDesign(.serif),
                  let font = NSFont(descriptor: descriptor, size: size) else { return base }
            return font
        }
    }
}
