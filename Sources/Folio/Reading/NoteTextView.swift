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
    /// Body and dimmed text from the theme.
    let textColor: NSColor
    let secondaryTextColor: NSColor
    /// How find matches are painted; the current one gets the stronger of the two.
    let findMatch: Highlight
    let findCurrentMatch: Highlight
    let noteID: URL?
    /// Whether reading mode is the mode on screen. The reader stays mounted while
    /// writing (see `EditorPane`), so this is the only signal that it is visible.
    let isActive: Bool
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
        tv.findMatch = findMatch
        tv.findCurrentMatch = findCurrentMatch
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
        // Decorated paragraphs get a fragment that paints its own card/bar/rule
        // (see `DecoratedLayoutFragment`).
        tv.textLayoutManager?.delegate = context.coordinator
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
        tv.findMatch = findMatch
        tv.findCurrentMatch = findCurrentMatch
        if tv.readableWidth != readableWidth {
            tv.readableWidth = readableWidth
            tv.applyReadableInset()
        }

        coordinator.render(self)
        coordinator.becameActive(isActive, in: tv)

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
    final class Coordinator: NSObject, NSTextViewDelegate, @preconcurrency NSTextLayoutManagerDelegate {
        var parent: NoteTextView
        weak var textView: NoteContentTextView?
        weak var scrollView: NSScrollView?
        let keys = KeyboardScroller.Coordinator()
        let memory = ScrollMemory.Coordinator()

        private var wasActive = true
        private var renderedKey: String?
        private var findKey: String?
        private var revealKey: String?
        private var findRanges: [NSRange] = []

        init(_ parent: NoteTextView) { self.parent = parent }

        // MARK: Content

        func render(_ config: NoteTextView) {
            // The palette is part of the rendered string, so a theme switch has to
            // re-render. A light/dark switch does not — those colors are dynamic
            // and re-resolve at draw time.
            let key = "\(config.renderKey)|\(config.bodySize)|\(config.family.rawValue)"
                + "|\(config.readableWidth)"
                + "|\(config.textColor.hashValue)|\(config.secondaryTextColor.hashValue)"
            guard key != renderedKey, let tv = textView else { return }
            renderedKey = key

            let renderer = NoteTextRenderer(bodySize: config.bodySize,
                                            family: config.family,
                                            contentWidth: config.readableWidth,
                                            textColor: config.textColor,
                                            secondaryTextColor: config.secondaryTextColor,
                                            loadImage: config.loadImage)
            let string = renderer.render(config.blocks)
            tv.textStorage?.setAttributedString(string)
            tv.cacheHostedBlocks()
            // The new string carries brand-new hosted blocks; nothing else fires
            // for a re-render that moves neither window, mode, nor scroll offset
            // (⌘+/⌘−, switching between notes both resting at the top).
            tv.scheduleHealPass()
            // The text changed under it, so every find highlight is stale.
            findKey = nil
            revealKey = nil
            findRanges = []
        }

        /// Reading mode came back to the front. Hosted blocks (tables, the
        /// properties card) have to be laid out again: TextKit can lay a fragment
        /// out while the reader is hidden behind the editor, and a fragment laid
        /// out then never gets its hosted view — it draws the generic attachment
        /// icon in its place, and nothing re-measures it afterwards.
        func becameActive(_ active: Bool, in tv: NoteContentTextView) {
            defer { wasActive = active }
            guard active, !wasActive else { return }
            tv.scheduleHealPass()
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

        /// A paragraph carrying a block decoration lays out as a fragment that
        /// draws it. The decoration covers the whole block, so the first
        /// character is as good as any.
        func textLayoutManager(_ textLayoutManager: NSTextLayoutManager,
                               textLayoutFragmentFor location: NSTextLocation,
                               in textElement: NSTextElement) -> NSTextLayoutFragment {
            if let paragraph = textElement as? NSTextParagraph,
               paragraph.attributedString.length > 0,
               let box = paragraph.attributedString.attribute(.folioDecoration, at: 0,
                                                              effectiveRange: nil) as? DecorationBox {
                return DecoratedLayoutFragment(textElement: textElement, range: textElement.elementRange,
                                               decoration: box.value)
            }
            return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
        }
    }
}

