#if os(macOS)
import AppKit
import SwiftUI

/// A block-level SwiftUI view embedded in the note's text stream.
///
/// Used for the two blocks that genuinely aren't text — the properties card and
/// tables. Because the attachment is a single character in the same string, a
/// selection can run straight through it, and `NoteTextView` substitutes the
/// block's Markdown source when copying.
final class HostedBlockAttachment: NSTextAttachment {
    let rootView: AnyView
    /// The same block, laid out purely to be measured. Usually `rootView`; a
    /// table hands over its bare grid, because the scrolling island it displays
    /// through would report the *clipped* height, not the real one.
    let measureView: AnyView
    /// Width of the reading column; the hosted view is measured against it.
    let width: CGFloat
    /// A concrete width to lay the hosted view out at. `width` may be `.infinity`
    /// in full-width mode, which is not something you can hand to a frame.
    var measurementWidth: CGFloat { width.isFinite ? width : 900 }

    /// Off-screen twin of the block, kept solely to answer "how tall is this?".
    ///
    /// The height has to come from something we own. Asking the *displayed* view
    /// — directly, or through `tracksTextAttachmentViewBounds` — is a race: a
    /// hosting view is born zero-sized and only becomes its real size once
    /// SwiftUI lays it out, so whichever side gets there first decides whether
    /// the block renders or collapses to the generic attachment icon.
    private var measurer: NSHostingView<AnyView>?
    private var measuredWidth: CGFloat = -1
    /// Height last reported by a live displayed view, and the width it was laid
    /// out at. It wins over the measured height when present — only the real
    /// view knows it has been expanded — but never at a different width: a
    /// height carried across a resize would reserve the wrong space until the
    /// view reloads, and the page would visibly jump.
    private var liveHeight: CGFloat = 0
    private var liveWidth: CGFloat = -1

    /// Height of the block at `width`, from the off-screen twin.
    func height(at width: CGFloat) -> CGFloat {
        if liveHeight > 1, abs(liveWidth - width) <= 0.5 { return liveHeight }
        if measurer == nil || abs(measuredWidth - width) > 0.5 {
            measuredWidth = width
            let pinned = AnyView(measureView
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true))
            if let host = measurer { host.rootView = pinned } else { measurer = NSHostingView(rootView: pinned) }
            measurer?.layoutSubtreeIfNeeded()
        }
        return max(measurer?.fittingSize.height ?? 0, 1)
    }

    /// A displayed view settled at a height — the properties card expanding, or
    /// simply finishing its first layout.
    func report(height: CGFloat, at width: CGFloat) {
        guard height > 1 else { return }
        liveHeight = height
        liveWidth = width
    }
    /// Current answer, so a report that changes nothing doesn't churn layout.
    var currentHeight: CGFloat { liveHeight }
    /// The column changed width; the old live height no longer describes it.
    func forgetLiveHeight() { liveHeight = 0 }

    /// The provider showing this block right now, so the displayed view can be
    /// re-laid at whatever width TextKit ends up giving us.
    weak var liveProvider: HostedBlockViewProvider?

    /// Deterministic bounds for the block, shared by the attachment- and
    /// provider-side `attachmentBounds` overrides (TextKit consults one or the
    /// other depending on configuration).
    func measuredBounds(proposedWidth: CGFloat) -> CGRect {
        let proposed = proposedWidth > 1 ? proposedWidth : measurementWidth
        let w = max(min(width, proposed), 1)
        liveProvider?.host(at: w)
        return CGRect(x: 0, y: 0, width: w, height: ceil(height(at: w)))
    }

    override func attachmentBounds(for attributes: [NSAttributedString.Key: Any],
                                   location: NSTextLocation,
                                   textContainer: NSTextContainer?,
                                   proposedLineFragment: CGRect,
                                   position: CGPoint) -> CGRect {
        measuredBounds(proposedWidth: proposedLineFragment.width)
    }

    /// The block, hard-pinned to a width so SwiftUI reports the wrapped height,
    /// and reporting that height whenever it changes.
    ///
    /// The report is what makes a block that *grows* work (the properties card
    /// expanding). `tracksTextAttachmentViewBounds` cannot do it: it watches the
    /// hosted view's bounds, but TextKit sets those bounds *from*
    /// `attachmentBounds`, so the view never resizes itself and nothing ever
    /// re-measures — the card just gets clipped to its collapsed height.
    func sized(to width: CGFloat, onHeightChange: @escaping (CGFloat) -> Void) -> AnyView {
        AnyView(
            rootView
                .frame(width: width)
                // Take the ideal height rather than whatever TextKit last forced,
                // or the reported height would just echo the stale value back.
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeightChange($0) }
        )
    }

    init(rootView: AnyView, measureView: AnyView? = nil, width: CGFloat) {
        self.rootView = rootView
        self.measureView = measureView ?? rootView
        self.width = width
        super.init(data: nil, ofType: nil)
        // The hosted view can change its own height (the properties card expands),
        // so let TextKit re-measure instead of caching our first answer.
        allowsTextAttachmentView = true
        lineLayoutPadding = 0
        // The fragment can draw before the hosted view is installed (the heal
        // pass in `NoteContentTextView` installs it a beat later). With no image
        // TextKit fills that beat with its generic document icon — a visible
        // white flash on every scroll-in. An empty image draws nothing.
        image = NSImage(size: NSSize(width: 1, height: 1))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewProvider(for parentView: NSView?,
                               location: NSTextLocation,
                               textContainer: NSTextContainer?) -> NSTextAttachmentViewProvider? {
        let provider = HostedBlockViewProvider(textAttachment: self,
                                               parentView: parentView,
                                               textLayoutManager: textContainer?.textLayoutManager,
                                               location: location)
        // `true` is what makes NSTextView install the provider's view as a
        // rendering surface at all — with `false` it loads the view and never
        // shows it. Sizing does NOT come from the view though: both
        // `attachmentBounds` overrides answer from our own measurement.
        provider.tracksTextAttachmentViewBounds = true
        return provider
    }

}

