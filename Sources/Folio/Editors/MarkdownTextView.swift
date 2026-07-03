import AppKit
import SwiftUI

/// NSTextView subclass that adds editing affordances:
///   1. `[[` autocomplete of note names, with auto-closing `]]`.
///   2. Plain-click navigation for `.link` ranges (wikilinks / URLs).
///   3. Hover preview popovers for wikilinks.
final class MarkdownTextView: NSTextView {
    /// Supplies the current vault's note names for `[[` completion.
    var noteNames: () -> [String] = { [] }
    /// Invoked when a `.link` range is clicked; returns true if it was handled.
    var onClickLink: (URL) -> Bool = { _ in false }
    /// Returns preview text for a hovered link URL (nil = no preview).
    var previewProvider: (URL) -> String? = { _ in nil }
    /// Width of the centered reading column.
    var readableWidth: CGFloat = 720

    private static let taskClick = try! NSRegularExpression(pattern: "^(\\s*[-*+]\\s+)(\\[[ xX]\\])")

    private var hoverPopover: NSPopover?
    private var hoveredKey: String?

    /// Center the text in a readable column by padding the container insets.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        applyReadableInset()
    }

    func applyReadableInset() {
        let target = max(28, (bounds.width - readableWidth) / 2)
        if abs(textContainerInset.width - target) > 0.5 {
            textContainerInset = NSSize(width: target, height: textContainerInset.height)
        }
    }

    /// Invoked on ⌘F so the editor opens the *same* shared find bar as Reading mode
    /// (this SwiftUI app has no Edit▸Find menu that would route the shortcut, and we
    /// want one consistent finder across both modes rather than the native one).
    var onFind: () -> Void = {}

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "f" {
            onFind()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Restrict the completion "partial word" to the text typed after `[[`, so
    /// note names with spaces complete correctly.
    override var rangeForUserCompletion: NSRange {
        let sel = selectedRange()
        let ns = string as NSString
        guard sel.location <= ns.length else { return super.rangeForUserCompletion }
        let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        let before = ns.substring(with: NSRange(location: lineRange.location,
                                                length: sel.location - lineRange.location))
        if let open = before.range(of: "[[", options: .backwards),
           !before[open.upperBound...].contains("]]") {
            let queryLen = before.distance(from: open.upperBound, to: before.endIndex)
            let loc = sel.location - queryLen
            return NSRange(location: loc, length: queryLen)
        }
        return super.rangeForUserCompletion
    }

    /// Pop the completion list as soon as the user forms `[[`.
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        super.insertText(insertString, replacementRange: replacementRange)
        if let s = insertString as? String, s == "[" {
            let sel = selectedRange()
            let ns = string as NSString
            if sel.location >= 2,
               ns.substring(with: NSRange(location: sel.location - 2, length: 2)) == "[[" {
                complete(nil)
            }
        }
    }

    /// After choosing a completion, auto-insert the closing `]]`.
    override func insertCompletion(_ word: String, forPartialWordRange charRange: NSRange,
                                   movement: Int, isFinal: Bool) {
        super.insertCompletion(word, forPartialWordRange: charRange, movement: movement, isFinal: isFinal)
        guard isFinal else { return }
        let sel = selectedRange()
        let ns = string as NSString
        let hasClose = sel.location + 2 <= ns.length
            && ns.substring(with: NSRange(location: sel.location, length: 2)) == "]]"
        if !hasClose { insertText("]]", replacementRange: sel) }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let idx = characterIndexForInsertion(at: point)
        if toggleTask(atClick: idx) { return }
        if idx >= 0, let storage = textStorage, idx < storage.length,
           let value = storage.attribute(.link, at: idx, effectiveRange: nil) {
            let url = (value as? URL) ?? (value as? String).flatMap { URL(string: $0) }
            if let url, onClickLink(url) { return }
        }
        super.mouseDown(with: event)
    }

    // MARK: - Hover preview

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        guard let storage = textStorage else { dismissHover(); return }
        let idx = characterIndexForInsertion(at: point)
        guard idx >= 0, idx < storage.length,
              let value = storage.attribute(.link, at: idx, effectiveRange: nil),
              let url = (value as? URL) ?? (value as? String).flatMap({ URL(string: $0) }),
              url.scheme == "folio", url.host == "wikilink" else { dismissHover(); return }

        let key = url.absoluteString
        if key == hoveredKey { return }                 // already previewing this link
        guard let preview = previewProvider(url), !preview.isEmpty else { dismissHover(); return }
        showHover(preview, at: point)
        hoveredKey = key
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        dismissHover()
    }

    private func showHover(_ text: String, at point: NSPoint) {
        dismissHover()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: HoverPreview(text: text))
        popover.show(relativeTo: NSRect(origin: point, size: CGSize(width: 1, height: 1)),
                     of: self, preferredEdge: .maxY)
        hoverPopover = popover
    }

    private func dismissHover() {
        hoverPopover?.performClose(nil)
        hoverPopover = nil
        hoveredKey = nil
    }

    /// Toggle a `- [ ]` / `- [x]` checkbox when its box is clicked.
    private func toggleTask(atClick idx: Int) -> Bool {
        guard idx >= 0 else { return false }
        let ns = string as NSString
        guard idx <= ns.length else { return false }
        let lineRange = ns.lineRange(for: NSRange(location: min(idx, ns.length), length: 0))
        let line = ns.substring(with: lineRange)
        guard let m = Self.taskClick.firstMatch(
            in: line, range: NSRange(location: 0, length: (line as NSString).length)) else { return false }
        let g1 = m.range(at: 1), g2 = m.range(at: 2)
        let boxStart = lineRange.location + g1.location
        let boxEnd = lineRange.location + g2.location + g2.length
        guard idx >= boxStart, idx <= boxEnd else { return false }
        let inner = NSRange(location: lineRange.location + g2.location + 1, length: 1)
        let newChar = ns.substring(with: inner).lowercased() == "x" ? " " : "x"
        if shouldChangeText(in: inner, replacementString: newChar) {
            insertText(newChar, replacementRange: inner)
        }
        return true
    }
}

/// Content of the wikilink hover popover: a scrollable peek at the target note.
private struct HoverPreview: View {
    let text: String
    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .frame(width: 340, height: 240)
    }
}
