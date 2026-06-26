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
    var background: NSColor = .textBackgroundColor
    var readableWidth: CGFloat = 720

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

        tv.noteNames = noteNames
        tv.onClickLink = onOpenLink
        tv.previewProvider = previewForLink
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
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LivePreviewEditor
        weak var textView: MarkdownTextView?
        init(_ parent: LivePreviewEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
            highlight()
            parent.onChange()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            highlight()   // re-evaluate which markers are revealed
        }

        func highlight() {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let ns = tv.string as NSString
            let loc = min(tv.selectedRange().location, ns.length)
            let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
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