final class HostedBlockViewProvider: NSTextAttachmentViewProvider {
    private var hostedWidth: CGFloat = -1

    override func loadView() {
        guard let attachment = textAttachment as? HostedBlockAttachment else { return }
        attachment.liveProvider = self
        // A fresh view starts in its own state — the properties card comes back
        // collapsed — so whatever the last one reported no longer describes it.
        // Measure again, and let this view report once it has settled.
        attachment.forgetLiveHeight()
        if hostedWidth < 0 { hostedWidth = attachment.measurementWidth }
        view = hostingView(for: attachment, at: hostedWidth)
    }

    /// Lay the displayed view out at the width TextKit is actually giving the
    /// block. The width has to be pinned *inside* SwiftUI — resizing the frame
    /// leaves the hosted view reporting its unwrapped ideal layout.
    func host(at width: CGFloat) {
        guard abs(hostedWidth - width) > 0.5 else { return }
        hostedWidth = width
        guard let attachment = textAttachment as? HostedBlockAttachment else { return }
        // A different column width means a different height; re-measure rather
        // than trusting what the old layout reported.
        attachment.forgetLiveHeight()
        guard let host = view as? NSHostingView<AnyView> else { return }
        host.rootView = attachment.sized(to: width) { [weak self] height in
            self?.contentHeightChanged(height)
        }
        host.layoutSubtreeIfNeeded()
    }

    private func hostingView(for attachment: HostedBlockAttachment, at width: CGFloat) -> NSHostingView<AnyView> {
        let host = NSHostingView(rootView: attachment.sized(to: width) { [weak self] height in
            self?.contentHeightChanged(height)
        })
        host.frame.size = host.fittingSize
        return host
    }

