#if os(macOS)
import AppKit
import SwiftUI

extension NSAttributedString.Key {
    /// Block decoration to draw *behind* a range (code card, callout, quote bar,
    /// divider rule). TextKit has no block-background concept under TextKit 2, so
    /// `NoteTextView` draws these from the laid-out fragment geometry.
    static let folioDecoration = NSAttributedString.Key("folioDecoration")
    /// Content index of a task's `[ ]` marker — click to toggle.
    static let folioCheckbox = NSAttributedString.Key("folioCheckbox")
    /// Heading anchor, so the outline can scroll to a heading.
    static let folioAnchor = NSAttributedString.Key("folioAnchor")
    /// Text equivalent for a range that renders as an attachment, so copying a
    /// selection that spans one yields something meaningful instead of U+FFFC.
    static let folioSource = NSAttributedString.Key("folioSource")
    /// Marks the newline *between* blocks (as opposed to a soft break inside a
    /// paragraph), so copied text gets a blank line where the layout shows a gap.
    static let folioBlockBreak = NSAttributedString.Key("folioBlockBreak")
}

/// What to paint behind a run of text.
enum BlockDecoration: Equatable {
    case code
    case callout(kind: String)
    case quote
    case divider
}

/// Builds the whole note as a single `NSAttributedString`.
///
/// This is the point of reading mode's architecture: one text stream means one
/// selection. Prose, headings, lists, tasks, quotes, callouts and code are real
/// text; only genuinely non-textual blocks (tables, the properties card, images)
/// become attachments, and selection still flows *through* those because an
/// attachment is one character in the same stream.
@MainActor
struct NoteTextRenderer {
    let bodySize: CGFloat
    let family: ReadingFont
    /// Column width, for sizing image and table attachments.
    let contentWidth: CGFloat
    /// Resolves a relative image path against the note/vault.
    var loadImage: (String) -> NSImage? = { _ in nil }

    private var lineSpacing: CGFloat { bodySize * Typography.lineSpacing }
    private var blockSpacing: CGFloat { bodySize * Typography.blockSpacing }
    private var listIndent: CGFloat { bodySize * Typography.listIndent }
    private var body: NSFont { family.nsFont(size: bodySize) }

    // MARK: Entry point

    func render(_ blocks: [Block]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for (i, block) in blocks.enumerated() {
            let piece = render(block, isFirst: i == 0)
            out.append(piece)
            // Every block is its own paragraph; spacing comes from the paragraph
            // style, so the separator is a bare newline.
            if i < blocks.count - 1 {
                out.append(NSAttributedString(string: "\n", attributes: [.folioBlockBreak: true]))
            }
        }
        return out
    }

    private func render(_ block: Block, isFirst: Bool) -> NSAttributedString {
        switch block.kind {
        case let .properties(props):        return propertiesBlock(props)
        case let .heading(level, text, anchor): return heading(level, text, anchor, isFirst: isFirst)
        case let .paragraph(text):          return paragraph(text)
        case let .listItem(ordered, number, indent, text):
            return listItem(ordered: ordered, number: number, indent: indent, text: text)
        case let .task(checked, indent, text, checkboxIndex):
            return task(checked: checked, indent: indent, text: text, checkboxIndex: checkboxIndex)
        case let .quote(text):              return quote(text)
        case let .callout(kind, title, body): return callout(kind: kind, title: title, body: body)
        case let .code(language, text):     return code(language: language, text: text)
        case .divider:                      return divider()
        case let .image(alt, source):       return image(alt: alt, source: source)
        case let .table(headers, rows):     return table(headers: headers, rows: rows)
        }
    }

    // MARK: Paragraph styles

    private func style(_ configure: (NSMutableParagraphStyle) -> Void = { _ in }) -> NSParagraphStyle {
        let s = NSMutableParagraphStyle()
        s.lineSpacing = lineSpacing
        s.paragraphSpacing = blockSpacing
        configure(s)
        return s
    }

