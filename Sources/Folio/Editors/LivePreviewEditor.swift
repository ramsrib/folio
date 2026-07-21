import SwiftUI
import AppKit

/// The real editor: a `MarkdownTextView` (TextKit) wrapped for SwiftUI. The text
/// storage holds the literal Markdown; `MarkdownHighlighter` styles it in place
/// so it *looks* WYSIWYG while staying byte-for-byte lossless on disk.
struct LivePreviewEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var scrollTo: Int?
    var onChange: () -> Void
    var resolveWikilink: (String) -> Bool
    var noteNames: () -> [String]
    var onOpenLink: (URL) -> Bool
    var previewForLink: (URL) -> String? = { _ in nil }
    var onEscape: () -> Void = {}
    var background: NSColor = .textBackgroundColor
    var readableWidth: CGFloat = 720
    @ObservedObject var find: FindModel

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true

        let tv = MarkdownTextView(frame: .zero)
        tv.delegate = context.coordinator
        tv.allowsUndo = true
        tv.isRichText = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.font = Theme.body
        tv.textContainerInset = NSSize(width: 22, height: 18)
        tv.backgroundColor = background
        tv.readableWidth = readableWidth
        tv.typingAttributes = [.font: Theme.body, .foregroundColor: Theme.text]
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        // Lay out lazily: without this, NSTextView lays out the ENTIRE document
        // before first display — seconds of "switching to edit mode" on large
        // notes. TextKit's own LazyVStack trade: estimated heights while
        // scrolling far, exact everywhere you've been.
        tv.layoutManager?.allowsNonContiguousLayout = true

        tv.noteNames = noteNames
        tv.onClickLink = onOpenLink
        tv.previewProvider = previewForLink
        tv.onFind = { [find] in find.open() }
        tv.onEscape = onEscape
        tv.string = text

        scroll.documentView = tv
        context.coordinator.textView = tv
        context.coordinator.highlight()
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = nsView.documentView as? MarkdownTextView else { return }
        tv.noteNames = noteNames
        tv.onClickLink = onOpenLink
        tv.previewProvider = previewForLink
        if tv.backgroundColor != background { tv.backgroundColor = background }
        if tv.readableWidth != readableWidth { tv.readableWidth = readableWidth; tv.applyReadableInset() }

        if tv.string != text {                  // external change (file switch / disk reload)
            let len = (text as NSString).length
            let prev = tv.selectedRange()
            tv.string = text
            tv.setSelectedRange(NSRange(location: min(prev.location, len), length: 0))
            context.coordinator.highlight()
        }

        if let idx = scrollTo {                  // outline click → scroll to heading
            let len = (tv.string as NSString).length
            let loc = min(max(idx, 0), len)
            tv.setSelectedRange(NSRange(location: loc, length: 0))
            tv.scrollRangeToVisible(NSRange(location: loc, length: 0))
            context.coordinator.highlight()
            DispatchQueue.main.async { scrollTo = nil }
        }

        tv.onFind = { [find] in find.open() }
        tv.onEscape = onEscape
        context.coordinator.applyFind(find, to: tv)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LivePreviewEditor
        weak var textView: MarkdownTextView?
        init(_ parent: LivePreviewEditor) { self.parent = parent }

        // MARK: Find (driven by the shared FindModel)
        private var findRanges: [NSRange] = []
        private var lastHighlightKey: String?   // query + case + text length → recompute + highlight
        private var lastRevealKey: String?      // query + case + current → move selection

        /// Sync the editor with the shared find state: (re)highlight all matches when
        /// the query/case/text changes, and reveal the current match only when the
        /// user actually navigates — never yanking the caret while they're editing.
        func applyFind(_ find: FindModel, to tv: MarkdownTextView) {
            guard find.active, !find.query.isEmpty else {
                if !findRanges.isEmpty { clearFindHighlight(tv); findRanges = [] }
                lastHighlightKey = nil; lastRevealKey = nil
                if find.total != 0 { DispatchQueue.main.async { find.total = 0 } }
                return
            }
            let text = tv.string as NSString
            let highlightKey = "\(find.caseSensitive)|\(text.length)|\(find.query)"
            if highlightKey != lastHighlightKey {
                lastHighlightKey = highlightKey
                findRanges = ranges(of: find.query, in: text, options: find.options)
                highlightAll(tv, ranges: findRanges)
                let count = findRanges.count
                DispatchQueue.main.async {
                    if find.total != count { find.total = count }
                    if find.current >= count { find.current = max(0, count - 1) }
                }
            }
            let revealKey = "\(find.caseSensitive)|\(find.query)|\(find.current)"
            if revealKey != lastRevealKey, findRanges.indices.contains(find.current) {
                lastRevealKey = revealKey
                let r = findRanges[find.current]
                tv.setSelectedRange(r)
                tv.scrollRangeToVisible(r)
                tv.showFindIndicator(for: r)
            }
        }

        private func ranges(of query: String, in text: NSString, options: NSString.CompareOptions) -> [NSRange] {
            guard !query.isEmpty, text.length > 0 else { return [] }
            var result: [NSRange] = []
            var searchRange = NSRange(location: 0, length: text.length)
            while searchRange.length > 0 {
                let r = text.range(of: query, options: options, range: searchRange)
                if r.location == NSNotFound { break }
                result.append(r)
                let nextLoc = r.location + max(r.length, 1)
                if nextLoc >= text.length { break }
                searchRange = NSRange(location: nextLoc, length: text.length - nextLoc)
            }
            return result
        }

        /// Non-destructive highlight via layout-manager temporary attributes, so it
        /// never touches the text storage (keeps the buffer lossless) and coexists
        /// with the Markdown syntax highlighting.
        private func highlightAll(_ tv: NSTextView, ranges: [NSRange]) {
            guard let lm = tv.layoutManager else { return }
            clearFindHighlight(tv)
            for r in ranges {
                lm.addTemporaryAttributes([.backgroundColor: NSColor.systemYellow.withAlphaComponent(0.4)],
                                          forCharacterRange: r)
            }
        }

        private func clearFindHighlight(_ tv: NSTextView) {
            guard let lm = tv.layoutManager else { return }
            lm.removeTemporaryAttribute(.backgroundColor,
                                        forCharacterRange: NSRange(location: 0, length: (tv.string as NSString).length))
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
            highlight()
            parent.onChange()
        }

        /// The cursor line of the last full highlight pass. Marker reveal is the
        /// only thing that depends on the caret, so a caret move *within* the
        /// same line changes nothing — skip the whole-document restyle (which is
        /// what made arrowing around large notes feel sticky).
        private var lastCursorLine = NSRange(location: NSNotFound, length: 0)

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = textView else { return }
            let ns = tv.string as NSString
            let loc = min(tv.selectedRange().location, ns.length)
            let line = ns.lineRange(for: NSRange(location: loc, length: 0))
            if line != lastCursorLine { highlight() }   // reveal moved to another line
            tv.needsDisplay = true   // move the current-line wash with the caret
        }

        func highlight() {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let ns = tv.string as NSString
            let loc = min(tv.selectedRange().location, ns.length)
            let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
            lastCursorLine = lineRange
            MarkdownHighlighter.apply(to: storage, cursorLine: lineRange,
                                      resolveWikilink: parent.resolveWikilink)
        }

        /// Provide note-name completions inside a `[[ … ]]` context.
        func textView(_ textView: NSTextView, completions words: [String],
                      forPartialWordRange charRange: NSRange,
                      indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String] {
            let ns = textView.string as NSString
            guard charRange.location != NSNotFound, NSMaxRange(charRange) <= ns.length else { return words }
            let lineRange = ns.lineRange(for: NSRange(location: charRange.location, length: 0))
            let pre = ns.substring(with: NSRange(location: lineRange.location,
                                                 length: charRange.location - lineRange.location))
            guard let open = pre.range(of: "[[", options: .backwards),
                  !pre[open.upperBound...].contains("]]") else { return words }

            let query = ns.substring(with: charRange).lowercased()
            let names = parent.noteNames()
            let filtered = names.filter { query.isEmpty || $0.lowercased().contains(query) }
            return Array(filtered.sorted { a, b in
                let ap = a.lowercased().hasPrefix(query), bp = b.lowercased().hasPrefix(query)
                if ap != bp { return ap }
                return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            }.prefix(50))
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let url = (link as? URL) ?? (link as? String).flatMap { URL(string: $0) }
            guard let url else { return false }
            return parent.onOpenLink(url)
        }
    }
}