    /// The hosted block settled at a height — the properties card expanded, or a
    /// first layout finished. Record it and ask TextKit to re-lay this
    /// attachment, which then asks the attachment for the new bounds.
    private func contentHeightChanged(_ height: CGFloat) {
        guard let attachment = textAttachment as? HostedBlockAttachment else { return }
        let settled = ceil(height)
        guard settled > 1, abs(settled - attachment.currentHeight) > 0.5 else { return }
        attachment.report(height: settled, at: hostedWidth)
        invalidateOwnLayout()
    }

    override func attachmentBounds(for attributes: [NSAttributedString.Key: Any],
                                   location: NSTextLocation,
                                   textContainer: NSTextContainer?,
                                   proposedLineFragment: CGRect,
                                   position: CGPoint) -> CGRect {
        guard let attachment = textAttachment as? HostedBlockAttachment else { return .zero }
        let rect = attachment.measuredBounds(proposedWidth: proposedLineFragment.width)
        // Bounds can be asked before TextKit loads the view. Remember the real
        // width so `loadView` hosts at it, not at the fallback — hosting wide
        // and correcting a beat later reads as a reflow flicker.
        if view == nil { hostedWidth = rect.width }
        return rect
    }

    /// Re-lay just this attachment's character.
    func invalidateOwnLayout() {
        guard let layoutManager = textLayoutManager,
              let content = layoutManager.textContentManager,
              let end = content.location(location, offsetBy: 1),
              let range = NSTextRange(location: location, end: end) else { return }
        layoutManager.invalidateLayout(for: range)
    }
}

// MARK: - The blocks that stay SwiftUI

/// Frontmatter card, wrapped so it owns its own expand/collapse state (inside a
/// text attachment there's no parent view to hold it).
struct PropertiesBlockView: View {
    let props: [Prop]
    @State private var expanded = false

    var body: some View {
        PropertiesView(props: props, expanded: $expanded)
    }
}

/// Markdown table. A real grid — column widths have to respond to content, which
/// is the one thing a single text stream can't express.
///
/// Columns are sized to what's in them, not split evenly: an even split turns a
/// wide table into one character per line. When the natural widths outrun the
/// reading column the whole grid scrolls sideways instead of being squeezed.
struct TableBlockView: View {
    let headers: [String]
    let rows: [[String]]
    let bodySize: CGFloat
    /// Per-column widths, measured once at construction — `body` runs again every
    /// time the attachment re-hosts at a new width, and re-measuring every cell
    /// there would be quadratic on a big table.
    private let widths: [CGFloat]

    private var cellSize: CGFloat { bodySize * Typography.table }
    private static let hPad: CGFloat = 10
    private static let vPad: CGFloat = 6

    @MainActor init(headers: [String], rows: [[String]], bodySize: CGFloat) {
        self.headers = headers
        self.rows = rows
        self.bodySize = bodySize
        self.widths = Self.columnWidths(headers: headers, rows: rows,
                                        cellSize: bodySize * Typography.table)
    }