// MARK: - Block decorations

/// A paragraph with a block decoration (code card, callout fill, quote bar,
/// rule) draws it itself, underneath its own text.
///
/// TextKit 2 renders text into fragment surfaces of its own, placed by each
/// viewport layout pass — not by the text view's draw pass. A decoration
/// painted in `drawBackground` from measured fragment geometry is therefore
/// only right until the next layout pass moves the text without redrawing the
/// view. That is routine when a note opens at a remembered scroll offset:
/// TextKit refines the estimated heights above the viewport over several
/// passes, the text settles, and the boxes stayed where the text *used* to be
/// until a click forced a redraw. Drawing inside the fragment ties each
/// decoration to the text it decorates, whatever moves it.
final class DecoratedLayoutFragment: NSTextLayoutFragment {
    let decoration: BlockDecoration

    init(textElement: NSTextElement, range: NSTextRange?, decoration: BlockDecoration) {
        self.decoration = decoration
        super.init(textElement: textElement, range: range)
    }

    required init?(coder: NSCoder) { nil }

    /// The card is inset outward from the text, the quote bar hangs left of it,
    /// and the rule runs the column's width: the surface has to cover them or
    /// they are clipped.
    override var renderingSurfaceBounds: CGRect {
        var bounds = super.renderingSurfaceBounds.union(textBox.insetBy(dx: -24, dy: -12))
        if case .divider = decoration {
            bounds = bounds.union(CGRect(x: 0, y: bounds.minY, width: columnWidth, height: 1))
        }
        return bounds
    }

    /// The fragment frame is only as wide as its text, so the rule takes its
    /// width from the container — the reading column.
    private var columnWidth: CGFloat {
        textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.width
    }

    /// Union of the laid-out lines, in fragment coordinates.
    private var textBox: CGRect {
        textLineFragments.reduce(CGRect.null) { $0.union($1.typographicBounds) }
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        let box = textBox
        if !box.isNull {
            context.saveGState()
            context.translateBy(x: point.x, y: point.y)
            drawDecoration(around: box, in: context)
            context.restoreGState()
        }
        super.draw(at: point, in: context)
    }

    private func drawDecoration(around text: CGRect, in context: CGContext) {
        func fill(_ rect: CGRect, radius: CGFloat, _ color: NSColor) {
            context.setFillColor(color.cgColor)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.fillPath()
        }
        switch decoration {
        case .code:
            fill(text.insetBy(dx: -10, dy: -8), radius: 10, NSColor.labelColor.withAlphaComponent(0.06))

        case let .callout(kind):
            // Fragments draw on the main thread; the renderer's palette lives there.
            let tint = MainActor.assumeIsolated { NoteTextRenderer.calloutTint(kind) }
            let card = text.insetBy(dx: -10, dy: -8)
            fill(card, radius: 10, tint.withAlphaComponent(0.12))
            fill(CGRect(x: card.minX, y: card.minY, width: 3, height: card.height),
                 radius: 1.5, tint.withAlphaComponent(0.7))

        case .quote:
            fill(CGRect(x: text.minX - 14, y: text.minY, width: 3, height: text.height),
                 radius: 1.5, NSColor.secondaryLabelColor.withAlphaComponent(0.5))

        case .divider:
            // Symmetric in the column: the fragment sits `layoutFragmentFrame.minX`
            // (line-fragment padding) into the container, and the text
            // `text.minX` into the fragment, so the rule stops that far short of
            // the right edge too.
            let y = text.midY.rounded()
            let margin = layoutFragmentFrame.minX + text.minX
            fill(CGRect(x: text.minX, y: y, width: max(text.width, columnWidth - margin * 2), height: 1),
                 radius: 0, NSColor.separatorColor)
        }
    }
}

// MARK: - The text view

