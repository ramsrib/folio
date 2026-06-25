import AppKit

/// NSTextView subclass that adds two behaviors on top of plain editing:
///   1. `[[` autocomplete of note names (using AppKit's native completion list,
///      so positioning + keyboard nav come for free), with auto-closing `]]`.
///   2. Plain-click navigation for `.link` ranges (wikilinks / URLs), so a click
///      follows the link instead of just placing the caret.
final class MarkdownTextView: NSTextView {
    /// Supplies the current vault's note names for `[[` completion.
    var noteNames: () -> [String] = { [] }
    /// Invoked when a `.link` range is clicked; returns true if it was handled.
    var onClickLink: (URL) -> Bool = { _ in false }
    /// Width of the centered reading column.
    var readableWidth: CGFloat = 720

    private static let taskClick = try! NSRegularExpression(pattern: "^(\\s*[-*+]\\s+)(\\[[ xX]\\])")

    /// Center the text in a readable column by padding the container insets.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let target = max(28, (newSize.width - readableWidth) / 2)
        if abs(textContainerInset.width - target) > 0.5 {
            textContainerInset = NSSize(width: target, height: textContainerInset.height)
        }
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