    /// Indented body style with a hanging indent, for lists and tasks: wrapped
    /// lines line up under the text, not under the bullet.
    private func hangingStyle(depth: Int, marker: CGFloat) -> NSParagraphStyle {
        style { s in
            let base = CGFloat(depth) * listIndent
            s.firstLineHeadIndent = base
            s.headIndent = base + marker
            s.tabStops = [NSTextTab(textAlignment: .left, location: base + marker)]
            s.defaultTabInterval = marker
        }
    }

    // MARK: Blocks

    private func heading(_ level: Int, _ text: String, _ anchor: Int, isFirst: Bool) -> NSAttributedString {
        let size = Typography.headingSize(level, body: bodySize)
        let font = family.nsFont(size: size, weight: level <= 2 ? .bold : .semibold)
        let attr = inline(text, font: font)
        attr.addAttributes([
            .kern: Typography.tracking(forSize: size),
            .folioAnchor: anchor,
            .paragraphStyle: style { s in
                s.lineSpacing = size * Typography.headingLineSpacing
                s.paragraphSpacingBefore = isFirst
                    ? 0 : bodySize * Typography.headingTopPadding(level: level)
            },
        ], range: attr.fullRange)
        return attr
    }

    private func paragraph(_ text: String) -> NSAttributedString {
        let attr = inline(text, font: body)
        attr.addAttribute(.paragraphStyle, value: style(), range: attr.fullRange)
        return attr
    }

    private func listItem(ordered: Bool, number: Int, indent: Int, text: String) -> NSAttributedString {
        let marker = ordered ? "\(number)." : "•"
        let out = NSMutableAttributedString(string: marker + "\t", attributes: [
            .font: body, .foregroundColor: NSColor.secondaryLabelColor,
        ])
        out.append(inline(text, font: body))
        out.addAttribute(.paragraphStyle, value: hangingStyle(depth: indent, marker: listIndent),
                         range: out.fullRange)
        return out
    }

    private func task(checked: Bool, indent: Int, text: String, checkboxIndex: Int) -> NSAttributedString {
        let symbol = checked ? "checkmark.square.fill" : "square"
        let tint: NSColor = checked ? .controlAccentColor : .secondaryLabelColor
        let out = NSMutableAttributedString()
        if let box = symbolAttachment(symbol, size: bodySize * 0.94, tint: tint) {
            out.append(box)
        } else {
            out.append(NSAttributedString(string: checked ? "☑" : "☐", attributes: [.font: body]))
        }
        // The checkbox character carries the click target, and copies as what
        // it looks like rather than as an object-replacement character.
        out.addAttributes([.folioCheckbox: checkboxIndex,
                           .folioSource: checked ? "☑" : "☐"],
                          range: NSRange(location: 0, length: out.length))
        out.append(NSAttributedString(string: "\t", attributes: [.font: body]))

        let label = inline(text, font: body)
        if checked {
            label.addAttributes([
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .foregroundColor: NSColor.secondaryLabelColor,
            ], range: label.fullRange)
        }
        out.append(label)
        out.addAttribute(.paragraphStyle, value: hangingStyle(depth: indent, marker: listIndent),
                         range: out.fullRange)
        return out
    }

    private func quote(_ text: String) -> NSAttributedString {
        let attr = inline(text, font: body)
        attr.addAttributes([
            .foregroundColor: NSColor.secondaryLabelColor,
            .folioDecoration: BlockDecoration.quote.boxed,
            .paragraphStyle: style { s in
                s.firstLineHeadIndent = listIndent
                s.headIndent = listIndent
            },
        ], range: attr.fullRange)
        return attr
    }

    private func callout(kind: String, title: String, body bodyText: String) -> NSAttributedString {
        let size = bodySize * Typography.callout
        let out = NSMutableAttributedString()
        if let icon = symbolAttachment(NoteTextRenderer.calloutSymbol(kind), size: size,
                                       tint: NoteTextRenderer.calloutTint(kind)) {
            let marked = NSMutableAttributedString(attributedString: icon)
            marked.addAttribute(.folioSource, value: "", range: marked.fullRange)   // pure decoration
            out.append(marked)
            out.append(NSAttributedString(string: " ", attributes: [.font: body]))
        }
        out.append(inline(title, font: family.nsFont(size: size, weight: .semibold)))
        if !bodyText.isEmpty {
            out.append(NSAttributedString(string: "\n", attributes: [.font: body]))
            out.append(inline(bodyText, font: family.nsFont(size: size)))
        }
        let inset = bodySize * 0.7
        out.addAttributes([
            .folioDecoration: BlockDecoration.callout(kind: kind).boxed,
            .paragraphStyle: style { s in
                s.firstLineHeadIndent = inset
                s.headIndent = inset
                s.paragraphSpacingBefore = inset * 0.6
                s.paragraphSpacing = blockSpacing + inset * 0.6
            },
        ], range: out.fullRange)
        return out
    }

