import CoreGraphics

/// The type scale, in one place, expressed as multiples of the user's body size
/// (`AppSettings.bodyFontSize`).
///
/// Everything typographic derives from here so that (a) ⌘+/⌘− scales the whole
/// note rather than just its prose, and (b) reading and writing mode lay text out
/// *identically* — the read↔edit switch is the app's core gesture, so text must
/// not reflow across it.
enum Typography {
    // MARK: Line height

    /// Gap added between lines, as a fraction of body size. Yields a line height
    /// of ~1.6× at the default 17pt — the long-form sweet spot.
    ///
    /// Reading mode feeds this to SwiftUI's `lineSpacing`; writing mode feeds it
    /// to `NSParagraphStyle.lineSpacing`. Both mean "points between the bottom of
    /// one line fragment and the top of the next", so one number covers both.
    static let lineSpacing: CGFloat = 0.42

    /// Headings need far less than body text — they're display sizes, and their
    /// own point size already opens up the leading.
    static let headingLineSpacing: CGFloat = 0.12

    // MARK: Block rhythm

    /// Vertical gap between blocks. Comfortably more than the interline gap so a
    /// paragraph break reads as one, without punching a hole in the column.
    static let blockSpacing: CGFloat = 0.95

    /// Indent per nesting level for lists and tasks.
    static let listIndent: CGFloat = 1.3

    /// Extra air above a heading that follows other content: major headings open
    /// a section, minor ones just label the next few lines.
    static func headingTopPadding(level: Int) -> CGFloat { level <= 2 ? 1.53 : 0.7 }

    // MARK: Sizes relative to body

    /// Inline `code` spans. Monospace runs optically larger than the prose around
    /// it at the same point size, so it sits a touch below body.
    static let inlineCode: CGFloat = 0.88
    /// Fenced code blocks — a hair smaller again, since they're scanned not read.
    static let codeBlock: CGFloat = 0.85
    static let table: CGFloat = 0.88
    static let callout: CGFloat = 0.9

    /// Heading ramp, h1…h6.
    static let headingScale: [CGFloat] = [1.75, 1.4, 1.18, 1.06, 0.98, 0.9]

    static func headingSize(_ level: Int, body: CGFloat) -> CGFloat {
        body * headingScale[min(max(level - 1, 0), headingScale.count - 1)]
    }

    // MARK: Tracking

    /// Display-size text needs its tracking pulled in: the system font's spacing
    /// is metric-optimized for label sizes and reads loose once it's this big.
    /// Body sizes are left alone.
    static func tracking(forSize size: CGFloat) -> CGFloat {
        size >= 20 ? -size * 0.015 : 0
    }
}