/// Read-only note surface: toggles task checkboxes on click, highlights find
/// matches, heals hosted blocks, and copies attachment blocks as their Markdown
/// source. Block decorations are drawn by `DecoratedLayoutFragment`.
final class NoteContentTextView: NSTextView {
    var readableWidth: CGFloat = 720
    var findMatch = Highlight(background: .systemYellow.withAlphaComponent(0.4))
    var findCurrentMatch = Highlight(background: .systemOrange.withAlphaComponent(0.9),
                                     foreground: .black)
    var onToggleTask: (Int) -> Void = { _ in }

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

    // MARK: Hosted blocks

    /// Hosted-block positions, so the heal pass doesn't sweep the whole storage
    /// on every scroll frame.
    func cacheHostedBlocks() {
        guard let storage = textStorage else { hostedBlockRanges = []; return }
        var hosted: [NSRange] = []
        storage.enumerateAttribute(.attachment, in: storage.fullRange) { value, range, _ in
            if value is HostedBlockAttachment { hosted.append(range) }
        }
        hostedBlockRanges = hosted
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
                                                value: findMatch.background, for: textRange)
            if let ink = findMatch.foreground {
                layoutManager.addRenderingAttribute(.foregroundColor, value: ink, for: textRange)
            }
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
                                                value: findCurrentMatch.background, for: textRange)
            if let ink = findCurrentMatch.foreground {
                layoutManager.addRenderingAttribute(.foregroundColor, value: ink, for: textRange)
            }
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

    // MARK: Hosted-block healing

    /// TextKit 2 installs an attachment's view only during a viewport layout
    /// pass that happens while the text view is actually displayed. A fragment
    /// laid out at any other moment — before the view joins the window, while
    /// the reader sits hidden behind the editor, during the mode-switch
    /// animation — keeps that layout as final, and its view is never installed:
    /// the block renders as the generic attachment icon, or as nothing at all.
    ///
    /// The one reliable recovery is to invalidate the fragment while the view is
    /// displayed and the fragment is in the viewport. This pass does exactly
    /// that for every hosted block whose view isn't installed, and runs at the
    /// moments visibility can have changed: joining a window, returning to
    /// reading mode, and scrolling (fragments enter the viewport pre-laid-out).
    private var hostedBlockRanges: [NSRange] = []

    func healHostedBlocks() {
        guard window != nil, !isHiddenOrHasHiddenAncestor,
              let layoutManager = textLayoutManager, let storage = textStorage else { return }
        let viewport = layoutManager.textViewportLayoutController.viewportRange
        for range in hostedBlockRanges {
            guard range.location < storage.length,
                  let attachment = storage.attribute(.attachment, at: range.location,
                                                     effectiveRange: nil) as? HostedBlockAttachment,
                  attachment.liveProvider?.view?.superview == nil,
                  let textRange = layoutManager.textRange(for: range) else { continue }
            // Only blocks the viewport can see: an off-screen block gets its
            // chance when it scrolls in (the scroll observer re-runs this).
            if let viewport, !viewport.intersects(textRange) { continue }
            layoutManager.invalidateLayout(for: textRange)
        }
    }

    /// Coalesced trigger for `healHostedBlocks` — scrolling fires the clip-view
    /// notification for every frame of the scroll.
    private var healScheduled = false
    func scheduleHealPass() {
        guard !healScheduled else { return }
        healScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.healScheduled = false
            self.healHostedBlocks()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleHealPass()
    }

    private var scrollObserver: NSObjectProtocol?
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if let observer = scrollObserver { NotificationCenter.default.removeObserver(observer) }
        scrollObserver = nil
        guard let clip = superview as? NSClipView else { return }
        clip.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
        ) { [weak self] _ in
            self?.scheduleHealPass()
        }
    }

    /// A non-editable text view still has to take first responder, or ⌘A and the
    /// selection-extending keys never reach it.
    override var acceptsFirstResponder: Bool { true }

    deinit {
        if let observer = scrollObserver { NotificationCenter.default.removeObserver(observer) }
    }
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