    private func code(language: String, text: String) -> NSAttributedString {
        let size = bodySize * Typography.codeBlock
        let out = NSMutableAttributedString(
            attributedString: CodeHighlighter.highlightNS(text, language: language, size: size))
        let inset = bodySize * 0.7
        out.addAttributes([
            .folioDecoration: BlockDecoration.code.boxed,
            .paragraphStyle: style { s in
                // Code wraps rather than scrolling: a horizontally scrolling island
                // inside one text stream would be a selection dead-zone, and code
                // is the thing people copy most.
                s.lineSpacing = size * 0.3
                s.firstLineHeadIndent = inset
                s.headIndent = inset * 1.6
                s.tailIndent = -inset
                s.paragraphSpacingBefore = inset * 0.7
                s.paragraphSpacing = blockSpacing + inset * 0.7
            },
        ], range: out.fullRange)
        return out
    }

    /// A blank line carrying the rule; `NoteTextView` strikes it through the middle.
    private func divider() -> NSAttributedString {
        NSAttributedString(string: " ", attributes: [
            .font: body,
            .folioSource: "———",
            .folioDecoration: BlockDecoration.divider.boxed,
            .paragraphStyle: style { s in
                s.paragraphSpacingBefore = blockSpacing * 0.5
                s.paragraphSpacing = blockSpacing * 1.5
            },
        ])
    }

    private func image(alt: String, source: String) -> NSAttributedString {
        guard let image = loadImage(source) else {
            let placeholder = NSMutableAttributedString(
                string: alt.isEmpty ? source : alt,
                attributes: [.font: body, .foregroundColor: NSColor.secondaryLabelColor,
                             .paragraphStyle: style()])
            return placeholder
        }
        let attachment = NSTextAttachment()
        attachment.image = image
        // Fit the column, never upscale.
        let scale = min(1, contentWidth / max(image.size.width, 1))
        attachment.bounds = NSRect(origin: .zero,
                                   size: NSSize(width: image.size.width * scale,
                                                height: image.size.height * scale))
        let out = NSMutableAttributedString(attachment: attachment)
        out.addAttributes([
            .folioSource: "![\(alt)](\(source))",
            .paragraphStyle: style(),
        ], range: out.fullRange)
        return out
    }

    // MARK: Hosted blocks

    private func table(headers: [String], rows: [[String]]) -> NSAttributedString {
        hosted(TableBlockView(headers: headers, rows: rows, bodySize: bodySize),
               source: MarkdownSource.table(headers: headers, rows: rows))
    }

    private func propertiesBlock(_ props: [Prop]) -> NSAttributedString {
        hosted(PropertiesBlockView(props: props),
               source: MarkdownSource.properties(props))
    }

    /// Embed a SwiftUI view as a block-level attachment. It sits in the text
    /// stream as one character, so a selection can run straight through it.
    private func hosted<V: View>(_ view: V, source: String) -> NSAttributedString {
        let attachment = HostedBlockAttachment(rootView: AnyView(view), width: contentWidth)
        let out = NSMutableAttributedString(attachment: attachment)
        out.addAttributes([
            .folioSource: source,
            .paragraphStyle: style(),
        ], range: out.fullRange)
        return out
    }

    // MARK: Inline

    /// One line of inline Markdown → `NSAttributedString`, with bold/italic/code/
    /// strikethrough and links resolved. Mirrors `InlineMarkdown` (which produces
    /// the SwiftUI flavor for iOS) but maps runs onto AppKit attributes directly.
    private func inline(_ raw: String, font: NSFont) -> NSMutableAttributedString {
        let source = InlineMarkdown.transform(raw)
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible)
        guard let parsed = try? AttributedString(markdown: source, options: options) else {
            return NSMutableAttributedString(string: raw, attributes: [.font: font,
                                                                       .foregroundColor: NSColor.labelColor])
        }