    /// The table itself, at its natural size. Displayed through a scroll island,
    /// and measured directly — the island would only ever report the height of
    /// whatever fits the column.
    var grid: some View {
        VStack(spacing: 0) {
            row(headers, bold: true)
            Divider()
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                row(r, bold: false)
                Divider()
            }
        }
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator))
        // Its own size, whatever width it is offered: the grid never squeezes,
        // it scrolls.
        .fixedSize()
    }

    var body: some View {
        ScrollIsland { grid }
        // The island is only as wide as the grid, so the rest of the column is
        // empty layout, not view: the note keeps that space, and a narrow table
        // sits at the margin instead of being centred by the attachment's frame.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ cells: [String], bold: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(widths.indices, id: \.self) { c in
                Text(c < cells.count
                     ? InlineMarkdown.render(cells[c], codeSize: cellSize * Typography.inlineCode)
                     : AttributedString(""))
                    .font(.system(size: cellSize, weight: bold ? .semibold : .regular))
                    .textSelection(.enabled)
                    .frame(width: widths[c], alignment: .topLeading)
                    .padding(.horizontal, Self.hPad).padding(.vertical, Self.vPad)
                if c < widths.count - 1 { Divider().frame(maxHeight: .infinity) }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Measurement

    /// The widest cell in each column, capped: one long prose cell should wrap
    /// rather than push every other column off the far edge.
    @MainActor
    private static func columnWidths(headers: [String], rows: [[String]],
                                     cellSize: CGFloat) -> [CGFloat] {
        let columns = max(headers.count, rows.map(\.count).max() ?? 0)
        guard columns > 0 else { return [] }
        let cap = cellSize * 28
        let floor = cellSize * 1.5
        // Measured semibold throughout: it's the header weight, and it covers a
        // bold run inside a body cell too. A hair generous beats a hair short —
        // short means an unwanted wrap.
        let font = NSFont.systemFont(ofSize: cellSize, weight: .semibold)
        let codeSize = cellSize * Typography.inlineCode
        var widths = [CGFloat](repeating: floor, count: columns)
        for c in 0..<columns {
            if c < headers.count {
                widths[c] = max(widths[c], measure(headers[c], font: font, codeSize: codeSize))
            }
            for r in rows where c < r.count {
                widths[c] = max(widths[c], measure(r[c], font: font, codeSize: codeSize))
            }
            widths[c] = min(widths[c], cap)
        }
        return widths
    }

    /// Width of one cell's rendered text on a single line. Measured off the
    /// *rendered* string so `**markers**` don't count toward the width.
    @MainActor
    private static func measure(_ raw: String, font: NSFont, codeSize: CGFloat) -> CGFloat {
        let text = String(InlineMarkdown.render(raw, codeSize: codeSize).characters)
        guard !text.isEmpty else { return 0 }
        let size = (text as NSString).size(withAttributes: [.font: font])
        return ceil(size.width) + 1
    }
}

/// A block that scrolls sideways when it outgrows the column, and leaves
/// vertical scrolling to the note behind it.
///
/// Not SwiftUI's `ScrollView`, which fails at both jobs here: it swallows the
/// vertical wheel events the reader needs, and inside a text attachment it
/// reports no ideal height, so the block cannot be measured reliably.
struct ScrollIsland<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    func makeNSView(context: Context) -> AxisLockedScrollView {
        let scroll = AxisLockedScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.verticalScrollElasticity = .none
        let host = NSHostingView(rootView: content)
        host.frame.size = host.fittingSize
        scroll.documentView = host
        // Born at its real size: a zero-sized island is measured as an empty block.
        scroll.frame.size = host.frame.size
        return scroll
    }

    func updateNSView(_ scroll: AxisLockedScrollView, context: Context) {
        guard let host = scroll.documentView as? NSHostingView<Content> else { return }
        host.rootView = content
        // The document view keeps its natural size; the clip view is what shrinks.
        host.frame.size = host.fittingSize
    }

    /// Measured off the hosted content, not the scroll view: an AppKit fitting
    /// size is always available, which is what keeps the attachment's height
    /// honest across re-layouts.
    func sizeThatFits(_ proposal: ProposedViewSize,
                      nsView: AxisLockedScrollView,
                      context: Context) -> CGSize? {
        guard let host = nsView.documentView as? NSHostingView<Content> else { return nil }
        let ideal = host.fittingSize
        let offered = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? ideal.width
        return CGSize(width: min(offered, ideal.width), height: ideal.height)
    }
}

/// Scroll view that claims only horizontal intent. A vertical wheel goes to the
/// responder behind it, so the note never gets stuck under the pointer.
final class AxisLockedScrollView: NSScrollView {
    /// Decided once per gesture: a trackpad swipe that starts vertical stays
    /// vertical, rather than flipping axis halfway through a diagonal drift.
    private var passesThrough = false

    override func scrollWheel(with event: NSEvent) {
        let gestureStart = event.phase == .began || (event.phase == [] && event.momentumPhase == [])
        if gestureStart {
            // Shift+wheel is how a mouse asks for sideways; everything else is
            // judged on which way the gesture actually leans.
            let sideways = event.modifierFlags.contains(.shift)
                || abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            passesThrough = !sideways
        }
        if passesThrough {
            nextResponder?.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

#endif
