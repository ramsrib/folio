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
    override func loadView() {
        guard let attachment = textAttachment as? HostedBlockAttachment else { return }
        let host = NSHostingView(rootView: attachment.rootView)
        // Grow vertically with the content, stay pinned to the column width.
        host.sizingOptions = [.intrinsicContentSize]
        view = host
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
        let width = min(attachment.width, max(proposedLineFragment.width, 1))
        // Pin the width, then ask what height the content needs at that width.
        host.frame.size.width = width
        host.layoutSubtreeIfNeeded()
        let height = max(host.fittingSize.height, host.intrinsicContentSize.height)
        return CGRect(x: 0, y: 0, width: width, height: ceil(height))
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