        let out = NSMutableAttributedString()
        for run in parsed.runs {
            let text = String(parsed[run.range].characters)
            let intent = run.inlinePresentationIntent ?? []
            var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.labelColor]

            if intent.contains(.code) {
                attrs[.font] = NSFont.monospacedSystemFont(ofSize: font.pointSize * Typography.inlineCode,
                                                           weight: .regular)
                attrs[.backgroundColor] = NSColor.labelColor.withAlphaComponent(0.06)
            } else {
                var traits: NSFontTraitMask = []
                if intent.contains(.stronglyEmphasized) { traits.insert(.boldFontMask) }
                if intent.contains(.emphasized) { traits.insert(.italicFontMask) }
                attrs[.font] = traits.isEmpty
                    ? font : NSFontManager.shared.convert(font, toHaveTrait: traits)
            }
            if intent.contains(.strikethrough) {
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if let link = run.link {
                attrs[.link] = link
                attrs[.foregroundColor] = NSColor.controlAccentColor
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            out.append(NSAttributedString(string: text, attributes: attrs))
        }
        return out
    }

    /// An SF Symbol as an inline attachment, baseline-aligned with the text.
    private func symbolAttachment(_ name: String, size: CGFloat, tint: NSColor) -> NSAttributedString? {
        guard let raw = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
            .applying(.init(paletteColors: [tint]))
        guard let image = raw.withSymbolConfiguration(config) else { return nil }
        let attachment = NSTextAttachment()
        attachment.image = image
        // Sit the glyph on the text baseline rather than the line bottom.
        attachment.bounds = NSRect(x: 0, y: -size * 0.15,
                                   width: image.size.width, height: image.size.height)
        return NSAttributedString(attachment: attachment)
    }

    // MARK: Callout vocabulary (mirrors the SwiftUI reader)

    static func calloutSymbol(_ kind: String) -> String {
        switch kind {
        case "warning", "caution", "attention": return "exclamationmark.triangle.fill"
        case "danger", "error", "bug":          return "xmark.octagon.fill"
        case "success", "check", "done":        return "checkmark.circle.fill"
        case "question", "faq", "help":         return "questionmark.circle.fill"
        case "tip", "hint", "important":        return "flame.fill"
        case "quote", "cite":                   return "quote.opening"
        default:                                return "info.circle.fill"
        }
    }

    static func calloutTint(_ kind: String) -> NSColor {
        switch kind {
        case "warning", "caution", "attention": return .systemOrange
        case "danger", "error", "bug":          return .systemRed
        case "success", "check", "done":        return .systemGreen
        case "question", "faq", "help":         return .systemPurple
        case "tip", "hint", "important":        return .systemPink
        case "quote", "cite":                   return .systemGray
        default:                                return .systemBlue
        }
    }
}

// MARK: - Plumbing

extension NSAttributedString {
    var fullRange: NSRange { NSRange(location: 0, length: length) }
}

/// `NSAttributedString` attribute values must be objects; box the enum.
extension BlockDecoration {
    var boxed: NSObject { DecorationBox(self) }
}

final class DecorationBox: NSObject {
    let value: BlockDecoration
    init(_ value: BlockDecoration) { self.value = value }
    override func isEqual(_ object: Any?) -> Bool {
        (object as? DecorationBox)?.value == value
    }
    override var hash: Int { String(describing: value).hashValue }
}

/// Markdown source for blocks that render as attachments, so copying a selection
/// that spans one yields text rather than a hole.
enum MarkdownSource {
    static func table(headers: [String], rows: [[String]]) -> String {
        var lines = ["| " + headers.joined(separator: " | ") + " |"]
        lines.append("| " + headers.map { _ in "---" }.joined(separator: " | ") + " |")
        for row in rows { lines.append("| " + row.joined(separator: " | ") + " |") }
        return lines.joined(separator: "\n")
    }

    static func properties(_ props: [Prop]) -> String {
        props.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
    }
}
#endif
