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
    /// Body and dimmed text. Per-theme rather than static, because Paper's dark
    /// side warms them and every other theme keeps the system label colors.
    let text: NSColor
    let secondary: NSColor
    /// `==mark==` wash.
    let inlineHighlight: NSColor

    let body: NSFont
    let bold: NSFont
    let italic: NSFont
    let mono: NSFont
    /// Shared by every paragraph so line height matches reading mode.
    let paragraphStyle: NSParagraphStyle

    init(bodySize: CGFloat, family: ReadingFont,
         text: NSColor = .labelColor, secondary: NSColor = .secondaryLabelColor,
         inlineHighlight: NSColor = NSColor.systemYellow.withAlphaComponent(0.30)) {
        self.bodySize = bodySize
        self.family = family
        self.text = text
        self.secondary = secondary
        self.inlineHighlight = inlineHighlight

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
        self.init(bodySize: settings.bodyFontSize, family: settings.readingFont,
                  text: settings.nsTextColor, secondary: settings.nsSecondaryTextColor,
                  inlineHighlight: settings.nsInlineHighlight)
    }

    func heading(_ level: Int) -> NSFont {
        family.nsFont(size: Typography.headingSize(level, body: bodySize), weight: .bold)
    }

    /// Base attributes for the whole document — the floor every syntax rule
    /// paints over.
    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: body, .foregroundColor: text, .paragraphStyle: paragraphStyle]
    }

    static func == (a: Theme, b: Theme) -> Bool {
        a.bodySize == b.bodySize && a.family == b.family
            && a.text == b.text && a.secondary == b.secondary
            && a.inlineHighlight == b.inlineHighlight
    }

    // MARK: Colors

    static let marker = NSColor.tertiaryLabelColor   // dimmed syntax when off the cursor line
    static let accent = NSColor.controlAccentColor
    static let unresolved = NSColor.systemRed      // wikilink to a non-existent note
    static let codeBg = NSColor(white: 0.5, alpha: 0.14)
    /// Writing mode's current-line wash — just enough to anchor the eye (Zed/
    /// editor convention), quiet enough to disappear while reading the draft.
    static let currentLineBg = NSColor.labelColor.withAlphaComponent(0.045)
    /// Frontmatter comments (`# …` inside YAML) — metadata, never a heading.
    static let yamlComment = NSColor.tertiaryLabelColor
}

extension NSTextView {
    /// Paint text selection in a theme color, or hand it back to the system when
    /// there isn't one. Idempotent: `updateNSView` calls this on every SwiftUI
    /// update, and re-assigning the attributes would redraw the selection each time.
    func applySelectionHighlight(_ color: NSColor?) {
        let background = color ?? .selectedTextBackgroundColor
        guard selectedTextAttributes[.backgroundColor] as? NSColor != background else { return }
        if let color {
            // Background only: the wash is light enough that text keeps its own
            // color, which is what lets a link stay a link while selected.
            selectedTextAttributes = [.backgroundColor: color]
        } else {
            // The system default is a *pair* — dropping `selectedTextColor` would
            // leave an accent-colored link drawn in blue on the blue selection.
            selectedTextAttributes = [.backgroundColor: NSColor.selectedTextBackgroundColor,
                                      .foregroundColor: NSColor.selectedTextColor]
        }
    }

    /// Paint the caret in a theme color, or hand it back to the system. Same
    /// idempotence rule as `applySelectionHighlight` — this runs on every update.
    func applyCaretColor(_ color: NSColor?) {
        let target = color ?? .textInsertionPointColor
        guard insertionPointColor != target else { return }
        insertionPointColor = target
    }
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
