#if os(macOS)
import SwiftUI
import AppKit

/// Reading mode's text surface: the whole note in **one** TextKit 2 text view.
///
/// The block-per-view reader it replaced could only ever select inside a single
/// block, because AppKit/SwiftUI has no cross-view text selection. One text
/// stream gets selection, ⌘A, copy, Look Up, drag-out, print and accessibility
/// for free, and — since writing mode is also a text view — the two modes now
/// share a layout engine instead of agreeing by convention.
struct NoteTextView: NSViewRepresentable {
    let blocks: [Block]
    /// Identity of everything the rendered string depends on. Changing it
    /// re-renders; unchanged means the (expensive) rebuild is skipped.
    let renderKey: String
    let bodySize: CGFloat
    let family: ReadingFont
    let readableWidth: CGFloat
    let background: NSColor
    /// Theme tint for selected text; nil uses the system selection color.
    let selectionHighlight: NSColor?
    let noteID: URL?
    @ObservedObject var find: FindModel
    /// Heading anchor to scroll to (outline click / wikilink with `#heading`).
    let scrollRequest: Int?
    var loadImage: (String) -> NSImage? = { _ in nil }
    var onToggleTask: (Int) -> Void = { _ in }
    var onOpenLink: (URL) -> Bool = { _ in false }
    var onConsumedScrollRequest: () -> Void = {}

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true

        let tv = NoteContentTextView(usingTextLayoutManager: true)
        tv.delegate = context.coordinator
        tv.isEditable = false
        tv.isSelectable = true
        tv.isRichText = true
        tv.isAutomaticLinkDetectionEnabled = false
        tv.drawsBackground = true
        tv.backgroundColor = background
        tv.applySelectionHighlight(selectionHighlight)
        tv.readableWidth = readableWidth
        tv.textContainerInset = NSSize(width: 32, height: 28)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        // The column width is ours to set (see `applyReadableInset`), not something
        // to derive from the frame — `widthTracksTextView` would re-wrap the text
        // mid-resize using the stale inset.
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.heightTracksTextView = false
        tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        tv.onToggleTask = onToggleTask

        scroll.documentView = tv
        context.coordinator.textView = tv
        context.coordinator.scrollView = scroll

        // Reuse Reading mode's existing AppKit helpers rather than reimplementing
        // vim scrolling and per-note scroll memory against a new scroll view.
        context.coordinator.keys.scrollView = scroll
        context.coordinator.keys.installMonitor()
        context.coordinator.memory.attach(to: scroll)

        context.coordinator.render(self)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NoteContentTextView else { return }
        let coordinator = context.coordinator
        coordinator.parent = self
        tv.onToggleTask = onToggleTask
        if tv.backgroundColor != background { tv.backgroundColor = background }
        tv.applySelectionHighlight(selectionHighlight)
        if tv.readableWidth != readableWidth {
            tv.readableWidth = readableWidth
            tv.applyReadableInset()
        }

        coordinator.render(self)

        // A find/outline jump owns the scroll position for this switch; otherwise
        // the note's remembered offset does.
        coordinator.memory.positionOwnedElsewhere = {
            (find.active && !find.query.isEmpty) || scrollRequest != nil
        }
        if coordinator.memory.currentKey != noteID {
            coordinator.memory.noteChanged(to: noteID)
        }

        coordinator.applyFind(find)

        if let anchor = scrollRequest {
            coordinator.scrollToAnchor(anchor)
            DispatchQueue.main.async { onConsumedScrollRequest() }
        }
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.keys.removeMonitor()
        coordinator.memory.detach()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextView
        weak var textView: NoteContentTextView?
        weak var scrollView: NSScrollView?
        let keys = KeyboardScroller.Coordinator()
        let memory = ScrollMemory.Coordinator()

        private var renderedKey: String?
        private var findKey: String?
        private var revealKey: String?
        private var findRanges: [NSRange] = []

        init(_ parent: NoteTextView) { self.parent = parent }

        // MARK: Content

