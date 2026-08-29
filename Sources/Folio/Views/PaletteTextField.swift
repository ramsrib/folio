import SwiftUI
import AppKit

/// Single-line query field for the palettes — deliberately NOT a SwiftUI
/// TextField. NSTextField (which backs TextField) edits through the window's
/// shared *field editor*, and that editor's first session per launch flashes its
/// untamed chrome — a white box and the inline-prediction candidate panel, which
/// floats in its own AppKit window where no SwiftUI styling or opacity can reach
/// it (the "phantom dropdown"). A plain NSTextView owns its editing directly:
/// no field editor, no prediction UI, configured dead before it ever draws.
///
/// Arrow/return keys are surfaced as callbacks because AppKit consumes them
/// ahead of SwiftUI's `.onKeyPress`; Esc is left alone — the global palette
/// monitor (GestureMonitor) owns it.
struct PaletteTextField: NSViewRepresentable {
    /// Read from the environment rather than passed in: every host of this field
    /// already has it, and the alternative is threading a color through six
    /// call sites that care about nothing else.
    @EnvironmentObject private var settings: AppSettings
    @Binding var text: String
    var placeholder: String
    var fontSize: CGFloat = 17
    var onSubmit: (NSEvent.ModifierFlags) -> Void = { _ in }
    var onMoveUp: () -> Void = {}
    var onMoveDown: () -> Void = {}
    /// Bump to ask the field to (re)take first responder — e.g. the find bar's
    /// focusRequest when ⌘F is pressed while the bar is already open.
    var focusToken: Int = 0
    /// Esc handler for hosts the global palette monitor does NOT cover (the find
    /// bar in writing mode — the monitor passes Esc through there, and without
    /// this the field swallowed it as a no-op). Palettes leave it nil: the
    /// monitor dismisses them before the field ever sees the key.
    var onEscape: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // Borderless, scroller-less scroll view: gives the text view horizontal
        // overflow (long queries) without wrapping to a second line.
        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.verticalScrollElasticity = .none

        let tv = QueryTextView()
        tv.delegate = context.coordinator
        tv.font = .systemFont(ofSize: fontSize)
        tv.drawsBackground = false
        tv.isRichText = false
        tv.usesFontPanel = false
        tv.usesFindBar = false
        tv.importsGraphics = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticTextCompletionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        if #available(macOS 14.0, *) { tv.inlinePredictionType = .no }
        tv.textContainerInset = .zero
        // Single-line: the container is effectively infinite in width and the
        // text view grows horizontally instead of wrapping.
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = true
        tv.maxSize = NSSize(width: .greatestFiniteMagnitude, height: fontSize * 1.4)
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = NSSize(width: .greatestFiniteMagnitude,
                                                 height: fontSize * 1.4)
        tv.applyCaretColor(settings.nsCaretColor)
        tv.placeholder = placeholder
        tv.string = text

        scroll.documentView = tv
        context.coordinator.textView = tv
        // Take focus once the view is in a window. No taming needed — there is
        // no field editor in this path, which is the whole point.
        DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = nsView.documentView as? QueryTextView else { return }
        tv.applyCaretColor(settings.nsCaretColor)
        if tv.string != text { tv.string = text }
        if tv.placeholder != placeholder { tv.placeholder = placeholder; tv.needsDisplay = true }
        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PaletteTextField
        weak var textView: QueryTextView?
        var lastFocusToken = 0
        init(_ parent: PaletteTextField) { self.parent = parent; lastFocusToken = parent.focusToken }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            // Single-line field: pasted newlines flatten to spaces.
            let flat = tv.string.replacingOccurrences(of: "\n", with: " ")
            if flat != tv.string { tv.string = flat }
            parent.text = flat
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertLineBreak(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                parent.onSubmit(NSApp.currentEvent?.modifierFlags
                    .intersection([.command, .shift, .option]) ?? [])
                return true
            case #selector(NSResponder.moveUp(_:)):   parent.onMoveUp(); return true
            case #selector(NSResponder.moveDown(_:)): parent.onMoveDown(); return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape?()
                return true   // never the completions popup, regardless
            default:
                return false
            }
        }
    }

    /// NSTextView with a drawn placeholder (NSTextView has no built-in one).
    final class QueryTextView: NSTextView {
        var placeholder: String = ""

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            guard string.isEmpty, !placeholder.isEmpty else { return }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font ?? .systemFont(ofSize: 17),
                .foregroundColor: NSColor.placeholderTextColor,
            ]
            NSAttributedString(string: placeholder, attributes: attrs)
                .draw(at: NSPoint(x: textContainerInset.width + 2, y: textContainerInset.height))
        }

        override var string: String {
            didSet { needsDisplay = true }
        }
    }
}
