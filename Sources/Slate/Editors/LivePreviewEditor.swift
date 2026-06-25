import SwiftUI
import AppKit

/// The real editor: an `NSTextView` (TextKit) wrapped for SwiftUI. The text
/// storage holds the literal Markdown; `MarkdownHighlighter` styles it in place
/// so it *looks* WYSIWYG while staying byte-for-byte lossless on disk.
struct LivePreviewEditor: NSViewRepresentable {
    @Binding var text: String
    var onChange: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        guard let tv = scroll.documentView as? NSTextView else { return scroll }

        tv.delegate = context.coordinator
        tv.allowsUndo = true
        tv.isRichText = true            // we manage attributes; saved content is tv.string (plain)
        tv.isAutomaticQuoteSubstitutionEnabled = false   // never rewrite quotes in the file
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.font = Theme.body
        tv.textContainerInset = NSSize(width: 22, height: 18)
        tv.backgroundColor = .textBackgroundColor
        tv.typingAttributes = [.font: Theme.body, .foregroundColor: Theme.text]
        tv.string = text

        context.coordinator.textView = tv
        context.coordinator.highlight()
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = nsView.documentView as? NSTextView else { return }
        if tv.string != text {                  // external change (file switch / disk reload)
            let len = (text as NSString).length
            let prev = tv.selectedRange()
            tv.string = text
            tv.setSelectedRange(NSRange(location: min(prev.location, len), length: 0))
            context.coordinator.highlight()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LivePreviewEditor
        weak var textView: NSTextView?
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
            MarkdownHighlighter.apply(to: storage, cursorLine: lineRange)
        }
    }
}