        func render(_ config: NoteTextView) {
            let key = "\(config.renderKey)|\(config.bodySize)|\(config.family.rawValue)|\(config.readableWidth)"
            guard key != renderedKey, let tv = textView else { return }
            renderedKey = key

            let renderer = NoteTextRenderer(bodySize: config.bodySize,
                                            family: config.family,
                                            contentWidth: config.readableWidth,
                                            loadImage: config.loadImage)
            let string = renderer.render(config.blocks)
            tv.textStorage?.setAttributedString(string)
            tv.cacheDecorations()
            // The text changed under it, so every find highlight is stale.
            findKey = nil
            revealKey = nil
            findRanges = []
        }

        // MARK: Find in page

        func applyFind(_ find: FindModel) {
            guard let tv = textView else { return }
            guard find.active, !find.query.isEmpty else {
                if !findRanges.isEmpty { tv.clearFindHighlights(); findRanges = [] }
                findKey = nil; revealKey = nil
                if find.total != 0 { DispatchQueue.main.async { find.total = 0 } }
                return
            }

            let key = "\(renderedKey ?? "")|\(find.caseSensitive)|\(find.query)"
            if key != findKey {
                findKey = key
                findRanges = tv.ranges(of: find.query, options: find.options)
                tv.highlightFindMatches(findRanges)
                let count = findRanges.count
                DispatchQueue.main.async {
                    if find.total != count { find.total = count }
                    if find.current >= count { find.current = max(0, count - 1) }
                }
            }

            let reveal = "\(key)|\(find.current)"
            if reveal != revealKey, findRanges.indices.contains(find.current) {
                revealKey = reveal
                tv.revealFindMatch(findRanges[find.current], among: findRanges)
            }
        }

        // MARK: Anchors

        func scrollToAnchor(_ anchor: Int) {
            guard let tv = textView, let storage = tv.textStorage else { return }
            var target: NSRange?
            storage.enumerateAttribute(.folioAnchor, in: storage.fullRange) { value, range, stop in
                if (value as? Int) == anchor { target = range; stop.pointee = true }
            }
            guard let target else { return }
            tv.scrollToTop(of: target)
        }

        // MARK: Delegate

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let url = (link as? URL) ?? (link as? String).flatMap { URL(string: $0) }
            guard let url else { return false }
            return parent.onOpenLink(url)
        }
    }
}

// MARK: - The text view

/// Read-only note surface: draws the block decorations TextKit has no concept of
/// (code cards, callouts, quote bars, rules), toggles task checkboxes on click,
/// and copies attachment blocks as their Markdown source.
final class NoteContentTextView: NSTextView {
    var readableWidth: CGFloat = 720
    var onToggleTask: (Int) -> Void = { _ in }

    private var decorations: [(range: NSRange, decoration: BlockDecoration)] = []

