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
    /// Width of the reading column; the hosted view is measured against it.
    let width: CGFloat
    /// A concrete width to lay the hosted view out at. `width` may be `.infinity`
    /// in full-width mode, which is not something you can hand to a frame.
    var measurementWidth: CGFloat { width.isFinite ? width : 900 }

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

    init(rootView: AnyView, width: CGFloat) {
        self.rootView = rootView
        self.width = width
        super.init(data: nil, ofType: nil)
        // The hosted view can change its own height (the properties card expands),
        // so let TextKit re-measure instead of caching our first answer.
        allowsTextAttachmentView = true
        lineLayoutPadding = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewProvider(for parentView: NSView?,
                               location: NSTextLocation,
                               textContainer: NSTextContainer?) -> NSTextAttachmentViewProvider? {
        let provider = HostedBlockViewProvider(textAttachment: self,
                                               parentView: parentView,
                                               textLayoutManager: textContainer?.textLayoutManager,
                                               location: location)
        provider.tracksTextAttachmentViewBounds = true
        return provider
    }
}

final class HostedBlockViewProvider: NSTextAttachmentViewProvider {
    /// Stand-in height for a hosted view that hasn't reported a size yet.
    private static let provisionalHeight: CGFloat = 44

    private var hostedWidth: CGFloat = -1
    /// The height last handed to TextKit, so a report that matches it is ignored
    /// and the invalidate → re-measure → report cycle terminates.
    private var reportedHeight: CGFloat = -1

    override func loadView() {
        guard let attachment = textAttachment as? HostedBlockAttachment else { return }
        hostedWidth = attachment.measurementWidth
        view = NSHostingView(rootView: attachment.sized(to: hostedWidth) { [weak self] height in
            self?.contentHeightChanged(height)
        })
    }

    /// The hosted block changed height (the properties card expanded). Ask TextKit
    /// to re-lay this attachment so it asks us for the new bounds.
    private func contentHeightChanged(_ height: CGFloat) {
        guard abs(ceil(height) - reportedHeight) > 0.5 else { return }
        guard let layoutManager = textLayoutManager,
              let content = layoutManager.textContentManager,
              let end = content.location(location, offsetBy: 1),
              let range = NSTextRange(location: location, end: end) else { return }
        layoutManager.invalidateLayout(for: range)
    }

    override func attachmentBounds(for attributes: [NSAttributedString.Key: Any],
                                   location: NSTextLocation,
                                   textContainer: NSTextContainer?,
                                   proposedLineFragment: CGRect,
                                   position: CGPoint) -> CGRect {
        guard let attachment = textAttachment as? HostedBlockAttachment,
              let host = view as? NSHostingView<AnyView> else {
            return .zero
        }
        let proposed = proposedLineFragment.width > 1 ? proposedLineFragment.width : attachment.measurementWidth
        let width = max(min(attachment.width, proposed), 1)
        // Re-host at the real width rather than resizing the frame: the width has
        // to be pinned *inside* SwiftUI, or the hosting view reports the height of
        // its ideal (unwrapped) layout — which is how a wide table ended up
        // measuring near-zero and rendering as the generic attachment icon.
        if abs(hostedWidth - width) > 0.5 {
            hostedWidth = width
            host.rootView = attachment.sized(to: width) { [weak self] height in
                self?.contentHeightChanged(height)
            }
            host.layoutSubtreeIfNeeded()
        }
        let measured = max(host.intrinsicContentSize.height, host.fittingSize.height)
        // Never return zero: TextKit reads that as "no view" and draws the generic
        // attachment icon. `tracksTextAttachmentViewBounds` re-measures once the
        // hosted view settles, so a provisional height self-corrects.
        let height = measured > 1 ? measured : Self.provisionalHeight
        reportedHeight = ceil(height)
        return CGRect(x: 0, y: 0, width: width, height: reportedHeight)
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
struct TableBlockView: View {
    let headers: [String]
    let rows: [[String]]
    let bodySize: CGFloat

    private var columns: Int { max(headers.count, rows.map(\.count).max() ?? 0) }
    private var cellSize: CGFloat { bodySize * Typography.table }

    var body: some View {
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
    }

    private func row(_ cells: [String], bold: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<columns, id: \.self) { c in
                Text(c < cells.count
                     ? InlineMarkdown.render(cells[c], codeSize: cellSize * Typography.inlineCode)
                     : AttributedString(""))
                    .font(.system(size: cellSize, weight: bold ? .semibold : .regular))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                if c < columns - 1 { Divider() }
            }
        }
    }
}

#endif
