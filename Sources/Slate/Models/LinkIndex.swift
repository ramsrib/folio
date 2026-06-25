import Foundation

/// A note that links *to* the current note (an inbound link), with a snippet of
/// the line it appears on.
struct Backlink: Identifiable, Hashable {
    let source: URL
    let sourceName: String
    let context: String
    var id: String { source.path + "|" + context }
}

/// A heading in the current note, for the outline panel.
struct OutlineItem: Identifiable, Hashable {
    let id = UUID()
    let level: Int
    let title: String
    let charIndex: Int   // character offset of the heading line, for scroll-to
}