    // MARK: Layout

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        applyReadableInset()
    }

    /// Size and center the reading column.
    ///
    /// Both the container width *and* the inset are set here, in that order,
    /// because `widthTracksTextView` would otherwise resize the container from the
    /// stale inset on every `setFrameSize` and re-wrap the text twice per frame —
    /// the jitter you get dragging the sidebar. Setting the width ourselves means a
    /// sidebar slide moves the column without re-wrapping it at all: the width only
    /// changes once the pane is narrower than the column.
    func applyReadableInset() {
        let margin = sideMargin
        let available = max(bounds.width - margin * 2, 200)
        let column = min(readableWidth, available)
        if let container = textContainer, abs(container.size.width - column) > 0.5 {
            container.size = NSSize(width: column, height: CGFloat.greatestFiniteMagnitude)
        }
        // Whole points: a half-pixel inset shifts every glyph off the pixel grid
        // and makes the text shimmer while the pane animates.
        let inset = max(margin, ((bounds.width - column) / 2).rounded())
        if abs(textContainerInset.width - inset) > 0.5 {
            textContainerInset = NSSize(width: inset, height: textContainerInset.height)
        }
    }

    /// In column mode this is just a floor for a pane too narrow to hold the
    /// column. Full width has no centering to create margins, so it needs a real
    /// one — scaled to the pane, or the text ends up against the window chrome and
    /// the scroller on a wide display.
    private var sideMargin: CGFloat {
        guard !readableWidth.isFinite else { return 32 }
        return min(120, max(64, (bounds.width * 0.06).rounded()))
    }

    // MARK: Decorations

    func cacheDecorations() {
        guard let storage = textStorage else { decorations = []; return }
        var found: [(NSRange, BlockDecoration)] = []
        storage.enumerateAttribute(.folioDecoration, in: storage.fullRange) { value, range, _ in
            if let box = value as? DecorationBox { found.append((range, box.value)) }
        }
        decorations = found
        needsDisplay = true
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard !decorations.isEmpty, let layoutManager = textLayoutManager else { return }
        let origin = textContainerOrigin

        // Only decorations near the viewport. Measuring one means asking TextKit
        // for its segment rects, which lays that range out — so walking all of
        // them would lay out the whole document on every draw pass (the trap
        // `MarkdownTextView.drawBackground` documents, in its TextKit 2 form).
        guard let visible = visibleCharacterRange() else { return }

        for (range, decoration) in decorations where NSIntersectionRange(range, visible).length > 0
                                                     || NSLocationInRange(range.location, visible) {
            guard let frame = boundingRect(for: range, using: layoutManager) else { continue }
            var box = frame.offsetBy(dx: origin.x, dy: origin.y)
            guard box.intersects(rect) else { continue }

            switch decoration {
            case .code:
                box = box.insetBy(dx: -10, dy: -8)
                NSColor.labelColor.withAlphaComponent(0.06).setFill()
                NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()

            case let .callout(kind):
                let tint = NoteTextRenderer.calloutTint(kind)
                box = box.insetBy(dx: -10, dy: -8)
                tint.withAlphaComponent(0.12).setFill()
                NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()
                tint.withAlphaComponent(0.7).setFill()
                NSBezierPath(roundedRect: NSRect(x: box.minX, y: box.minY, width: 3, height: box.height),
                             xRadius: 1.5, yRadius: 1.5).fill()

            case .quote:
                let bar = NSRect(x: box.minX - 14, y: box.minY, width: 3, height: box.height)
                NSColor.secondaryLabelColor.withAlphaComponent(0.5).setFill()
                NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()

            case .divider:
                let y = box.midY.rounded()
                NSColor.separatorColor.setFill()
                NSRect(x: box.minX, y: y, width: max(box.width, bounds.width - box.minX * 2), height: 1).fill()
            }
        }
    }

    /// Character range currently laid out for display, padded by a screen's worth
    /// either side so a decoration straddling the edge still paints.
    private func visibleCharacterRange() -> NSRange? {
        guard let layoutManager = textLayoutManager,
              let content = layoutManager.textContentManager,
              let viewport = layoutManager.textViewportLayoutController.viewportRange
        else { return nil }
        let origin = content.documentRange.location
        let start = content.offset(from: origin, to: viewport.location)
        let end = content.offset(from: origin, to: viewport.endLocation)
        guard start != NSNotFound, end != NSNotFound, end >= start else { return nil }
        let slack = 4096
        let lower = max(0, start - slack)
        let upper = min((string as NSString).length, end + slack)
        return NSRange(location: lower, length: upper - lower)
    }

    /// Union of the layout segments for a character range, in container space.
    private func boundingRect(for range: NSRange, using layoutManager: NSTextLayoutManager) -> NSRect? {
        guard let textRange = layoutManager.textRange(for: range) else { return nil }
        var result = NSRect.null
        layoutManager.enumerateTextSegments(in: textRange, type: .standard,
                                            options: [.rangeNotRequired]) { _, frame, _, _ in
            result = result.isNull ? frame : result.union(frame)
            return true
        }
        return result.isNull ? nil : result
    }

    // MARK: Find

    func ranges(of query: String, options: NSString.CompareOptions) -> [NSRange] {
        let text = string as NSString
        guard !query.isEmpty, text.length > 0 else { return [] }
        var out: [NSRange] = []
        var searchRange = NSRange(location: 0, length: text.length)
        while searchRange.length > 0 {
            let r = text.range(of: query, options: options, range: searchRange)
            if r.location == NSNotFound { break }
            out.append(r)
            let next = r.location + max(r.length, 1)
            if next >= text.length { break }
            searchRange = NSRange(location: next, length: text.length - next)
        }
        return out
    }

    /// Highlight via *rendering* attributes so the text storage stays untouched —
    /// the same non-destructive approach writing mode uses.
    func highlightFindMatches(_ ranges: [NSRange]) {
        guard let layoutManager = textLayoutManager else { return }
        clearFindHighlights()
        for r in ranges {
            guard let textRange = layoutManager.textRange(for: r) else { continue }
            layoutManager.addRenderingAttribute(.backgroundColor,
                                                value: NSColor.systemYellow.withAlphaComponent(0.4),
                                                for: textRange)
        }
    }

    func clearFindHighlights() {
        guard let layoutManager = textLayoutManager else { return }
        layoutManager.removeRenderingAttribute(.backgroundColor, for: layoutManager.documentRange)
        layoutManager.removeRenderingAttribute(.foregroundColor, for: layoutManager.documentRange)
    }

    /// Tint the current match more strongly, scroll it into view, and flash it.
    func revealFindMatch(_ range: NSRange, among all: [NSRange]) {
        guard let layoutManager = textLayoutManager else { return }
        highlightFindMatches(all)
        if let textRange = layoutManager.textRange(for: range) {
            layoutManager.addRenderingAttribute(.backgroundColor,
                                                value: NSColor.systemOrange.withAlphaComponent(0.9),
                                                for: textRange)
            layoutManager.addRenderingAttribute(.foregroundColor, value: NSColor.black, for: textRange)
        }
        scrollRangeToVisible(range)
        showFindIndicator(for: range)
    }

    /// Put a range near the top of the viewport (outline jumps read better there
    /// than centered).
    func scrollToTop(of range: NSRange) {
        guard let layoutManager = textLayoutManager,
              let frame = boundingRect(for: range, using: layoutManager),
              let clip = enclosingScrollView?.contentView else {
            scrollRangeToVisible(range)
            return
        }
        let y = max(0, frame.minY + textContainerOrigin.y - 12)
        let maxY = max(0, (enclosingScrollView?.documentView?.frame.height ?? 0) - clip.bounds.height)
        clip.animator().setBoundsOrigin(NSPoint(x: 0, y: min(y, maxY)))
        enclosingScrollView?.reflectScrolledClipView(clip)
    }

    // MARK: Interaction

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = checkboxIndex(at: point) {
            onToggleTask(index)
            return
        }
        super.mouseDown(with: event)
    }

    private func checkboxIndex(at point: NSPoint) -> Int? {
        guard let storage = textStorage, storage.length > 0 else { return nil }
        let index = characterIndexForInsertion(at: point)
        // The insertion index can land either side of the checkbox glyph.
        for candidate in [index, index - 1] where candidate >= 0 && candidate < storage.length {
            if let value = storage.attribute(.folioCheckbox, at: candidate, effectiveRange: nil) as? Int {
                return value
            }
        }
        return nil
    }

    /// Copy the selection as text, substituting the Markdown source of any
    /// attachment blocks (tables, the properties card, images) it spans.
    override func copy(_ sender: Any?) {
        guard let storage = textStorage else { return super.copy(sender) }
        let selection = selectedRange()
        guard selection.length > 0 else { return super.copy(sender) }

        let out = NSMutableString()
        storage.enumerateAttributes(in: selection) { attrs, range, _ in
            if let source = attrs[.folioSource] as? String {
                out.append(source)
            } else if attrs[.folioBlockBreak] != nil {
                // The gap between blocks is drawn with paragraph spacing, not a
                // blank line — put the blank line back for the pasteboard.
                out.append("\n\n")
            } else {
                out.append((storage.string as NSString).substring(with: range))
            }
        }
        // Soft breaks are a layout device; the pasteboard wants real newlines.
        out.replaceOccurrences(of: "\u{2028}", with: "\n", options: [],
                               range: NSRange(location: 0, length: out.length))
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(out as String, forType: .string)
    }

    /// A non-editable text view still has to take first responder, or ⌘A and the
    /// selection-extending keys never reach it.
    override var acceptsFirstResponder: Bool { true }
}

// MARK: - TextKit 2 range bridging

extension NSTextLayoutManager {
    /// `NSRange` (character offsets) → `NSTextRange` (opaque locations).
    func textRange(for range: NSRange) -> NSTextRange? {
        guard let content = textContentManager,
              let start = content.location(content.documentRange.location, offsetBy: range.location),
              let end = content.location(start, offsetBy: range.length) else { return nil }
        return NSTextRange(location: start, end: end)
    }
}
#endif
